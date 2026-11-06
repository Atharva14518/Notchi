import AppKit
import Combine

enum ActionError: LocalizedError {
    case failed(String)
    var errorDescription: String? { switch self { case .failed(let message): return message } }
}
struct ActionOptionsRequest: Identifiable {
    let id = UUID()
    let action: NativeFileAction
    let item: ShelfItem
}
struct MediaOptionsRequest: Identifiable {
    let id = UUID()
    let item: ShelfItem
}
struct ActionJob {
    enum Phase { case running, success, failure, cancelled }
    let itemID: UUID
    var phase: Phase = .running
    var fraction: Double?
    var estimatedRemaining: TimeInterval?
    var message: String = String(localized: "getting ready…")
    var result: ActionResult?
    var error: String?
}

@MainActor
final class ActionCoordinator: ObservableObject {
    @Published private(set) var isBusy = false
    @Published private(set) var job: ActionJob?
    @Published var options: ActionOptionsRequest?
    @Published var mediaOptions: MediaOptionsRequest?
    @Published var errorMessage: String?
    @Published private(set) var lowerResolutionAction: NativeFileAction?
    @Published private(set) var successToken = 0
    @Published private(set) var errorToken = 0
    var scanHandler: ((ShelfItem, ScanMode) -> Void)?
    private let settings: SettingsStore?
    init(settings: SettingsStore? = nil) { self.settings = settings }
    private var lastAction: NativeFileAction?
    private var lastItem: ShelfItem?
    private var workTask: Task<Void, Never>?
    private var consumerTask: Task<Void, Never>?
    private var engineTask: Task<ActionResult, Error>?
    private var generation = UUID()
    private weak var boundStore: ShelfStore?
    private var shelfSubscription: AnyCancellable?
    private func observeShelf(_ store: ShelfStore) {
        guard boundStore !== store else { return }
        boundStore = store
        shelfSubscription = store.$files.sink { [weak self] files in
            guard let self, !self.isBusy, let job = self.job, job.phase != .running else { return }
            let resultURLs = Set(job.result?.outputs ?? [])
            guard !files.contains(where: { $0.id == job.itemID || resultURLs.contains($0.url) }) else { return }
            self.job = nil; self.lowerResolutionAction = nil; self.errorMessage = nil
            self.lastAction = nil; self.lastItem = nil
        }
    }

    var isComplete: Bool { job?.phase == .success }
    var progress: Double { job?.fraction ?? 0.18 }
    var isIndeterminate: Bool { isBusy && job?.fraction == nil }
    var isMediaWorking: Bool { isBusy && lastAction?.isMedia == true }
    var status: String { job?.message ?? "" }
    var isPresentingDialog: Bool { options != nil || mediaOptions != nil }
    var outputURL: URL? { job?.result?.outputs.first }
    func job(for id: UUID) -> ActionJob? { job?.itemID == id ? job : nil }

    func request(_ action: NativeFileAction, item: ShelfItem, store: ShelfStore) {
        guard !isBusy else { return }
        switch action.operation {
        case .recognizeText: scanHandler?(item, .text)
        case .detectBarcodes: scanHandler?(item, .barcodes)
        case .convert, .compressImage, .compressPDF, .resize: options = ActionOptionsRequest(action: action, item: item)
        case .media(.trim(nil)): mediaOptions = MediaOptionsRequest(item: item)
        default: run(action, item: item, store: store)
        }
    }
    func confirmTrim(_ range: MediaRange, item: ShelfItem, store: ShelfStore) {
        mediaOptions = nil
        run(NativeFileAction(operation: .media(.trim(range))), item: item, store: store)
    }
    func confirm(format: ImageFormat, quality: QualityPreset, resize: ResizeSpec, store: ShelfStore) {
        guard let request = options else { return }
        var operation = request.action.operation
        switch operation {
        case .convert: operation = .convert(format)
        case .compressImage: operation = .compressImage(quality)
        case .compressPDF: operation = .compressPDF(quality)
        case .resize: operation = .resize(resize)
        default: break
        }
        options = nil
        run(NativeFileAction(operation: operation), item: request.item, store: store)
    }
    func retry(store: ShelfStore) {
        guard let lastAction, let lastItem else { return }
        run(lastAction, item: lastItem, store: store)
    }
    func tryLowerResolution(store: ShelfStore) {
        guard let lowerResolutionAction, let lastItem else { return }
        run(lowerResolutionAction, item: lastItem, store: store)
    }
    func cancel() {
        guard isMediaWorking else { return }
        // Invalidate callbacks before cancelling. An old process can finish
        // teardown after the next action starts without touching its UI state.
        generation = UUID()
        workTask?.cancel(); engineTask?.cancel(); consumerTask?.cancel()
        workTask = nil; engineTask = nil; consumerTask = nil
        isBusy = false
        job?.phase = .cancelled; job?.fraction = nil; job?.estimatedRemaining = nil
        job?.message = String(localized: "cancelled · originals kept.")
    }
    func run(_ action: NativeFileAction, item: ShelfItem, store: ShelfStore) {
        guard !isBusy else { return }
        // Reserve and publish synchronously so a same-event cancel/tap cannot
        // miss the job before the asynchronous engine starts.
        let token = begin(action, item: item, store: store, expandPanel: true)
        workTask = Task { [weak self] in
            guard let self else { return }
            _ = try? await executeStarted(action, item: item, store: store, token: token, expandPanel: true)
        }
    }
    private func begin(_ action: NativeFileAction, item: ShelfItem, store: ShelfStore, expandPanel: Bool) -> UUID {
        observeShelf(store)
        generation = UUID()
        isBusy = true; errorMessage = nil; lowerResolutionAction = nil
        lastAction = action; lastItem = item
        job = ActionJob(itemID: item.id)
        if expandPanel { store.isExpanded = true }
        return generation
    }

