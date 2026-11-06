import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ScanCoordinator: ObservableObject {
    typealias Exporter = @Sendable ([ScanPage], Bool, URL, ActionProgress.Reporter) async throws -> URL
    enum Stage { case sources, shelfPicker, pages, recognition }
    @Published private(set) var isPresenting = false
    @Published private(set) var isBusy = false
    @Published private(set) var isCapturing = false
    @Published private(set) var stage: Stage = .sources
    @Published private(set) var pages: [ScanPage] = []
    @Published var selectedPageID: UUID?
    @Published var selectedShelfIDs: Set<UUID> = []
    var pageFrames: [UUID: CGRect] = [:]
    @Published var draggingPageID: UUID?
    @Published private(set) var look: ScanLook = .color
    @Published var searchable = true
    @Published private(set) var report: RecognitionReport?
    @Published var reportPage = 0
    @Published private(set) var mode: ScanMode = .text
    @Published private(set) var status = String(localized: "A little less paper.")
    @Published private(set) var error: String?
    @Published private(set) var progress: Double?
    @Published private(set) var animationToken = 0
    @Published private(set) var successToken = 0
    private var work: Task<Void, Never>?
    private var generation = UUID()
    private var folder = ScanCoordinator.draftFolder()
    private let exporter: Exporter
    init(exporter: @escaping Exporter = { pages, searchable, folder, progress in
        try await ScanVisionWorker.shared.export(pages, searchable: searchable, into: folder, progress: progress)
    }) { self.exporter = exporter }
    private static func draftFolder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("Notchi/ScanDrafts/\(UUID().uuidString)") }
    var selectedPage: ScanPage? { pages.first { $0.id == selectedPageID } ?? pages.first }
    var reading: Bool { isBusy && stage == .recognition }

    func open() {
        guard !isBusy else { return }
        isPresenting = true; stage = pages.isEmpty ? .sources : .pages
        error = nil; status = String(localized: "A little less paper.")
    }
    func sources() { guard !isBusy else { return }; stage = .sources; error = nil }
    func showPages() { stage = .pages }
    func pickShelf(_ store: ShelfStore) {
        stage = .shelfPicker
        selectedShelfIDs = Set(store.selectedItems.filter(\.isImage).map(\.id))
    }
    func close() {
        cancel(); isPresenting = false // Closing preserves the current draft until export or app quit.
    }
    func cancel() {
        generation = UUID(); work?.cancel(); work = nil
        draggingPageID = nil
        isBusy = false; isCapturing = false; progress = nil; status = String(localized: "Stopped. Your existing pages are safe.")
    }
    func nativePageDrag(at point: CGPoint, finished: Bool) -> Bool {
        guard !isBusy, let source = draggingPageID,
              let target = pageFrames.first(where: { $0.value.insetBy(dx: -4, dy: -4).contains(point) })?.key else { return false }
        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? Animations.fade : Animations.snappy) { reorder(source: source, target: target) }
        if finished { draggingPageID = nil }
        return true
    }
    func reorder(source: UUID, target: UUID) { guard !isBusy else { return }; pages = ScanCoordinates.reordered(pages, source: source, target: target) }
    func remove(_ page: ScanPage) {
        guard !isBusy else { return }
        pages.removeAll { $0.id == page.id }
        if selectedPageID == page.id { selectedPageID = pages.first?.id }
        if pages.isEmpty { stage = .sources }
    }
    func chooseFiles() {
        guard !isBusy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image, .pdf]
        panel.allowsMultipleSelection = true; panel.prompt = String(localized: "Add pages")
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { importInputs(panel.urls.map(ScanInput.file)) }
    }
    func importInputs(_ inputs: [ScanInput]) {
        guard !inputs.isEmpty, !isBusy else { return }
        isPresenting = true; stage = .pages
        let token = begin(String(localized: "finding page edges…"))
        let batch = folder.appendingPathComponent(UUID().uuidString)
        let currentLook = look
        let scoped = inputs.compactMap { input -> URL? in
            if case .file(let url) = input, url.startAccessingSecurityScopedResource() { return url }; return nil
        }
        work = Task { [weak self] in
            defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
            do {
                let additions = try await ScanVisionWorker.shared.importPages(inputs, into: batch, look: currentLook)
                try Task.checkCancellation()
                guard let self, generation == token else { await ScanVisionWorker.shared.removeFolder(batch); return }
                guard pages.count + additions.count <= ScanVisionWorker.maximumPages else { throw ScanError.tooManyPages }
                pages += additions; selectedPageID = additions.first?.id
                animationToken += 1; status = String(localized: "Drag pages to put them in order.")
                finish(token)
            } catch {
                await ScanVisionWorker.shared.removeFolder(batch)
                self?.fail(error, token: token)
            }
        }
    }
    func changeLook(_ newLook: ScanLook) {
        guard !isBusy, newLook != look else { return }
        guard !pages.isEmpty else { look = newLook; return }
        let token = begin(String(localized: "giving those pages a fresh look…")), oldPages = pages
        work = Task { [weak self] in
            do {
                var updated: [ScanPage] = []
                for page in oldPages { updated.append(try await ScanVisionWorker.shared.restyle(page, look: newLook)); try Task.checkCancellation() }
                guard let self, generation == token else { return }
                pages = updated; look = newLook; animationToken += 1; finish(token)
            } catch { self?.fail(error, token: token) }
        }
    }
    func recognize(_ item: ShelfItem, mode: ScanMode) {
        guard !isBusy else { return }
        isPresenting = true; stage = .recognition; self.mode = mode
        report = nil; reportPage = 0
        let token = begin(mode == .text ? String(localized: "reading the tiny print…") : String(localized: "looking for codes…"))
        let scoped = item.url.startAccessingSecurityScopedResource()
        let (stream, reporter) = AsyncStream<ActionProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
        work = Task { [weak self] in
            defer { if scoped { item.url.stopAccessingSecurityScopedResource() }; reporter.finish() }
            let consumer = Task { @MainActor [weak self] in
                for await update in stream {
                    guard let self, generation == token else { return }
                    progress = update.fraction; status = update.message
                }
            }
            do {
                let result = try await ScanVisionWorker.shared.recognize(.file(item.url), mode: mode, progress: reporter)
                reporter.finish(); await consumer.value; try Task.checkCancellation()
                guard let self, generation == token else { return }
                report = result
                let hasText = result.pages.contains { !$0.lines.isEmpty }
                let hasCodes = result.pages.contains { !$0.barcodes.isEmpty }
                if mode == .text && !hasText { error = ScanError.noText.localizedDescription }
                if mode == .barcodes && !hasCodes { error = ScanError.noBarcode.localizedDescription }
                status = mode == .text ? String(localized: "Text stays on this Mac.") : String(localized: "Links open only when you choose Open link.")
                finish(token)
            } catch { reporter.finish(); consumer.cancel(); self?.fail(error, token: token) }
        }
    }
    func export(to store: ShelfStore) {
        guard !pages.isEmpty, !isBusy else { return }
        let token = begin(searchable ? String(localized: "reading pages for searchable text…") : String(localized: "building PDF…"))
        let currentPages = pages, includeText = searchable, draft = folder
        let results = FileManager.default.temporaryDirectory.appendingPathComponent("Notchi/Results/\(UUID().uuidString)")
        let exportPages = exporter
        let (stream, reporter) = AsyncStream<ActionProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
        work = Task { [weak self, weak store] in
            let consumer = Task { @MainActor [weak self] in
                for await update in stream {
                    guard let self, generation == token else { return }
                    progress = update.fraction; status = update.message
                }
            }
            do {
                let url = try await exportPages(currentPages, includeText, results, reporter)
                reporter.finish(); await consumer.value
                try Task.checkCancellation()
                guard let self, generation == token else { await ScanVisionWorker.shared.removeFolder(results); return }
                store?.add([url], isNew: true)
                successToken += 1; pages = []; selectedPageID = nil; report = nil
                folder = Self.draftFolder(); finish(token); isPresenting = false
                await ScanVisionWorker.shared.removeFolder(draft)
            } catch {
                reporter.finish(); consumer.cancel()
                await ScanVisionWorker.shared.removeFolder(results); self?.fail(error, token: token)
            }
        }
    }
    func captureArea() {
        guard !isBusy else { return }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            error = String(localized: "Enable Screen Recording, then retry.")
            return
        }
        let token = begin(String(localized: "Choose an area. Escape cancels."))
        isCapturing = true
        work = Task { [weak self] in
            do {
                let captured = try await ScanScreenCapture.capture()
                guard let self, generation == token else { if let captured { await ScanVisionWorker.shared.removeFolder(captured.deletingLastPathComponent()) }; return }
                if let captured {
                    // Import pixels before deleting the owned screenshot.
                    let bytes = try await ScanScreenCapture.readAndRemove(captured)
                    try Task.checkCancellation()
                    guard generation == token else { return }
                    isCapturing = false; finish(token)
                    importInputs([.data(bytes)])
                } else {
                    isCapturing = false; finish(token)
                    status = String(localized: "Capture cancelled. Pick another source whenever you’re ready.")
                }
            } catch {
                guard let self, generation == token else { return }
                isCapturing = false; fail(error, token: token)
            }
        }
    }
    func copyText() {
        guard let text = report?.text, !text.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        status = String(localized: "Text copied!")
    }
    func copyCode(_ code: DetectedBarcode) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code.payload, forType: .string); status = String(localized: "Code copied!")
    }
    private func begin(_ message: String) -> UUID {
        generation = UUID(); isBusy = true; error = nil; progress = nil; status = message; return generation
    }
    private func finish(_ token: UUID) { guard generation == token else { return }; isBusy = false; progress = nil; work = nil }
    private func fail(_ error: Error, token: UUID) {
        guard generation == token else { return }
        if error is CancellationError { status = String(localized: "Stopped. Your existing pages are safe.") }
        else { self.error = error.localizedDescription }
        finish(token)
    }
    func shutdown() {
        let previous = work, draft = folder
        cancel()
        Task { await previous?.value; await ScanVisionWorker.shared.removeFolder(draft) }
    }
}

