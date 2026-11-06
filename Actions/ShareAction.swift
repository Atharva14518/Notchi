import AppKit
import Combine

@MainActor
final class ShareAction: NSObject, ObservableObject, NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    typealias AppLauncher = @MainActor (InstalledSendApp) async throws -> Void
    typealias RecipientPicker = @MainActor (InstalledSendApp, [URL]) async throws -> Void
    @Published private(set) var lifecycle = SendLifecycle()
    @Published private(set) var session: SendSession?
    @Published private(set) var targets: [SendTarget] = []
    @Published private(set) var flight: SendFlight?
    @Published private(set) var toast: SendToast?
    @Published private(set) var waveToken = 0
    @Published private(set) var status = String(localized: "Choose where it goes.")
    @Published private(set) var handoff: SendAppHandoff?
    @Published private(set) var isExternalHandoffActive = false
    weak var sourceView: NSView?
    var originFrames: [UUID: CGRect] = [:]
    var tileFrames: [String: CGRect] = [:]
    private var selectedTarget = "more"
    private var activeService: NSSharingService?
    private var picker: NSSharingServicePicker?
    private var savePanel: NSSavePanel?
    private let exporter = SendFileExporter()
    private var celebrationTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private let catalog: ([URL]) -> [SendTarget]
    private let attachments: SendAttachmentPreparer
    private let clipboard: NSPasteboard
    private let launchApp: AppLauncher
    private let recipientPicker: RecipientPicker
    private let automationPermission: () -> Bool
    private let requestAutomationPermission: () -> Void
    private var preparationID = UUID()
    private var serviceFiles: PreparedSendFiles?

    init(catalog: (([URL]) -> [SendTarget])? = nil,
         attachments: SendAttachmentPreparer = SendAttachmentPreparer(),
         clipboard: NSPasteboard = .general, launchApp: AppLauncher? = nil,
         recipientPicker: RecipientPicker? = nil, automationPermission: (() -> Bool)? = nil,
         requestAutomationPermission: (() -> Void)? = nil) {
        self.catalog = catalog ?? { SendCatalog.targets(for: $0) }
        self.attachments = attachments; self.clipboard = clipboard
        self.recipientPicker = recipientPicker ?? { app, urls in try await WhatsAppAutomation.openRecipients(app: app, files: urls) }
        self.automationPermission = automationPermission ?? { PermissionManager.shared.refresh() }
        self.requestAutomationPermission = requestAutomationPermission ?? { PermissionManager.shared.showHelp() }
        self.launchApp = launchApp ?? { app in
            NSApp.yieldActivation(toApplicationWithBundleIdentifier: app.id)
            let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // Launch only: sending document URLs through Open Document is
                // not a general attachment API (notably for WhatsApp PDFs).
                NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { running, error in
                    Task { @MainActor in
                        if let error { continuation.resume(throwing: error); return }
                        guard let running else { continuation.resume(throwing: WhatsAppAutomationError.unavailable); return }
                        NSApp.yieldActivation(to: running)
                        running.unhide()
                        _ = running.activate(from: .current, options: .activateAllWindows)
                        for _ in 0..<40 {
                            if running.isActive { continuation.resume(); return }
                            try? await Task.sleep(for: .milliseconds(50))
                        }
                        continuation.resume(throwing: WhatsAppAutomationError.focusChanged)
                    }
                }
            }
        }
        super.init()
    }

    var isPresenting: Bool { lifecycle.keepsPanelOpen }
    var isBusy: Bool { lifecycle.isBusy }
    var isFlying: Bool { flight != nil }

    func show(items: [ShelfItem]) {
        guard !items.isEmpty, !isBusy else { return }
        celebrationTask?.cancel()
        toastTask?.cancel()
        session = SendSession(items: items)
        targets = catalog(items.map(\.url))
        originFrames = [:]
        tileFrames = [:]
        toast = nil
        handoff = nil; serviceFiles = nil
        status = String(localized: "Choose where it goes.")
        lifecycle.begin()
    }
    func close() {
        guard lifecycle.dismiss() else { return }
        celebrationTask?.cancel()
        flight = nil
        session = nil
        handoff = nil; serviceFiles = nil
        targets = []
        activeService?.delegate = nil
        activeService = nil
        picker = nil
        originFrames = [:]
        tileFrames = [:]
    }
    func choose(_ target: SendTarget) {
        guard !isBusy, let session else { return }
        guard session.items.allSatisfy({ FileManager.default.fileExists(atPath: $0.url.path) }) else {
            notify(String(localized: "A file moved or went offline. Add it to the shelf again."), error: true)
            return
        }
        selectedTarget = target.id
        switch target.kind {
        case .service(let service):
            share(service)
        case .copy:
            exportTask = Task { [weak self] in
                guard let self, self.session?.id == session.id else { return }
                _ = await self.copyFiles()
            }
        case .save: saveFiles()
        case .more: showMore()
        case .openApp(let app): prepareHandoff(app)
        }
    }
    func prepareService(_ service: NSSharingService) {
        guard session != nil, lifecycle.phase != .idle, lifecycle.phase != .celebrating else { return }
        activeService = service
        service.delegate = self
        lifecycle.choseService(true)
        status = String(localized: "Finish or cancel in \(service.title).")
    }
    @discardableResult
    func copyFiles(to pasteboard: NSPasteboard? = nil) async -> Bool {
        guard let session, !isBusy else { return false }
        lifecycle.export(); status = String(localized: "Preparing file copies…")
        let token = UUID(); preparationID = token
        do {
            let files = try await attachments.prepare(session.items.map(\.url), zipFolders: true)
            try Task.checkCancellation()
            guard self.session?.id == session.id, preparationID == token else { return false }
            let board = pasteboard ?? clipboard
            guard write(files, to: board) else { throw ActionError.failed(String(localized: "Couldn’t copy those files. Please try again.")) }
            confirmed("Copied!")
            return true
        } catch {
            guard self.session?.id == session.id, preparationID == token else { return false }
            lifecycle.returned(); notify(error.localizedDescription, error: true)
            return false
        }
    }

    private func write(_ files: PreparedSendFiles, to board: NSPasteboard) -> Bool {
        board.clearContents()
        return board.writeObjects(files.urls.map { $0 as NSURL })
    }

    private func share(_ service: NSSharingService) {
        guard let session else { return }
        lifecycle.export(); status = String(localized: "Preparing attachments…")
        let token = UUID(); preparationID = token
        exportTask = Task { [weak self] in
            guard let self else { return }
            do {
                let files = try await attachments.prepare(session.items.map(\.url))
                try Task.checkCancellation()
                guard self.session?.id == session.id, preparationID == token else { return }
                guard service.canPerform(withItems: files.urls.map { $0 as NSURL }) else {
                    throw ActionError.failed(String(localized: "This service doesn’t accept these files. Use Copy or Save to… and attach them as documents in the destination app."))
                }
                serviceFiles = files
                lifecycle.returned(); prepareService(service)
                service.perform(withItems: files.urls.map { $0 as NSURL })
            } catch {
                guard self.session?.id == session.id, preparationID == token else { return }
                lifecycle.returned(); notify(error.localizedDescription, error: true)
            }
        }
    }

    private func saveFiles() {
        guard let session else { return }
        lifecycle.save()
        status = String(localized: "Choose where to save a copy.")
        let panel = NSSavePanel()
        savePanel = panel
        panel.title = String(localized: "Save a copy")
        panel.prompt = String(localized: "Save copy")
        panel.canCreateDirectories = true
        panel.directoryURL = SettingsStore.shared.saveLocation
        panel.nameFieldStringValue = session.items.count == 1 ? session.items[0].name : String(localized: "\(AppConfig.appName) Files")
        panel.message = session.items.count == 1 ? String(localized: "Your original stays in place.") : String(localized: "Creates a folder containing \(session.items.count) files. Originals stay in place.")
        NSApp.activate(ignoringOtherApps: true)
        let complete: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
            guard let self, self.session?.id == session.id else { return }
            let destination = panel?.url
            self.savePanel = nil
            guard response == .OK, let destination else {
                self.lifecycle.returned(); self.status = String(localized: "Choose where it goes."); return
            }
            self.lifecycle.export()
            self.status = String(localized: "Saving a copy…")
            self.exportTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let scoped = destination.startAccessingSecurityScopedResource()
                    defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
                    try await self.exporter.export(session.items.map(\.url), to: destination)
                    guard self.session?.id == session.id else { return }
                    self.confirmed("Saved!")
                } catch {
                    guard self.session?.id == session.id else { return }
                    self.lifecycle.returned()
                    self.notify(error.localizedDescription, error: true)
                }
            }
        }
        if let window = sourceView?.window { panel.beginSheetModal(for: window, completionHandler: complete) }
        else { panel.begin(completionHandler: complete) }
    }

    private func showMore() {
        guard let session, let view = sourceView else { return }
        lifecycle.pickMore()
        status = String(localized: "Choose a sharing service.")
        let picker = NSSharingServicePicker(items: session.items.map { $0.url as NSURL })
        self.picker = picker
        picker.delegate = self
        picker.show(relativeTo: anchorInView(for: "more"), of: view, preferredEdge: .minY)
    }
    func prepareHandoff(_ app: InstalledSendApp, archiveAll: Bool = false) {
        guard !isBusy, let session else { return }
        lifecycle.export(); status = archiveAll ? String(localized: "Making a ZIP attachment…") : String(localized: "Preparing document attachments…")
        let token = UUID(); preparationID = token
        exportTask = Task { [weak self] in
            guard let self else { return }
            do {
                let files = try await attachments.prepare(session.items.map(\.url), zipFolders: true,
                    archiveAll: archiveAll, maximumBytes: app.maximumDocumentBytes)
                try Task.checkCancellation()
                guard self.session?.id == session.id, preparationID == token else { return }
                guard write(files, to: clipboard) else { throw ActionError.failed(String(localized: "Couldn’t copy the attachments. Try Save to… instead.")) }
                handoff = SendAppHandoff(app: app, files: files)
                try await openPreparedHandoff(app, files: files)
                guard self.session?.id == session.id, preparationID == token else { return }
                lifecycle.returned()
                status = app.isWhatsApp ? String(localized: "Choose recipients and press Send in WhatsApp.") : String(localized: "Files copied. Choose a chat, then Attach → Document.")
                isExternalHandoffActive = false
                // Launch and clipboard success do not confirm attachment or
                // delivery. Never show Sent! for this fallback.
            } catch {
                guard self.session?.id == session.id, preparationID == token else { return }
                lifecycle.returned(); notify(error.localizedDescription, error: true)
                status = handoff == nil ? String(localized: "Choose another way to attach these files.") : String(localized: "Files are ready. Open the app yourself, or show the files to attach them.")
                isExternalHandoffActive = false
            }
        }
    }

    func copyAndOpenHandoff() {
        guard !isBusy, let handoff else { return }
        guard handoff.files.urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }),
              write(handoff.files, to: clipboard) else {
            prepareHandoff(handoff.app); return
        }
        guard let session else { return }
        lifecycle.openApp(); status = String(localized: "Opening \(handoff.app.title)…")
        let token = UUID(); preparationID = token
        exportTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await openPreparedHandoff(handoff.app, files: handoff.files)
                try Task.checkCancellation()
                guard self.session?.id == session.id, preparationID == token else { return }
                lifecycle.returned()
                status = handoff.app.isWhatsApp ? String(localized: "Choose recipients and press Send in WhatsApp.") : String(localized: "Files copied. Choose a chat, then Attach → Document.")
            } catch {
                guard self.session?.id == session.id, preparationID == token else { return }
                lifecycle.returned(); notify(error.localizedDescription, error: true)
            }
            isExternalHandoffActive = false
        }
    }
    private func openPreparedHandoff(_ app: InstalledSendApp, files: PreparedSendFiles) async throws {
        if app.isWhatsApp, !automationPermission() {
            requestAutomationPermission()
            throw WhatsAppAutomationError.permission
        }
        lifecycle.openApp(); status = String(localized: "Opening \(app.title)…")
        isExternalHandoffActive = true
        try await launchApp(app)
        try Task.checkCancellation()
        if app.isWhatsApp {
            status = String(localized: "Preparing WhatsApp’s recipient picker…")
            try await recipientPicker(app, files.urls)
        }
    }
    func cancelExternalHandoff() {
        guard isExternalHandoffActive else { return }
        preparationID = UUID(); exportTask?.cancel(); exportTask = nil
        lifecycle.returned(); status = String(localized: "Stopped. You can cancel any open draft in WhatsApp.")
        isExternalHandoffActive = false
    }
    func showHandoffFiles() {
        if let handoff { NSWorkspace.shared.activateFileViewerSelecting(handoff.files.urls) }
    }
    func copyHandoffLocation() {
        guard let handoff else { return }
        let path = handoff.files.urls.count == 1 ? handoff.files.urls[0].path : handoff.files.folder.path
        clipboard.clearContents(); clipboard.setString(path, forType: .string)
        status = String(localized: "Copied")
        notify(String(localized: "Copied"))
    }
    func leaveHandoff() {
        guard !isBusy else { return }
        handoff = nil; toast = nil; status = String(localized: "Choose where it goes.")
    }

    private func confirmed(_ message: String) {
        guard let session else { return }
        lifecycle.confirmed()
        status = message
        waveToken += 1
        let fallback = CGRect(x: 28, y: 80, width: 142, height: 48)
        let destination = tileFrames[selectedTarget] ?? CGRect(x: 160, y: 210, width: 100, height: 86)
        flight = SendFlight(items: Array(session.items.prefix(5)),
            origins: Dictionary(uniqueKeysWithValues: session.items.map { ($0.id, originFrames[$0.id] ?? fallback) }), target: destination)
        notify(message)
        celebrationTask?.cancel()
        celebrationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(Motion.sendFlightDuration))
                guard let self, self.session?.id == session.id else { return }
                self.flight = nil
                self.lifecycle.returned()
                self.activeService?.delegate = nil
                self.activeService = nil
            } catch { }
        }
    }
    private func notify(_ text: String, error: Bool = false) {
        toastTask?.cancel()
        toast = SendToast(text: text, isError: error)
        toastTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(Motion.sendToastDuration))
                self?.toast = nil
            } catch { }
        }
    }
    private func anchorInView(for id: String) -> CGRect {
        guard let view = sourceView else { return .zero }
        let rect = tileFrames[id] ?? CGRect(x: 160, y: 160, width: 100, height: 86)
        if view.isFlipped { return rect }
        return CGRect(x: rect.minX, y: view.bounds.height - rect.maxY, width: rect.width, height: rect.height)
    }

    // Picker selection hands off to a service: it must NOT release the panel lock.
    nonisolated func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        Task { @MainActor [weak self] in
            guard let self, self.session != nil, self.picker === sharingServicePicker else { return }
            if let service {
                self.prepareService(service)
            } else {
                self.lifecycle.returned()
                self.status = String(localized: "Choose where it goes.")
                self.picker = nil
            }
        }
    }
    nonisolated func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                              delegateFor sharingService: NSSharingService) -> NSSharingServiceDelegate? {
        // Legacy picker delegates lack UI-actor annotations. AppKit invokes
        // this synchronous UI callback on the main thread.
        let delegate: ShareAction? = MainActor.assumeIsolated {
            guard self.picker === sharingServicePicker else { return nil }
            self.prepareService(sharingService)
            return self
        }
        return delegate
    }
    func sharingService(_ sharingService: NSSharingService, willShareItems items: [Any]) {
        guard activeService === sharingService, lifecycle.phase == .service else { return }
        lifecycle.choseService(true)
        status = String(localized: "Finish or cancel in \(sharingService.title).")
    }
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        guard activeService === sharingService, lifecycle.phase == .service else { return }
        // Only this delegate callback is treated as a confirmed successful share.
        confirmed("Sent!")
    }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        guard activeService === sharingService, lifecycle.phase == .service else { return }
        activeService = nil
        lifecycle.returned()
        status = String(localized: "Choose where it goes.")
        let nsError = error as NSError
        if nsError.code != NSUserCancelledError && nsError.code != NSURLErrorCancelled {
            notify(String(localized: "Couldn’t send that. Try Copy or Save to… and attach it as a document. \(error.localizedDescription)"), error: true)
        }
    }
    func sharingService(_ sharingService: NSSharingService, sourceWindowForShareItems items: [Any],
                        sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
        sharingContentScope.pointee = .item
        return sourceView?.window
    }
    func sharingService(_ sharingService: NSSharingService, sourceFrameOnScreenForShareItem item: Any) -> NSRect {
        guard let view = sourceView, let window = view.window else { return .zero }
        return window.convertToScreen(view.convert(anchorInView(for: selectedTarget), to: nil))
    }
    func sharingService(_ sharingService: NSSharingService, transitionImageForShareItem item: Any,
                        contentRect: UnsafeMutablePointer<NSRect>) -> NSImage? {
        nil // Our file-card flight runs after confirmation, not before delivery.
    }
    func stop() {
        preparationID = UUID()
        celebrationTask?.cancel(); toastTask?.cancel(); exportTask?.cancel()
        activeService?.delegate = nil
        picker?.delegate = nil
        savePanel?.cancel(nil)
        lifecycle.stop()
        session = nil
        flight = nil
        toast = nil
        picker = nil
        savePanel = nil
        targets = []
        handoff = nil; serviceFiles = nil
        isExternalHandoffActive = false
        sourceView = nil
    }
}
