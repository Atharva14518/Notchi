import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers

final class NotchiTests: XCTestCase {
    private var temporary: URL!

    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporary)
    }

    func testNotchedScreenKeepsBothPanelStatesAttachedToTop() {
        let frame = CGRect(x: -1728, y: 90, width: 1728, height: 1117)
        let geometry = NotchGeometry(screenFrame: frame, topInset: 32,
                                     leftArea: CGRect(x: -1728, y: 1175, width: 764, height: 32),
                                     rightArea: CGRect(x: -764, y: 1175, width: 764, height: 32))
        XCTAssertEqual(geometry.notchWidth, 200)
        for expanded in [false, true] {
            XCTAssertEqual(geometry.frame(expanded: expanded).midX, frame.midX)
            XCTAssertEqual(geometry.frame(expanded: expanded).maxY, frame.maxY)
        }
        XCTAssertEqual(geometry.collapsedSize.width, geometry.notchWidth)
        XCTAssertEqual(geometry.collapsedSize.height, 32)
    }

    func testUnnotchedScreenHasCompactFallback() {
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1280, height: 800), topInset: 0)
        XCTAssertEqual(geometry.notchWidth, 0)
        XCTAssertEqual(geometry.collapsedSize, CGSize(width: 170, height: 30))
        XCTAssertEqual(geometry.frame(expanded: true).maxY, 792)
    }

    func testCursorScreenSelectionSupportsNegativeAndStackedDisplays() {
        let frames = [CGRect(x: 0, y: 0, width: 1728, height: 1117),
                      CGRect(x: -1920, y: 200, width: 1920, height: 1080),
                      CGRect(x: 0, y: 1117, width: 1280, height: 800)]
        XCTAssertEqual(NotchGeometry.screenIndex(containing: CGPoint(x: -50, y: 500), frames: frames), 1)
        XCTAssertEqual(NotchGeometry.screenIndex(containing: CGPoint(x: 800, y: 1200), frames: frames), 2)
        XCTAssertNil(NotchGeometry.screenIndex(containing: CGPoint(x: -2000, y: 0), frames: frames))
    }

    func testNotchUsesAuxiliaryGapCenterAndPillFallbackForMissingAreas() {
        let frame = CGRect(x: -1000, y: 0, width: 1000, height: 800)
        let geometry = NotchGeometry(screenFrame: frame, topInset: 30,
            leftArea: CGRect(x: -1000, y: 770, width: 350, height: 30),
            rightArea: CGRect(x: -450, y: 770, width: 450, height: 30))
        XCTAssertEqual(geometry.frame(expanded: false).midX, -550)
        XCTAssertTrue(geometry.hotZone.contains(CGPoint(x: -657, y: 765)))
        XCTAssertFalse(NotchGeometry(screenFrame: frame, topInset: 30).hasNotch)
    }

    func testRoundedShapeExcludesInvisibleCanvasAndCorners() {
        let metrics = SilhouetteMetrics(size: CGSize(width: 420, height: 180), topRadius: 0, bottomRadius: 24)
        let shape = NotchSilhouette(metrics: metrics).path(in: CGRect(x: 0, y: 0, width: 484, height: 220))
        XCTAssertTrue(shape.contains(CGPoint(x: 242, y: 30)))
        XCTAssertTrue(shape.contains(CGPoint(x: 33, y: 1)))
        XCTAssertFalse(shape.contains(CGPoint(x: 10, y: 20)))
        XCTAssertFalse(shape.contains(CGPoint(x: 33, y: 179)))
        XCTAssertFalse(shape.contains(CGPoint(x: 242, y: 200)))
    }

    func testHoverDebounceExitDelayAndHeldOpenDrag() {
        var intent = HoverIntent()
        XCTAssertNil(intent.update(inside: true, expanded: false, heldOpen: false, now: 0))
        XCTAssertNil(intent.update(inside: true, expanded: false, heldOpen: false, now: 0.079))
        XCTAssertEqual(intent.update(inside: true, expanded: false, heldOpen: false, now: 0.08), true)
        XCTAssertNil(intent.update(inside: false, expanded: true, heldOpen: false, now: 0.1))
        XCTAssertNil(intent.update(inside: false, expanded: true, heldOpen: false, now: 0.499))
        XCTAssertNil(intent.update(inside: false, expanded: true, heldOpen: true, now: 2))
        XCTAssertNil(intent.update(inside: false, expanded: true, heldOpen: false, now: 3))
        XCTAssertEqual(intent.update(inside: false, expanded: true, heldOpen: false, now: 3.4), false)
        // A brief entry that ends before the debounce never expands later.
        intent = HoverIntent()
        XCTAssertNil(intent.update(inside: true, expanded: false, heldOpen: false, now: 4))
        XCTAssertNil(intent.update(inside: false, expanded: false, heldOpen: false, now: 4.02))
        XCTAssertNil(intent.update(inside: false, expanded: false, heldOpen: false, now: 5))
    }

    @MainActor
    func testCancellationBeforeAnticipationCannotMutateCollapsedShape() async throws {
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1280, height: 800), topInset: 0)
        let model = OverlayPresentation(geometry: geometry)
        model.transition(to: true, reduceMotion: false)
        model.transition(to: false, reduceMotion: false)
        try await Task.sleep(for: .seconds(0.7))
        XCTAssertEqual(model.metrics, geometry.collapsedMetrics)
        XCTAssertEqual(model.contentStage, 0)
        XCTAssertEqual(model.phase, .collapsed)
    }

    @MainActor
    func testExpansionReversalAndDisplayResetCancelOldContentReveals() async throws {
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1280, height: 800), topInset: 0)
        let model = OverlayPresentation(geometry: geometry)
        model.transition(to: true, reduceMotion: false)
        try await Task.sleep(for: .seconds(0.12))
        model.transition(to: false, reduceMotion: false)
        try await Task.sleep(for: .seconds(0.06))
        model.transition(to: true, reduceMotion: false)
        try await Task.sleep(for: .seconds(0.7))
        XCTAssertEqual(model.phase, .expanded)
        XCTAssertEqual(model.contentStage, 3)
        let other = NotchGeometry(screenFrame: CGRect(x: -1440, y: 0, width: 1440, height: 900), topInset: 0)
        model.transition(to: false, reduceMotion: false)
        model.transition(to: true, reduceMotion: false)
        model.reset(geometry: other)
        try await Task.sleep(for: .seconds(0.7))
        XCTAssertEqual(model.geometry, other)
        XCTAssertEqual(model.metrics, other.collapsedMetrics)
        XCTAssertEqual(model.contentStage, 0)
    }

    @MainActor
    func testReduceMotionChangesImmediatelyWithoutPendingContent() async throws {
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1280, height: 800), topInset: 0)
        let model = OverlayPresentation(geometry: geometry)
        model.transition(to: true, reduceMotion: true)
        XCTAssertEqual(model.metrics, geometry.expandedMetrics)
        XCTAssertEqual(model.contentStage, 3)
        model.transition(to: false, reduceMotion: true)
        XCTAssertEqual(model.metrics, geometry.collapsedMetrics)
        XCTAssertEqual(model.contentStage, 0)
    }

    @MainActor
    func testShelfDeduplicatesAndClearPreservesOriginals() async throws {
        let file = temporary.appendingPathComponent("original.txt")
        try Data("keep me".utf8).write(to: file)
        let store = ShelfStore(persistence: MemoryShelfPersistence())
        store.add([file, file])
        XCTAssertEqual(store.files.count, 1)
        XCTAssertEqual(store.files.first?.name, "original.txt")
        store.clear()
        XCTAssertTrue(store.files.isEmpty)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "keep me")
    }

    func testArchivePreservesCollidingNamesAndFolderContents() throws {
        let first = temporary.appendingPathComponent("first")
        let second = temporary.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let a = first.appendingPathComponent("same.txt")
        let b = second.appendingPathComponent("same.txt")
        try Data("first".utf8).write(to: a)
        try Data("second".utf8).write(to: b)
        let folder = temporary.appendingPathComponent("folder with spaces")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: folder.appendingPathComponent("nested.txt"))
        let archive = temporary.appendingPathComponent("result.zip")
        try Compression.archive(urls: [a, b, folder], destination: archive)
        let extracted = temporary.appendingPathComponent("extracted")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, extracted.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let files = extracted.appendingPathComponent("Files")
        XCTAssertEqual(try String(contentsOf: files.appendingPathComponent("same.txt"), encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: files.appendingPathComponent("same 2.txt"), encoding: .utf8), "second")
        XCTAssertEqual(try String(contentsOf: files.appendingPathComponent("folder with spaces/nested.txt"), encoding: .utf8), "nested")
    }

    func testImageConversionProducesReadablePNGAndJPEG() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let pixels = try XCTUnwrap(bitmap.bitmapData)
        for y in 0..<8 {
            for x in 0..<12 {
                let offset = y * bitmap.bytesPerRow + x * 4
                pixels[offset] = 125
                pixels[offset + 1] = 92
                pixels[offset + 2] = 255
                pixels[offset + 3] = 255
            }
        }
        let source = temporary.appendingPathComponent("source.png")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: source)
        for format in [ImageFormat.png, .jpeg] {
            let destination = temporary.appendingPathComponent("output.\(format.fileExtension)")
            try ImageConversion.convert(source: source, destination: destination, format: format)
            let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL, nil))
            XCTAssertEqual(CGImageSourceGetType(imageSource) as String?, format.contentType.identifier)
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
            XCTAssertEqual(image.width, 12)
            XCTAssertEqual(image.height, 8)
            let pixel = try XCTUnwrap(NSBitmapImageRep(cgImage: image).colorAt(x: 4, y: 4))
            XCTAssertGreaterThan(pixel.blueComponent, pixel.redComponent)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testInvalidImageThrowsWithoutCreatingOutput() throws {
        let source = temporary.appendingPathComponent("bad.png")
        let destination = temporary.appendingPathComponent("output.jpg")
        try Data("not an image".utf8).write(to: source)
        XCTAssertThrowsError(try ImageConversion.convert(source: source, destination: destination, format: .jpeg))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
}
