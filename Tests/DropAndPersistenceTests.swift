import XCTest
import AppKit
import UniformTypeIdentifiers

final class DropAndPersistenceTests: XCTestCase {
    private var temporary: URL!
    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent("NotchiDropTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: temporary) }
    func testSystemDragRequiresMovementAndPasteboardChangeThenEndsOnRelease() {
        var tracker = SystemDragTracker(changeCount: 10)
        XCTAssertFalse(tracker.update(changeCount: 10, buttonDown: true, mouseDown: true, hasPayload: true))
        XCTAssertFalse(tracker.update(changeCount: 10, buttonDown: true, mouseDragged: true, hasPayload: true))
        XCTAssertTrue(tracker.update(changeCount: 11, buttonDown: true, hasPayload: true))
        XCTAssertTrue(tracker.update(changeCount: 11, buttonDown: true, hasPayload: true))
        XCTAssertFalse(tracker.update(changeCount: 11, buttonDown: false, hasPayload: true))
        XCTAssertFalse(tracker.update(changeCount: 11, buttonDown: true, mouseDragged: true, hasPayload: true))
    }
    func testImporterKeepsFileReferencesAndMaterializesOnlyNonFilePayloads() async throws {
        let original = temporary.appendingPathComponent("original.txt")
        try Data("original".utf8).write(to: original)
        let importer = DropImporter(root: temporary.appendingPathComponent("imports"))
        let result = await importer.resolve(payloads: [.file(original), .text("a note\nwith two lines"), .web(URL(string: "https://example.com/path")!)])
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(result.urls.count, 3)
        XCTAssertEqual(result.urls[0], original)
        XCTAssertEqual(try String(contentsOf: result.urls[1], encoding: .utf8), "a note\nwith two lines")
        let dictionary = try PropertyListSerialization.propertyList(from: Data(contentsOf: result.urls[2]), format: nil) as? [String: String]
        XCTAssertEqual(dictionary?["URL"], "https://example.com/path")
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "original")
        XCTAssertFalse(DropImporter.safeName("../../escape", extension: "txt").contains("/"))
    }
    @MainActor
    func testNativePasteboardPreservesMultipleFileAndFolderReferences() async throws {
        let file = temporary.appendingPathComponent("a.txt")
        let folder = temporary.appendingPathComponent("folder")
        try Data("a".utf8).write(to: file)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([file as NSURL, folder as NSURL])
        let payloads = PasteboardDrop.read(pasteboard)
        let result = await DropImporter(root: temporary).resolve(payloads: payloads)
        XCTAssertEqual(Set(result.urls.map(\.path)), Set([file.path, folder.path]))
        XCTAssertTrue(result.errors.isEmpty)
    }
    @MainActor
    func testProviderImportAndDuplicateDropSessionAreCoalesced() async throws {
        let store = ShelfStore(persistence: MemoryShelfPersistence(), importer: DropImporter(root: temporary))
        store.setDropTargeted(true)
        let provider = NSItemProvider(object: "hello from another app" as NSString)
        XCTAssertTrue(store.acceptDrop([provider]))
        XCTAssertTrue(store.acceptDrop([provider]))
        let deadline = Date().addingTimeInterval(5)
        while store.isImporting && Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertFalse(store.isImporting)
        XCTAssertEqual(store.files.count, 1)
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(store.files.first).url, encoding: .utf8), "hello from another app")
        store.shutdown()
    }
    @MainActor
    func testSecurityScopedBookmarksRestoreShelfWithoutCopyingOriginal() async throws {
        let url = temporary.appendingPathComponent("keep.txt")
        try Data("keep me".utf8).write(to: url)
        let persistence = MemoryShelfPersistence()
        let first = ShelfStore(persistence: persistence)
        first.add([url], isNew: true, originalSize: 100)
        let id = try XCTUnwrap(first.files.first?.id)
        XCTAssertEqual(persistence.records.count, 1)
        first.shutdown()
        let restored = ShelfStore(persistence: persistence)
        XCTAssertEqual(restored.files.count, 1)
        XCTAssertEqual(restored.files.first?.id, id)
        XCTAssertEqual(restored.files.first?.url, url)
        XCTAssertTrue(restored.files.first?.isNew == true)
        XCTAssertEqual(restored.files.first?.originalSize, 100)
        restored.clear()
        XCTAssertTrue(persistence.records.isEmpty)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "keep me")
    }
    @MainActor
    func testOfflineBookmarkIsKeptForFutureLaunch() async throws {
        let file = temporary.appendingPathComponent("offline.txt")
        try Data("offline".utf8).write(to: file)
        let persistence = MemoryShelfPersistence()
        let store = ShelfStore(persistence: persistence)
        store.add([file]); store.shutdown()
        try FileManager.default.removeItem(at: file)
        let restored = ShelfStore(persistence: persistence)
        XCTAssertTrue(restored.files.isEmpty)
        XCTAssertEqual(persistence.records.count, 1)
    }
}
