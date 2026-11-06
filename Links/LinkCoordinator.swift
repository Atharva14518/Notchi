import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class LinkCoordinator: ObservableObject {
    static let shared = LinkCoordinator()
    enum Phase: Equatable { case idle, preparing, uploading, finishing, flying, landed, failed }
    enum Screen { case compose, myLinks }
    @Published private(set) var isPresenting = false
    @Published private(set) var item: ShelfItem?
    @Published var screen: Screen = .compose
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var fraction: Double = 0
    @Published private(set) var links: [SharedLink] = []
    @Published private(set) var result: SharedLink?
    @Published var message: String?
    @Published private(set) var isError = false
    @Published private(set) var successToken = 0
    @Published private(set) var account: LinkAccount?
    @Published private(set) var isRefreshing = false
    let auth: LinkAuthStore
    let config: LinkConfiguration
    private let api: LinkAPI
    private let uploadStore: LinkUploadStore
    private let secrets: any LinkSecretStore
    private let clipboard: NSPasteboard
    typealias UploaderFactory = (@escaping @Sendable (UUID, Double) -> Void, @escaping @Sendable (UUID, Bool) -> Void) -> any LinkUploading
    private let uploaderFactory: UploaderFactory
    private var jobs: [PendingLinkUpload] = []
    private var started = false
    @Published private(set) var isRestoring = false
    private var work: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var generation = UUID()
    private var operationID: UUID?
    private lazy var uploader: any LinkUploading = uploaderFactory( { [weak self] id, value in
        Task { @MainActor in self?.update(id, value: value) }
    }, { [weak self] id, success in
        Task { @MainActor in await self?.uploaded(id, success: success) }
    })
    init(auth: LinkAuthStore? = nil, config: LinkConfiguration? = nil, api: LinkAPI = .shared,
         uploadStore: LinkUploadStore = .shared, secrets: any LinkSecretStore = LinkKeychain(), clipboard: NSPasteboard? = nil,
         uploaderFactory: @escaping UploaderFactory = { BackgroundLinkUploader(progress: $0, completion: $1) }) {
        self.auth = auth ?? .shared; self.config = config ?? .shared; self.api = api; self.uploadStore = uploadStore; self.secrets = secrets
        self.clipboard = clipboard ?? .general; self.uploaderFactory = uploaderFactory
    }
    var isBusy: Bool { isRestoring || [.preparing, .uploading, .finishing, .flying].contains(phase) }
    var hasPendingUpload: Bool { !jobs.isEmpty }
    var uploadingItemID: UUID? { jobs.first?.sourceItemID ?? (isBusy ? item?.id : nil) }
    func start() {
        guard !started else { return }; started = true; isRestoring = true
        let restoreGeneration = generation
        auth.onSignOut = { [weak self] in
            guard let self else { return }
            self.cancel(); self.links = []; self.account = nil; self.result = nil
        }
        Task {
            defer { isRestoring = false }
            do {
                let restored = try await uploadStore.read()
                guard generation == restoreGeneration else { return }
                jobs = restored
                // Never send one account's job to a newly configured server.
                let obsolete = jobs.filter { $0.apiBaseURL != config.baseURL }
                jobs.removeAll { $0.apiBaseURL != config.baseURL }
                for job in obsolete { await uploadStore.discard(job.localFile); secrets.remove(passwordKey(job.id, base: job.apiBaseURL)) }
                try await persist()
                uploader.reconcile { [weak self] active in
                    Task { @MainActor in
                        guard let self else { return }
                        if let job = self.jobs.first {
                            if job.uploaded { self.finish(job) }
                            else if active.contains(job.id) { self.phase = .uploading }
                            else { self.phase = .failed; self.notice(String(localized: "Upload paused. Tap Retry."), error: true) }
                        }
                    }
                }
            } catch { notice(String(localized: "Couldn’t restore the upload."), error: true) }
        }
    }
    func show(_ item: ShelfItem) {
        start(); self.item = item; screen = .compose; isPresenting = true
        if !isBusy && jobs.isEmpty { phase = .idle; result = nil; message = nil }
    }
    func showMyLinks() { start(); screen = .myLinks; isPresenting = true; Task { await refreshLinks() } }
    func close() { isPresenting = false }
    func begin(options: LinkOptions) {
        guard !isBusy, let item else { return }
        if !options.password.isEmpty && !(8...128).contains(options.password.count) { notice(LinkError.password.localizedDescription, error: true); return }
        generation = UUID(); let token = generation
        phase = .preparing; fraction = 0; result = nil; message = nil; isError = false
        work = Task {
            var staged: URL?
            do {
                // Explicitly replacing a failed upload cancels its old reservation.
                if !jobs.isEmpty { await cancelJobs() }
                let access = try await auth.token()
                let profile: LinkAccount = try await api.call("/v1/me", base: config.baseURL, token: access)
                account = profile
                if profile.activeLinks >= profile.maxActiveLinks { throw LinkError.quota }
                let file = try await uploadStore.stage(item.url); staged = file
                let size = try await uploadStore.size(file)
                guard size > 0, size <= profile.maxBytes else { throw LinkError.tooLarge }
                try Task.checkCancellation(); guard generation == token else { throw CancellationError() }
                let reply: LinkUploadInit = try await api.call("/v1/uploads/init", base: config.baseURL, method: "POST", token: access,
                    body: LinkAPI.body(["filename": file.lastPathComponent, "size": size, "mime": UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"]))
                guard generation == token, !Task.isCancelled else {
                    Task { let _: LinkOK? = try? await api.call("/v1/uploads/\(reply.fileId.uuidString)", base: config.baseURL, method: "DELETE", token: access) }
                    throw CancellationError()
                }
                guard let base = config.baseURL else { throw LinkError.configuration }
                let job = PendingLinkUpload(id: reply.fileId, owner: profile.userId, apiBaseURL: base, localFile: file, sourceItemID: item.id,
                                            expiry: options.expiry, downloadLimit: options.downloadLimit, hasPassword: !options.password.isEmpty)
                if job.hasPassword { try secrets.save(Data(options.password.utf8), account: passwordKey(job.id)) }
                jobs = [job]; try await persist()
                try Task.checkCancellation(); guard generation == token else { throw CancellationError() }
                try uploader.upload(job, reply: reply)
                staged = nil; phase = .uploading
            } catch {
                if let staged, !jobs.contains(where: { $0.localFile == staged }) { await uploadStore.discard(staged) }
                guard generation == token else { return }
                phase = .failed; notice(LinkError.safe(error), error: true)
            }
        }
    }
    private func update(_ id: UUID, value: Double) {
        guard jobs.contains(where: { $0.id == id }), phase == .uploading else { return }
        fraction = value
    }
    private func uploaded(_ id: UUID, success: Bool) async {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        if !success { phase = .failed; notice(String(localized: "Upload failed. Tap Retry."), error: true); return }
        jobs[index].uploaded = true
        do { try await persist(); finish(jobs[index]) }
        catch { phase = .failed; notice(LinkError.safe(error), error: true) }
    }
    private func finish(_ job: PendingLinkUpload) {
        guard auth.userID == job.owner else { phase = .failed; notice(LinkError.signIn.localizedDescription, error: true); return }
        guard operationID != job.id else { return }
        operationID = job.id; phase = .finishing; fraction = 1
        let token = generation
        work = Task {
            defer { if operationID == job.id { operationID = nil } }
            do {
                let access = try await auth.token()
                var body: [String:Any] = ["fileId": job.id.uuidString, "expiry": job.expiry.rawValue]
                if let limit = job.downloadLimit { body["downloadLimit"] = limit }
                if job.hasPassword {
                    guard let data = try secrets.read(passwordKey(job.id)), let password = String(data: data, encoding: .utf8) else { throw LinkError.keychain }
                    body["password"] = password
                }
                let share: SharedLink = try await api.call("/v1/uploads/complete", base: job.apiBaseURL, method: "POST", token: access, body: LinkAPI.body(body))
                guard generation == token, jobs.contains(where: { $0.id == job.id }) else { return }
                guard share.fileId == job.id, share.isActive(), share.url.scheme == job.apiBaseURL.scheme, share.url.host == job.apiBaseURL.host,
                      share.url.port == job.apiBaseURL.port, share.url.path.hasPrefix("/s/"), share.url.query == nil else { throw LinkError.invalidResponse }
                result = share; links.removeAll { $0.id == share.id }; links.insert(share, at: 0)
                phase = .flying
                try await Task.sleep(for: .seconds(Motion.sendFlightDuration))
                try Task.checkCancellation(); guard generation == token else { return }
                copy(share); phase = .landed; successToken += 1
                jobs.removeAll { $0.id == job.id }; try await persist()
                secrets.remove(passwordKey(job.id, base: job.apiBaseURL)); await uploadStore.discard(job.localFile)
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            } catch {
                guard generation == token else { return }
                phase = .failed; notice(LinkError.safe(error), error: true)
            }
        }
    }
    func retry() {
        guard !isBusy, let job = jobs.first else { return }
        generation = UUID(); operationID = nil
        let retryGeneration = generation
        if job.uploaded { finish(job); return }
        phase = .preparing; message = nil
        work = Task {
            do {
                try Task.checkCancellation()
                guard auth.userID == job.owner, config.baseURL == job.apiBaseURL else { throw LinkError.signIn }
                try await persist()
                let access = try await auth.token()
                let reply: LinkUploadInit = try await api.call("/v1/uploads/\(job.id.uuidString)", base: job.apiBaseURL, token: access)
                try Task.checkCancellation()
                guard generation == retryGeneration, jobs.contains(where: { $0.id == job.id }) else { return }
                try uploader.upload(job, reply: reply); phase = .uploading; fraction = 0
            } catch {
                guard generation == retryGeneration else { return }
                phase = .failed; notice(LinkError.safe(error), error: true)
            }
        }
    }
    func cancel() {
        generation = UUID(); work?.cancel(); work = nil; operationID = nil
        let old = jobs; jobs = []
        let cleanupToken = auth.cleanupToken, owner = auth.userID
        for job in old { uploader.cancel(job.id) }
        phase = .idle; message = String(localized: "Upload cancelled"); isError = false
        Task { await dispose(old, token: cleanupToken, owner: owner) }
    }
    private func cancelJobs() async {
        let old = jobs; jobs = []
        for job in old { uploader.cancel(job.id) }
        await dispose(old)
    }
    private func dispose(_ old: [PendingLinkUpload], token: String? = nil, owner: UUID? = nil) async {
        try? await persist()
        for job in old {
            let access = owner == job.owner ? token : (auth.userID == job.owner ? try? await auth.token() : nil)
            if let access {
                let _: LinkOK? = try? await api.call("/v1/uploads/\(job.id.uuidString)", base: job.apiBaseURL, method: "DELETE", token: access)
            }
            secrets.remove(passwordKey(job.id, base: job.apiBaseURL)); await uploadStore.discard(job.localFile)
        }
    }
    func refreshLinks() async {
        guard auth.isSignedIn, !isRefreshing else { return }
        let owner = auth.userID, base = config.baseURL
        isRefreshing = true; defer { isRefreshing = false }
        do {
            let access = try await auth.token()
            let reply: LinkListReply = try await api.call("/v1/links", base: base, token: access)
            guard auth.userID == owner, config.baseURL == base else { return }
            links = reply.links
        } catch {
            guard auth.userID == owner, config.baseURL == base else { return }
            notice(LinkError.safe(error), error: true)
        }
    }
    func revoke(_ link: SharedLink) async {
        do {
            let access = try await auth.token()
            let _: LinkOK = try await api.call("/v1/links/\(link.id.uuidString)", base: config.baseURL, method: "DELETE", token: access)
            await refreshLinks(); notice(String(localized: "Link revoked"))
        } catch { notice(LinkError.safe(error), error: true) }
    }
    func copy(_ link: SharedLink) {
        clipboard.clearContents()
        clipboard.setString(link.url.absoluteString, forType: .string)
        notice(String(localized: "Link copied"))
    }
    private func persist() async throws { try await uploadStore.save(jobs) }
    private func passwordKey(_ id: UUID, base: URL? = nil) -> String { "upload.\(LinkConfiguration.scope(base ?? config.baseURL)).\(id.uuidString)" }
    private func notice(_ text: String, error: Bool = false) {
        toastTask?.cancel(); message = text; isError = error
        if !error {
            toastTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(Motion.sendToastDuration))
                    try Task.checkCancellation(); self?.message = nil
                } catch { }
            }
        }
    }
    func resumeAfterSignIn() {
        if let job = jobs.first, job.uploaded, job.owner == auth.userID { finish(job) }
    }
}
