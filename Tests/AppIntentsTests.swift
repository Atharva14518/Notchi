import XCTest
import AppIntents
import AppKit
import ImageIO
import PDFKit
import CoreText
import UniformTypeIdentifiers

final class AppIntentsTests: XCTestCase {
    private var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("NotchiIntentTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }
    @MainActor private func runtime(persistence: MemoryShelfPersistence = MemoryShelfPersistence()) -> IntentRuntime {
        IntentRuntime(store: ShelfStore(persistence: persistence), actions: ActionCoordinator(),
                      stager: IntentFileStager(root: folder.appendingPathComponent("imports")))
    }
    private func png() throws -> URL {
        let image = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 96,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let bytes = try XCTUnwrap(image.bitmapData)
        for i in 0..<(image.bytesPerRow * image.pixelsHigh) { bytes[i] = UInt8(truncatingIfNeeded: i * 31) }
        let url = folder.appendingPathComponent("source.png")
        try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: url)
        return url
    }
    private func cleanup(_ result: IntentFile) {
        if let url = result.fileURL { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    }
    @MainActor
    func testCompressIntentUsesExistingEngineAndReturnsReadableFileWithoutOpeningPanel() async throws {
        let model = runtime(); defer { model.store.shutdown() }
        let source = try png(), original = try Data(contentsOf: source)
        try await IntentRuntime.$testing.withValue(model) {
            let intent = CompressFileIntent()
            intent.file = IntentFile(fileURL: source); intent.preset = .tiny
            let returned = try await intent.perform()
            let output = try XCTUnwrap(returned.value); defer { cleanup(output) }
            let url = try XCTUnwrap(output.fileURL)
            let decoded = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            XCTAssertEqual(CGImageSourceGetType(decoded) as String?, UTType.jpeg.identifier)
            XCTAssertFalse(output.removedOnCompletion)
            XCTAssertFalse(model.store.isExpanded)
            XCTAssertFalse(model.actions.isBusy)
            XCTAssertTrue(model.actions.isComplete)
            XCTAssertEqual(model.actions.successToken, 1)
            XCTAssertEqual(model.store.files.count, 1)
            XCTAssertTrue(model.store.files[0].isNew)
            XCTAssertEqual(try Data(contentsOf: source), original)
            XCTAssertTrue((try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("imports").path)).isEmpty)
        }
    }
    @MainActor
    func testEntityQueryUsesLiveIDsAndLatestConversionUpdatesVisibleCoordinator() async throws {
        let model = runtime(); defer { model.store.shutdown() }
        let source = try png()
        model.store.add([source])
        let first = try XCTUnwrap(model.store.files.first)
        try await IntentRuntime.$testing.withValue(model) {
            let query = ShelfItemQuery()
            let matches = try await query.entities(matching: "SOURCE")
            XCTAssertEqual(matches.map(\.id), [first.id])
            let selected = try await query.entities(for: [first.id, UUID()])
            XCTAssertEqual(selected.map(\.id), [first.id])
            let intent = ConvertFileIntent(); intent.shelfFile = selected[0]; intent.targetFormat = .jpg
            let result = try await intent.perform()
            let output = try XCTUnwrap(result.value); defer { cleanup(output) }
            XCTAssertTrue(model.store.isExpanded)
            XCTAssertEqual(model.actions.job?.itemID, first.id)
            XCTAssertEqual(model.actions.job?.phase, .success)
            XCTAssertEqual(model.store.files.count, 2)
            model.store.remove(first)
            let removed = try await query.entities(for: [first.id])
            XCTAssertTrue(removed.isEmpty)
        }
    }
    @MainActor
    func testLatestFileFallbackAndEmptyShelfError() async throws {
        let model = runtime(); defer { model.store.shutdown() }
        try await IntentRuntime.$testing.withValue(model) {
            do { _ = try await CompressFileIntent().perform(); XCTFail("Empty shelf must fail") }
            catch { XCTAssertTrue(error.localizedDescription.contains("empty")) }
            model.store.add([try png()], expand: false)
            let intent = ConvertFileIntent(); intent.targetFormat = .jpg
            let result = try await intent.perform()
            let output = try XCTUnwrap(result.value); defer { cleanup(output) }
            XCTAssertEqual(output.fileURL?.pathExtension, "jpg")
            XCTAssertFalse(model.store.isExpanded)
        }
    }
    @MainActor
    func testAddFilesSurvivesInputRemovalAndRestoresStableEntityIDsThenClearKeepsOriginals() async throws {
        let persistence = MemoryShelfPersistence()
        let model = runtime(persistence: persistence); defer { model.store.shutdown() }
        let source = folder.appendingPathComponent("input.txt")
        try Data("source bytes".utf8).write(to: source)
        try await IntentRuntime.$testing.withValue(model) {
            let add = AddToShelfIntent(); add.files = [IntentFile(fileURL: source), IntentFile(data: Data("memory".utf8), filename: "note.txt")]
            let result = try await add.perform()
            let entities = try XCTUnwrap(result.value)
            XCTAssertEqual(entities.count, 2)
            XCTAssertFalse(model.store.isExpanded)
            let retainedURLs = model.store.files.map(\.url)
            XCTAssertTrue(retainedURLs.allSatisfy { $0 != source })
            try FileManager.default.removeItem(at: source) // Simulate Shortcuts releasing its temporary input.
            let restored = ShelfStore(persistence: persistence); defer { restored.shutdown() }
            XCTAssertEqual(Set(restored.files.map(\.id)), Set(entities.map(\.id)))
            XCTAssertEqual(try String(contentsOf: retainedURLs[0], encoding: .utf8), "source bytes")
            _ = try await ClearShelfIntent().perform()
            XCTAssertTrue(model.store.files.isEmpty)
            XCTAssertTrue(persistence.records.isEmpty)
            XCTAssertTrue(retainedURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        }
    }
    @MainActor
    func testRemovedEntityAndInvalidFormatFailWithoutUsingAnotherFile() async throws {
        let model = runtime(); defer { model.store.shutdown() }
        let source = try png(); model.store.add([source], expand: false)
        let selected = ShelfItemEntity(try XCTUnwrap(model.store.files.first))
        model.store.clear()
        await IntentRuntime.$testing.withValue(model) {
            let compress = CompressFileIntent(); compress.shelfFile = selected
            do { _ = try await compress.perform(); XCTFail("Removed entity must fail") }
            catch { XCTAssertTrue(error.localizedDescription.contains("unavailable")) }
            let convert = ConvertFileIntent(); convert.file = IntentFile(fileURL: source); convert.targetFormat = .mp4
            do { _ = try await convert.perform(); XCTFail("Image to video must fail") }
            catch { XCTAssertTrue(error.localizedDescription.contains("format")) }
            XCTAssertFalse(model.actions.isBusy)
            XCTAssertFalse(model.store.isExpanded)
        }
    }
    @MainActor
    func testNavigationQueuesUntilAppDelegateIsReadyAndClearRespectsWorkspace() async throws {
        let model = runtime(); defer { model.store.shutdown() }
        try await IntentRuntime.$testing.withValue(model) {
            _ = try await OpenShelfIntent().perform()
            var opened = 0
            model.openShelfHandler = { opened += 1 }
            XCTAssertEqual(opened, 1)
            model.openShelfHandler = { opened += 1 }
            XCTAssertEqual(opened, 1)
            var scanOpened = false
            model.openScanHandler = { scanOpened = true }
            _ = try await OpenScanIntent().perform()
            XCTAssertTrue(scanOpened)
            model.canChangeShelf = { false }
            do { _ = try await ClearShelfIntent().perform(); XCTFail("Cannot clear a live workspace") }
            catch { XCTAssertTrue(error.localizedDescription.contains("current operation")) }
        }
    }
    @MainActor
    func testExtractTextIntentRunsVisionAndReturnsText() async throws {
        // A rendered text PDF exercises the same OCR route as scanned PDFs,
        // rather than substituting a direct PDF text extraction implementation.
        let pdf = folder.appendingPathComponent("text.pdf")
        let data = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        var bounds = CGRect(x: 0, y: 0, width: 600, height: 400)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(bounds)
        let text = NSAttributedString(string: "NOTCHI SHORTCUT TEST", attributes: [
            .font: NSFont.systemFont(ofSize: 32), .foregroundColor: NSColor.black])
        context.textPosition = CGPoint(x: 40, y: 220)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        context.endPDFPage(); context.closePDF(); try (data as Data).write(to: pdf)
        let model = runtime(); defer { model.store.shutdown() }
        try await IntentRuntime.$testing.withValue(model) {
            let intent = ExtractTextIntent(); intent.file = IntentFile(fileURL: pdf)
            let result = try await intent.perform()
            let text = try XCTUnwrap(result.value)
            XCTAssertTrue(text.uppercased().contains("SHORTCUT"), text)
            XCTAssertFalse(model.store.isExpanded)
            if let output = model.actions.outputURL { try? FileManager.default.removeItem(at: output.deletingLastPathComponent()) }
        }
    }
    func testCompressionRoutingUsesNativeAndMediaActions() async throws {
        let pdf = ShelfItem(url: folder.appendingPathComponent("file.pdf"))
        if case .compressPDF(.best) = IntentRuntime.compression(for: pdf, preset: .best).operation {} else { XCTFail("PDF engine") }
        let video = ShelfItem(url: folder.appendingPathComponent("video.mp4"))
        if case .media(.preset(.smallest, _)) = IntentRuntime.compression(for: video, preset: .tiny).operation {} else { XCTFail("Media engine") }
        let document = ShelfItem(url: folder.appendingPathComponent("file.txt"))
        if case .zip = IntentRuntime.compression(for: document, preset: .balanced).operation {} else { XCTFail("ZIP engine") }
    }
    func testStageRejectsInvalidNameWithoutEscapingOwnedStorage() async throws {
        let stager = IntentFileStager(root: folder.appendingPathComponent("imports"))
        do { _ = try await stager.stage(IntentFile(data: Data(), filename: "..")); XCTFail("Invalid name") }
        catch { XCTAssertTrue(error.localizedDescription.contains("name")) }
        let safe = try await stager.stage(IntentFile(data: Data("safe".utf8), filename: "../../safe.txt"))
        XCTAssertTrue(safe.path.hasPrefix(folder.appendingPathComponent("imports").path + "/"))
        XCTAssertEqual(safe.lastPathComponent, "safe.txt")
    }
}
