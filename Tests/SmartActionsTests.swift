import XCTest
import AppKit
import ImageIO
import PDFKit
import CoreText
import UniformTypeIdentifiers

final class SmartActionsTests: XCTestCase {
    private var temporary: URL!
    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent("NotchiTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: temporary) }

    private func image(name: String = "source.png", width: Int = 256, height: Int = 192,
                       format: UTType = .png, metadata: [CFString: Any] = [:]) throws -> URL {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let pixels = try XCTUnwrap(bitmap.bitmapData)
        var random: UInt32 = 941
        for y in 0..<height { for x in 0..<width {
            let p = y * bitmap.bytesPerRow + x * 4
            for c in 0..<3 {
                random = 1664525 &* random &+ 1013904223
                pixels[p + c] = UInt8(truncatingIfNeeded: random >> 24)
            }
            pixels[p + 3] = 255
        } }
        let url = temporary.appendingPathComponent(name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, format.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(bitmap.cgImage), metadata as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
    private func run(_ operation: NativeOperation, item: ShelfItem) async throws -> (ActionResult, [ActionProgress]) {
        let (stream, reporter) = AsyncStream<ActionProgress>.makeStream()
        let result = try await NativeFileAction(operation: operation).run(item: item, progress: reporter)
        reporter.finish()
        var updates: [ActionProgress] = []
        for await update in stream { updates.append(update) }
        return (result, updates)
    }
    private func clean(_ result: ActionResult) { if let first = result.outputs.first { try? FileManager.default.removeItem(at: first.deletingLastPathComponent()) } }

    func testConvertActionsWriteCorrectTypesAndLeaveOriginalUntouched() async throws {
        let source = try image()
        let original = try Data(contentsOf: source)
        for format in ImageFormat.supported {
            let (result, updates) = try await run(.convert(format), item: ShelfItem(url: source))
            defer { clean(result) }
            let url = try XCTUnwrap(result.outputs.first)
            let decoded = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            XCTAssertEqual(CGImageSourceGetType(decoded) as String?, format.contentType.identifier)
            let pixels = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
            XCTAssertEqual(pixels.width, 256)
            XCTAssertEqual(pixels.height, 192)
            XCTAssertEqual(updates.last?.fraction, 1)
            XCTAssertEqual(result.beforeBytes, Int64(original.count))
            XCTAssertGreaterThan(result.afterBytes, 0)
            XCTAssertEqual(try Data(contentsOf: source), original)
        }
    }

    func testCompressionPresetsReduceNoisyPNGAndOrderOutputQuality() async throws {
        let source = try image()
        let original = try Data(contentsOf: source)
        var sizes: [Int64] = []
        for preset in QualityPreset.allCases {
            let (result, _) = try await run(.compressImage(preset), item: ShelfItem(url: source))
            defer { clean(result) }
            sizes.append(result.afterBytes)
            XCTAssertLessThan(result.afterBytes, Int64(original.count))
            let decoded = try XCTUnwrap(CGImageSourceCreateWithURL(try XCTUnwrap(result.outputs.first) as CFURL, nil))
            XCTAssertEqual(CGImageSourceGetType(decoded) as String?, UTType.jpeg.identifier)
            XCTAssertNotNil(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
        }
        XCTAssertLessThan(sizes[0], sizes[1])
        XCTAssertLessThan(sizes[1], sizes[2])
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testResizePreservesAspectRatioAndDoesNotUpscale() async throws {
        let source = try image(width: 240, height: 120)
        for (spec, expected) in [(ResizeSpec.fraction(0.25), 60), (.fraction(0.5), 120), (.maxDimension(100), 100), (.maxDimension(1600), 240)] {
            let (result, _) = try await run(.resize(spec), item: ShelfItem(url: source))
            defer { clean(result) }
            let data = try XCTUnwrap(CGImageSourceCreateWithURL(try XCTUnwrap(result.outputs.first) as CFURL, nil))
            let pixels = try XCTUnwrap(CGImageSourceCreateImageAtIndex(data, 0, nil))
            XCTAssertEqual(pixels.width, expected)
            XCTAssertEqual(pixels.height, expected / 2)
        }
    }

    func testMetadataStrippingRemovesGPSAndEXIFAndNormalizesOrientation() async throws {
        let source = try image(name: "private.jpg", width: 120, height: 80, format: .jpeg, metadata: [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 10, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 20, kCGImagePropertyGPSLongitudeRef: "E"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Private Camera", kCGImagePropertyTIFFModel: "Private Model"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:01:02 12:00:00"]])
        let input = try XCTUnwrap(CGImageSourceCreateWithURL(source as CFURL, nil))
        let original = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(input, 0, nil) as? [CFString: Any])
        XCTAssertNotNil(original[kCGImagePropertyGPSDictionary])
        let (result, _) = try await run(.stripMetadata, item: ShelfItem(url: source))
        defer { clean(result) }
        let output = try XCTUnwrap(CGImageSourceCreateWithURL(try XCTUnwrap(result.outputs.first) as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(output, 0, nil) as? [CFString: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertNil(properties[kCGImagePropertyExifDictionary])
        XCTAssertNil(properties[kCGImagePropertyTIFFDictionary])
        let pixels = try XCTUnwrap(CGImageSourceCreateImageAtIndex(output, 0, nil))
        XCTAssertEqual(pixels.width, 80)
        XCTAssertEqual(pixels.height, 120)
    }

    func testConversionBakesOrientationWithoutDuplicatingRotationTags() async throws {
        let source = try image(name: "rotated.jpg", width: 120, height: 80, format: .jpeg,
            metadata: [kCGImagePropertyOrientation: 6,
                kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFOrientation: 6],
                kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:01:02 12:00:00"]])
        let original = try Data(contentsOf: source)
        let (result, _) = try await run(.convert(.jpeg), item: ShelfItem(url: source))
        defer { clean(result) }
        let output = try XCTUnwrap(CGImageSourceCreateWithURL(try XCTUnwrap(result.outputs.first) as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(output, 0, nil) as? [CFString: Any])
        let pixels = try XCTUnwrap(CGImageSourceCreateImageAtIndex(output, 0, nil))
        XCTAssertEqual(pixels.width, 80)
        XCTAssertEqual(pixels.height, 120)
        XCTAssertEqual((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, 1)
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let orientation = tiff[kCGImagePropertyTIFFOrientation] as? NSNumber {
            XCTAssertEqual(orientation.intValue, 1)
        }
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testSavingsRoundPercentAndReportBytesWithoutNegativeSavings() {
        let smaller = SizeComparison(before: 4_200_000, after: 890_000)
        XCTAssertEqual(smaller.saved, 3_310_000)
        XCTAssertEqual(smaller.percent, 79)
        XCTAssertTrue(smaller.description.contains("79% smaller"))
        let larger = SizeComparison(before: 100, after: 200)
        XCTAssertEqual(larger.saved, 0)
        XCTAssertEqual(larger.percent, 0)
        XCTAssertTrue(larger.description.contains("larger"))
        XCTAssertEqual(SizeComparison(before: 0, after: 20).percent, 0)
    }

    func testPNGMetadataCleanupPreservesCompressedPixelData() throws {
        let url = try image()
        let before = try Data(contentsOf: url)
        func pixelChunks(_ data: Data) throws -> Data {
            var result = Data()
            var offset = 8
            while offset + 12 <= data.count {
                let length = data[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
                guard length <= data.count - offset - 12 else { throw ActionError.failed("Invalid test PNG") }
                if String(data: data[offset + 4..<offset + 8], encoding: .ascii) == "IDAT" {
                    result.append(data[offset + 8..<offset + 8 + length])
                }
                offset += length + 12
            }
            return result
        }
        try PNGMetadataStripper.strip(at: url)
        let after = try Data(contentsOf: url)
        XCTAssertEqual(try pixelChunks(before), try pixelChunks(after))
        let decoded = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(decoded, 0, nil) as? [CFString: Any])
        XCTAssertNil(properties[kCGImagePropertyExifDictionary])
    }

    func testTruncatedPNGCleanupFailsWithoutReplacingFile() throws {
        let url = temporary.appendingPathComponent("truncated.png")
        let data = Data([137, 80, 78, 71, 13, 10, 26, 10, 255, 255, 255, 255, 73, 72, 68, 82])
        try data.write(to: url)
        XCTAssertThrowsError(try PNGMetadataStripper.strip(at: url))
        XCTAssertEqual(try Data(contentsOf: url), data)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporary.path), ["truncated.png"])
    }

    func testUnsupportedWebPIsFilteredAndInvalidInputFailsWithoutOutput() async throws {
        let source = temporary.appendingPathComponent("bad.png")
        try Data("not an image".utf8).write(to: source)
        let file = ShelfItem(url: source)
        if !ImageFormat.supported.contains(.webp) { XCTAssertFalse(NativeFileAction(operation: .convert(.webp)).isSupported(for: file)) }
        do { _ = try await run(.convert(.png), item: file); XCTFail("Invalid image should throw") }
        catch { XCTAssertTrue(FileManager.default.fileExists(atPath: source.path)) }
    }

    private func pdf(name: String, pages: Int) throws -> URL {
        let url = temporary.appendingPathComponent(name)
        var media = CGRect(x: 0, y: 0, width: 200, height: 300)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &media, nil))
        for index in 0..<pages {
            context.beginPDFPage(nil)
            context.textPosition = CGPoint(x: 20, y: 200)
            let text = NSAttributedString(string: "Hello page \(index + 1)", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 16, nil)])
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }
    func testPDFMergeSplitExtractAndRasterCompression() async throws {
        let a = ShelfItem(url: try pdf(name: "a.pdf", pages: 2))
        let b = ShelfItem(url: try pdf(name: "b.pdf", pages: 1))
        let (merged, _) = try await run(.mergePDFs([a, b]), item: a)
        defer { clean(merged) }
        XCTAssertEqual(PDFDocument(url: try XCTUnwrap(merged.outputs.first))?.pageCount, 3)
        let (split, _) = try await run(.splitPDF, item: a)
        defer { clean(split) }
        XCTAssertEqual(split.outputs.count, 2)
        for url in split.outputs { XCTAssertEqual(PDFDocument(url: url)?.pageCount, 1) }
        let (text, _) = try await run(.extractText, item: a)
        defer { clean(text) }
        XCTAssertTrue(try String(contentsOf: XCTUnwrap(text.outputs.first), encoding: .utf8).contains("Hello page 1"))
        let (compressed, _) = try await run(.compressPDF(.tiny), item: a)
        defer { clean(compressed) }
        let document = try XCTUnwrap(PDFDocument(url: XCTUnwrap(compressed.outputs.first)))
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertTrue((document.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testPDFCompressionKeepsRotatedPageDimensionsAndOriginal() async throws {
        let base = try pdf(name: "portrait.pdf", pages: 1)
        let document = try XCTUnwrap(PDFDocument(url: base))
        try XCTUnwrap(document.page(at: 0)).rotation = 90
        let source = temporary.appendingPathComponent("landscape.pdf")
        XCTAssertTrue(document.write(to: source))
        let original = try Data(contentsOf: source)
        let (result, _) = try await run(.compressPDF(.balanced), item: ShelfItem(url: source))
        defer { clean(result) }
        let output = try XCTUnwrap(PDFDocument(url: XCTUnwrap(result.outputs.first)))
        let page = try XCTUnwrap(output.page(at: 0))
        XCTAssertEqual(page.bounds(for: .mediaBox).width, 300, accuracy: 0.1)
        XCTAssertEqual(page.bounds(for: .mediaBox).height, 200, accuracy: 0.1)
        XCTAssertEqual(page.rotation, 0)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testActionCatalogFiltersByKindAndEnablesSelectedPDFMerge() throws {
        let image = ShelfItem(url: try image())
        let pdfA = ShelfItem(url: try pdf(name: "a.pdf", pages: 1))
        let pdfB = ShelfItem(url: try pdf(name: "b.pdf", pages: 1))
        let data = temporary.appendingPathComponent("archive.bin")
        try Data([0, 1, 2]).write(to: data)
        let other = ShelfItem(url: data)
        let imageActions = ActionCatalog.actions(for: image, selected: [image])
        XCTAssertTrue(imageActions.contains { $0.id == "compress-image" })
        XCTAssertFalse(imageActions.contains { $0.id == "split-pdf" })
        XCTAssertTrue(imageActions.allSatisfy { $0.isSupported(for: image) })
        XCTAssertFalse(ActionCatalog.actions(for: pdfA, selected: [pdfA]).contains { $0.id == "merge-pdf" })
        XCTAssertTrue(ActionCatalog.actions(for: pdfA, selected: [pdfA, pdfB]).contains { $0.id == "merge-pdf" })
        XCTAssertEqual(Set(ActionCatalog.actions(for: other, selected: []).map(\.id)), ["zip", "copy-path", "reveal"])
    }
}