actor ScanScreenCapture {
    static func capture() async throws -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Notchi/Captures/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let output = folder.appendingPathComponent("Selection.png")
        let process = CaptureProcess(output: output)
        do {
            let completed = try await withTaskCancellationHandler { try await process.run() } onCancel: { process.cancel() }
            if completed { return output }
            try? FileManager.default.removeItem(at: folder); return nil
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }
    static func readAndRemove(_ output: URL) async throws -> Data {
        defer { try? FileManager.default.removeItem(at: output.deletingLastPathComponent()) }
        return try Data(contentsOf: output, options: .mappedIfSafe)
    }
}
private final class CaptureProcess: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var cancelled = false
    private let output: URL
    init(output: URL) { self.output = output }
    func cancel() {
        lock.lock(); cancelled = true; if process.isRunning { process.terminate() }; lock.unlock()
    }
    func run() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [self] in
                do {
                    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    process.arguments = ["-i", "-s", "-x", "-t", "png", output.path]
                    process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
                    lock.lock()
                    if cancelled { lock.unlock(); throw CancellationError() }
                    do { try process.run(); lock.unlock() } catch { lock.unlock(); throw error }
                    process.waitUntilExit()
                    lock.lock(); let wasCancelled = cancelled; lock.unlock()
                    if wasCancelled { throw CancellationError() }
                    continuation.resume(returning: process.terminationStatus == 0 && FileManager.default.fileExists(atPath: output.path))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
