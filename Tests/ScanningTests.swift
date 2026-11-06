import XCTest
import CoreImage
import CoreText
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import QuartzCore

final class ScanningTests: XCTestCase {
    private var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("NotchiScanTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }
    private func bitmap(width: Int = 900, height: Int = 1200, dark: Bool = false, hindi: Bool = false) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: dark ? 0 : 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if !dark {
            for (index, value) in ["NOTCHI SCAN TEST", "Invoice 2048", "Total 1234", hindi ? "नमस्ते भारत" : "Keep your originals"].enumerated() {
                let font = CTFontCreateWithName((index == 3 && hindi ? "KohinoorDevanagari-Regular" : "Helvetica") as CFString, index == 3 && hindi ? 66 : 48, nil)
                let text = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)]))
                context.textPosition = CGPoint(x: 65, y: height - 180 - index * 140); CTLineDraw(text, context)
            }
        }
        return try XCTUnwrap(context.makeImage())
    }
    private func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
    func testAccurateOCRRecognizesEnglishAndHindiWhenNativeModelIsAvailable() async throws {
        let image = try bitmap(hindi: true)
        let report = try await ScanVisionWorker.shared.recognize(.data(png(image)))
        XCTAssertTrue(report.text.uppercased().contains("NOTCHI"), report.text)
        XCTAssertTrue(report.text.contains("2048"), report.text)
        if report.languageNotice == nil { XCTAssertTrue(report.text.contains("भारत"), report.text) }
        else { XCTAssertTrue(report.languageNotice?.contains("Hindi") == true) }
        XCTAssertTrue(report.pages[0].lines.allSatisfy { $0.bounds.minX >= 0 && $0.bounds.maxX <= 1.01 })
    }
    func testPerspectiveDocumentDetectionCorrectionAndAllScanLooks() async throws {
        let image = try bitmap(), context = CIContext()
        let transformed = CIImage(cgImage: image).applyingFilter("CIPerspectiveTransform", parameters: [
            "inputTopLeft": CIVector(x: 120, y: 1430), "inputTopRight": CIVector(x: 1090, y: 1510),
            "inputBottomLeft": CIVector(x: 160, y: 100), "inputBottomRight": CIVector(x: 1130, y: 190)])
        let background = CIImage(color: CIColor(red: 0.15, green: 0.16, blue: 0.18)).cropped(to: CGRect(x: 0, y: 0, width: 1250, height: 1600))
        let sample = try XCTUnwrap(context.createCGImage(transformed.composited(over: background), from: background.extent))
        let pages = try await ScanVisionWorker.shared.importPages([.data(png(sample))], into: folder.appendingPathComponent("pages"), look: .color)
        let page = try XCTUnwrap(pages.first)
        XCTAssertNotNil(page.quad)
        XCTAssertTrue(FileManager.default.fileExists(atPath: page.correctedURL.path))
        let gray = try await ScanVisionWorker.shared.restyle(page, look: .grayscale)
        let bw = try await ScanVisionWorker.shared.restyle(page, look: .blackAndWhite)
        XCTAssertEqual(gray.id, page.id); XCTAssertEqual(bw.look, .blackAndWhite)
        XCTAssertNotEqual(gray.correctedURL, page.correctedURL)
        let recognized = try await ScanVisionWorker.shared.recognize(.file(gray.correctedURL))
        XCTAssertTrue(recognized.text.contains("2048"), recognized.text)
    }
    func testLowLightAndInvalidFilesHaveFriendlyErrors() async throws {
        do {
            _ = try await ScanVisionWorker.shared.importPages([.data(png(bitmap(dark: true)))], into: folder, look: .color)
            XCTFail("Dark capture should ask for better lighting")
        } catch { XCTAssertTrue(error.localizedDescription.contains("dark"), error.localizedDescription) }
        do { _ = try await ScanVisionWorker.shared.recognize(.data(Data("not an image".utf8))); XCTFail("Invalid input must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Couldn’t read")) }
    }
    func testQRDetectionAndSafeExplicitOpenLinkPolicy() async throws {
        let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data("https://example.com/notchi".utf8), forKey: "inputMessage")
        let qr = try XCTUnwrap(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let image = try XCTUnwrap(CIContext().createCGImage(qr, from: qr.extent))
        let report = try await ScanVisionWorker.shared.recognize(.data(png(image)), mode: .barcodes)
        let result = try XCTUnwrap(report.pages.first?.barcodes.first)
        XCTAssertEqual(result.payload, "https://example.com/notchi")
        XCTAssertEqual(result.webURL?.host, "example.com")
        XCTAssertNil(DetectedBarcode(payload: "javascript:alert(1)", symbology: "QR", bounds: .zero).webURL)
        XCTAssertNil(DetectedBarcode(payload: "file:///etc/passwd", symbology: "QR", bounds: .zero).webURL)
        XCTAssertNil(DetectedBarcode(payload: "https://name:password@example.com", symbology: "QR", bounds: .zero).webURL)
    }
    func testSearchablePDFTextLayerAndMultiPageOrdering() async throws {
        let image = try bitmap()
        let line = OCRLine(text: "Searchable invoice 2048", bounds: CGRect(x: 0.1, y: 0.7, width: 0.7, height: 0.06), confidence: 1)
        let data = try await ScanVisionWorker.shared.pdfPage(image, lines: [line])
        let page = try XCTUnwrap(PDFDocument(data: data)?.page(at: 0))
        XCTAssertTrue(page.string?.contains("2048") == true, page.string ?? "nil")
        let noText = try await ScanVisionWorker.shared.pdfPage(image, lines: [])
        XCTAssertTrue((PDFDocument(data: noText)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let imported = try await ScanVisionWorker.shared.importPages([.data(png(image)), .data(png(image))], into: folder.appendingPathComponent("draft"), look: .grayscale)
        let reordered = ScanCoordinates.reordered(imported, source: imported[0].id, target: imported[1].id)
        XCTAssertEqual(reordered[0].id, imported[1].id)
        let (stream, reporter) = AsyncStream<ActionProgress>.makeStream()
        let url = try await ScanVisionWorker.shared.export(reordered, searchable: true, into: folder.appendingPathComponent("result"), progress: reporter)
        reporter.finish()
        var updates: [ActionProgress] = []
        for await update in stream { updates.append(update) }
        let fractions = updates.compactMap(\.fraction)
        XCTAssertEqual(fractions.last, 1)
        XCTAssertTrue(zip(fractions, fractions.dropFirst()).allSatisfy { $0 <= $1 })
        XCTAssertTrue(updates.contains { $0.message.contains("page 2 of 2") })
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(pdf.pageCount, 2)
        XCTAssertTrue(pdf.string?.contains("2048") == true)
    }
    func testOCRRasterizedRotatedPDFAndBlankTextReport() async throws {
        let image = try bitmap()
        let data = try await ScanVisionWorker.shared.pdfPage(image, lines: [])
        let pdf = try XCTUnwrap(PDFDocument(data: data)); pdf.page(at: 0)?.rotation = 90
        let rotated = try XCTUnwrap(pdf.dataRepresentation())
        let report = try await ScanVisionWorker.shared.recognize(.data(rotated))
        XCTAssertEqual(report.pages.count, 1)
        XCTAssertGreaterThan(report.pages[0].image.width, report.pages[0].image.height)
        let empty = RecognitionReport(pages: [RecognitionPage(image: image, lines: [], barcodes: []), RecognitionPage(image: image, lines: [], barcodes: [])])
        XCTAssertTrue(empty.text.isEmpty)
    }
    func testBoundingBoxesAndPerspectiveAnimationMapCornersCorrectly() {
        let frame = ScanCoordinates.fittedRect(imageSize: CGSize(width: 200, height: 100), canvas: CGSize(width: 300, height: 300))
        XCTAssertEqual(frame, CGRect(x: 0, y: 75, width: 300, height: 150))
        XCTAssertEqual(ScanCoordinates.box(CGRect(x: 0.1, y: 0.8, width: 0.2, height: 0.1), in: frame).minY, 90, accuracy: 0.001)
        let source = [CGPoint(x: 10, y: 20), CGPoint(x: 80, y: 10), CGPoint(x: 90, y: 95), CGPoint(x: 5, y: 90)]
        let target = [CGPoint.zero, CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)]
        let transform = ScanPerspectiveEffect.transform(source: source, target: target)
        for (s, t) in zip(source, target) {
            let denominator = transform.m14 * s.x + transform.m24 * s.y + 1
            XCTAssertEqual((transform.m11 * s.x + transform.m21 * s.y + transform.m41) / denominator, t.x, accuracy: 0.001)
            XCTAssertEqual((transform.m12 * s.x + transform.m22 * s.y + transform.m42) / denominator, t.y, accuracy: 0.001)
        }
    }
    @MainActor
    func testExportProgressTimeoutKeepsPagesAndAllowsNonSearchableRetry() async throws {
        let scanner = ScanCoordinator { pages, searchable, output, progress in
            if searchable {
                progress.yield(.init(fraction: 0.42, message: "reading text · page 1 of 1…"))
                try await Task.sleep(for: .milliseconds(120))
                throw ScanError.recognitionTimedOut
            }
            return try await ScanVisionWorker.shared.export(pages, searchable: false, into: output, progress: progress)
        }
        defer { scanner.shutdown() }
        let store = ShelfStore(persistence: MemoryShelfPersistence())
        scanner.importInputs([.data(try png(bitmap()))])
        try await waitUntil { !scanner.isBusy }
        let ids = scanner.pages.map(\.id)
        XCTAssertEqual(ids.count, 1)
        scanner.export(to: store)
        try await waitUntil { scanner.progress == 0.42 }
        XCTAssertTrue(scanner.status.contains("page 1 of 1"))
        try await waitUntil { !scanner.isBusy }
        XCTAssertTrue(scanner.error?.contains("turn off Searchable text layer") == true)
        XCTAssertEqual(scanner.pages.map(\.id), ids)
        XCTAssertTrue(store.files.isEmpty)
        scanner.searchable = false
        scanner.export(to: store)
        try await waitUntil { !scanner.isBusy }
        XCTAssertNil(scanner.error)
        XCTAssertTrue(scanner.pages.isEmpty)
        XCTAssertEqual(store.files.count, 1)
        let output = try XCTUnwrap(store.files.first?.url)
        defer { try? FileManager.default.removeItem(at: output.deletingLastPathComponent()) }
        XCTAssertEqual(PDFDocument(url: output)?.pageCount, 1)
    }

    func testStalledNativeRequestTimesOutWithoutWaitingForNativeReturn() async throws {
        let blocker = DispatchSemaphore(value: 0)
        defer { blocker.signal() }
        let execution = ScanRequestExecution(timeout: 0.05, operation: { blocker.wait() }, cancel: {})
        let start = Date()
        do { try await execution.run(); XCTFail("The stalled request must time out") }
        catch let error as ScanError {
            guard case .recognitionTimedOut = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }

    func testCancelReturnsEvenWhenNativeCancellationDoesNotUnblock() async throws {
        let started = expectation(description: "Native work started")
        let blocker = DispatchSemaphore(value: 0)
        defer { blocker.signal() }
        let execution = ScanRequestExecution(timeout: 10, operation: { started.fulfill(); blocker.wait() }, cancel: {})
        let task = Task { try await execution.run() }
        await fulfillment(of: [started], timeout: 1)
        let start = Date(); task.cancel()
        do { try await task.value; XCTFail("Cancelled work must not report success") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            guard Date() < deadline else { XCTFail("Scanner state did not settle"); throw ScanError.exportFailed }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor
    func testContinuityRequestorAcceptsImagePDFAndPasteboardWithoutHardware() throws {
        XCTAssertTrue(ContinuityCameraButton.CameraButton.accepts(.tiff))
        XCTAssertTrue(ContinuityCameraButton.CameraButton.accepts(.pdf))
        XCTAssertFalse(ContinuityCameraButton.CameraButton.accepts(.string))
        let button = ContinuityCameraButton.CameraButton(frame: .zero)
        XCTAssertNotNil(button.validRequestor(forSendType: nil, returnType: .png))
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.setData(try png(bitmap()), forType: .png)
        // No service is invoked and no photo/device capture is requested by this test.
        XCTAssertFalse(button.readSelection(from: board)) // no coordinator assigned
    }
}