    /// One execution path for card taps and App Intents. Background callers await
    /// the actual result; they never need a window, options sheet or main-thread worker.
    @discardableResult
    func execute(_ action: NativeFileAction, item: ShelfItem, store: ShelfStore,
                 expandPanel: Bool = false, progress: (@MainActor (ActionProgress) -> Void)? = nil) async throws -> ActionResult {
        try Task.checkCancellation()
        guard !isBusy else { throw ActionError.failed(String(localized: "Another action is running. Try again shortly.")) }
        let token = begin(action, item: item, store: store, expandPanel: expandPanel)
        return try await executeStarted(action, item: item, store: store, token: token, expandPanel: expandPanel, progress: progress)
    }
    private func executeStarted(_ action: NativeFileAction, item: ShelfItem, store: ShelfStore, token: UUID,
                                expandPanel: Bool, progress: (@MainActor (ActionProgress) -> Void)? = nil) async throws -> ActionResult {
        guard generation == token else { throw CancellationError() }
        if Task.isCancelled {
            isBusy = false; job?.phase = .cancelled
            job?.message = String(localized: "cancelled · originals kept.")
            throw CancellationError()
        }
        let wasVisible = store.isExpanded
        let (stream, reporter) = AsyncStream<ActionProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let consumer = Task { [weak self] in
            for await update in stream {
                guard !Task.isCancelled, let self, generation == token else { return }
                job?.fraction = update.fraction.map { min(action.isMedia ? 0.995 : 0.97, max(0, $0)) }
                job?.estimatedRemaining = update.estimatedRemaining
                job?.message = update.message
                progress?(update)
            }
        }
        consumerTask = consumer
        let policy = settings?.value.originals ?? .keep
        let start = ProcessInfo.processInfo.systemUptime
        let engine = Task { try await action.run(item: item, progress: reporter) }
        engineTask = engine
        defer {
            reporter.finish()
            if generation == token { isBusy = false; engineTask = nil; consumerTask = nil }
        }
        do {
            let result = try await withTaskCancellationHandler(operation: { try await engine.value }, onCancel: { engine.cancel() })
            reporter.finish(); await consumer.value
            do {
                try Task.checkCancellation()
                guard generation == token else { throw CancellationError() }
                let remaining = wasVisible ? Motion.minimumJobDuration - (ProcessInfo.processInfo.systemUptime - start) : 0
                if remaining > 0 { try await Task.sleep(for: .seconds(remaining)) }
            } catch {
                if action.isMedia { await MediaActionWorker.shared.discard(result.outputs) }
                throw error
            }
            if !result.outputs.isEmpty { store.addActionResult(result, source: item, policy: policy, expand: expandPanel) }
            job?.phase = .success; job?.fraction = 1; job?.estimatedRemaining = 0
            job?.message = result.message; job?.result = result
            successToken += 1
            if wasVisible { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
            if settings?.value.suggestRecentActions == true {
                Task { await ShortcutDonations.record(action) }
            }
            return result
        } catch {
            reporter.finish(); await consumer.value
            if generation == token {
                if error is CancellationError {
                    job?.phase = .cancelled; job?.message = String(localized: "cancelled · originals kept.")
                } else {
                    job?.phase = .failure; job?.error = error.localizedDescription
                    job?.message = String(localized: "that one didn’t work."); errorMessage = error.localizedDescription
                    if case MediaError.targetTooSmall(let preset, let lower) = error, !lower {
                        lowerResolutionAction = NativeFileAction(operation: .media(.preset(preset, lowerResolution: true)))
                    }
                    errorToken += 1
                }
            }
            throw error
        }
    }
}
