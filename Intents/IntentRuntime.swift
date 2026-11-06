import AppIntents
import AppKit

/// App Intents and AppDelegate share this single store/coordinator. No window,
/// panel, permission prompt or NSApp activation is needed to initialize it.
@MainActor
final class IntentRuntime {
    static let shared = IntentRuntime(store: ShelfStore(settings: .shared), actions: ActionCoordinator(settings: .shared))
    @TaskLocal static var testing: IntentRuntime?
    static var current: IntentRuntime { testing ?? shared }
    let store: ShelfStore
    let actions: ActionCoordinator
    private let stager: IntentFileStager
    var openShelfHandler: (() -> Void)? { didSet { deliverNavigation() } }
    var openScanHandler: (() -> Void)? { didSet { deliverNavigation() } }
    var canChangeShelf: () -> Bool = { true }
    private var navigation: Navigation?
    private enum Navigation { case shelf, scan }
    init(store: ShelfStore, actions: ActionCoordinator, stager: IntentFileStager = .shared) {
        self.store = store; self.actions = actions; self.stager = stager
    }
    func entities(identifiers: [UUID]? = nil, matching query: String? = nil) -> [ShelfItemEntity] {
        let available = store.files.filter { FileManager.default.isReadableFile(atPath: $0.url.path) }
        if let identifiers {
            let byID = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
            return identifiers.compactMap { byID[$0].map(ShelfItemEntity.init) }
        }
        return available.filter { query == nil || $0.name.localizedStandardContains(query!) }
            .sorted { $0.addedAt > $1.addedAt }.map(ShelfItemEntity.init)
    }
    func openShelf() { navigation = .shelf; deliverNavigation() }
    func openScan() { navigation = .scan; deliverNavigation() }
    private func deliverNavigation() {
        switch navigation {
        case .shelf where openShelfHandler != nil: navigation = nil; openShelfHandler?()
        case .scan where openScanHandler != nil: navigation = nil; openScanHandler?()
        default: break // Cold-start intent may arrive before AppDelegate finishes.
        }
    }
    func add(_ inputs: [IntentFile]) async throws -> [ShelfItemEntity] {
        guard !inputs.isEmpty else { throw ActionError.failed(String(localized: "Choose at least one file.")) }
        guard canChangeShelf() else { throw busyError }
        var staged: [URL] = []
        do {
            for input in inputs { staged.append(try await stager.stage(input)) }
            try Task.checkCancellation()
            guard canChangeShelf() else { throw busyError }
            store.add(staged, expand: false)
            return store.files.filter { staged.contains($0.url) }.map(ShelfItemEntity.init)
        } catch {
            for url in staged { await stager.discard(url) }
            throw error
        }
    }
    func clear() throws {
        guard !actions.isBusy, !store.isImporting, canChangeShelf() else { throw busyError }
        store.clear() // References only. Never delete the user's source files.
    }
    private var busyError: ActionError { .failed(String(localized: "Finish the current operation, then try again.")) }
    func perform(file: IntentFile?, shelfFile: ShelfItemEntity?,
                 operation: (ShelfItem) throws -> NativeFileAction,
                 progress: (@MainActor (ActionProgress) -> Void)? = nil) async throws -> ActionResult {
        guard !actions.isBusy else { throw busyError }
        guard file == nil || shelfFile == nil else {
            throw ActionError.failed(String(localized: "Choose an input file or a shelf file, not both."))
        }
        var stagedURL: URL?
        let item: ShelfItem
        if let file {
            let url = try await stager.stage(file); stagedURL = url
            item = ShelfItem(url: url)
        } else if let shelfFile {
            guard let found = store.files.first(where: { $0.id == shelfFile.id }),
                  FileManager.default.isReadableFile(atPath: found.url.path) else {
                throw ActionError.failed(String(localized: "That shelf file is unavailable. Add it again or choose another file."))
            }
            item = found
        } else {
            guard let latest = store.files.filter({ FileManager.default.isReadableFile(atPath: $0.url.path) })
                .max(by: { $0.addedAt < $1.addedAt }) else {
                throw ActionError.failed(String(localized: "Your shelf is empty. Choose an input file or add one first."))
            }
            item = latest
        }
        do {
            try Task.checkCancellation()
            guard !actions.isBusy else { throw busyError }
            let action = try operation(item)
            if store.isExpanded, !store.files.contains(where: { $0.id == item.id }) {
                store.add([item.url], expand: false)
            }
            // Use the card's actual ID if an incoming file was added for visible progress.
            let visibleItem = store.files.first { $0.url == item.url } ?? item
            let result = try await actions.execute(action, item: visibleItem, store: store, progress: progress)
            if let stagedURL, !store.files.contains(where: { $0.url == stagedURL }) { await stager.discard(stagedURL) }
            return result
        } catch {
            if let stagedURL, !store.files.contains(where: { $0.url == stagedURL }) { await stager.discard(stagedURL) }
            throw error
        }
    }
    func text(from result: ActionResult) async throws -> String {
        guard let url = result.outputs.first else { throw ScanError.noText }
        return try await stager.text(from: url)
    }
    nonisolated static func compression(for item: ShelfItem, preset: ShortcutCompressionPreset) -> NativeFileAction {
        switch item.kind {
        case .image: return NativeFileAction(operation: .compressImage(preset.quality))
        case .pdf: return NativeFileAction(operation: .compressPDF(preset.quality))
        case .video:
            return NativeFileAction(operation: .media(.preset(preset == .tiny ? .smallest : (preset == .best ? .highQuality : .email))))
        case .audio: return NativeFileAction(operation: .media(.compressAudio))
        default: return NativeFileAction(operation: .zip)
        }
    }
    nonisolated static func conversion(for item: ShelfItem, format: ShortcutTargetFormat) throws -> NativeFileAction {
        let action: NativeFileAction
        if item.isImage, let imageFormat = format.imageFormat {
            action = NativeFileAction(operation: .convert(imageFormat))
        } else if let mediaFormat = format.mediaFormat, item.kind == .video || item.kind == .audio {
            action = NativeFileAction(operation: item.kind == .video && mediaFormat.isAudio ? .media(.extract(mediaFormat)) : .media(.convert(mediaFormat)))
        } else { throw ActionError.failed(String(localized: "That format doesn’t match this file.")) }
        guard action.isSupported(for: item) else { throw ActionError.failed(String(localized: "This Mac can’t convert that format.")) }
        return action
    }
}
