import XCTest
import AppKit

final class SendFlowTests: XCTestCase {
    private var temporary: URL!
    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent("NotchiSendTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: temporary) }
    private func file(_ name: String, contents: String = "send sample") throws -> URL {
        let url = temporary.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url
    }
    func testPickerHandoffDoesNotReleasePanelUntilServiceEnds() {
        var state = SendLifecycle()
        state.begin()
        XCTAssertTrue(state.keepsPanelOpen)
        XCTAssertFalse(state.isBusy)
        state.pickMore()
        XCTAssertTrue(state.isBusy)
        XCTAssertFalse(state.dismiss())
        state.choseService(true)
        XCTAssertTrue(state.isBusy)
        XCTAssertTrue(state.keepsPanelOpen)
        XCTAssertFalse(state.dismiss())
        state.returned() // Service cancellation or failure returns to the tray.
        XCTAssertTrue(state.keepsPanelOpen)
        XCTAssertFalse(state.isBusy)
        XCTAssertTrue(state.dismiss())
        XCTAssertFalse(state.keepsPanelOpen)
    }
    func testPickerCancellationReturnsToChoosingWithoutConfirmation() {
        var state = SendLifecycle()
        state.begin(); state.pickMore(); state.choseService(false)
        XCTAssertEqual(state.phase, .choosing)
        XCTAssertTrue(state.keepsPanelOpen)
        state.save()
        XCTAssertFalse(state.dismiss())
        state.export()
        XCTAssertTrue(state.isBusy)
        state.confirmed()
        XCTAssertEqual(state.phase, .celebrating)
        XCTAssertFalse(state.dismiss())
    }
    @MainActor
    func testCopyWritesFileURLsNotPathsAndUsesHonestToast() async throws {
        let a = try file("a.txt"), b = try file("b.txt")
        let model = ShareAction(catalog: { _ in [] }, attachments: SendAttachmentPreparer(root: temporary.appendingPathComponent("prepared")))
        defer { model.stop() }
        model.show(items: [ShelfItem(url: a), ShelfItem(url: b)])
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let copied = await model.copyFiles(to: pasteboard)
        XCTAssertTrue(copied)
        let read = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        XCTAssertEqual(Set(read.map(\.lastPathComponent)), Set(["a.txt", "b.txt"]))
        XCTAssertTrue(read.allSatisfy { $0.deletingLastPathComponent() != temporary })
        for url in read { XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "send sample") }
        XCTAssertEqual(model.toast?.text, "Copied!")
        XCTAssertNotEqual(model.toast?.text, "Sent!")
        XCTAssertEqual(model.lifecycle.phase, .celebrating)
        XCTAssertEqual(model.waveToken, 1)
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "send sample")
    }
    @MainActor
    func testSuccessRequiresDelegateConfirmationAndIgnoresDuplicates() throws {
        let item = ShelfItem(url: try file("a.txt"))
        let model = ShareAction(catalog: { _ in [] })
        defer { model.stop() }
        let image = NSImage(size: NSSize(width: 20, height: 20))
        // Custom inert service: no recipient, service UI, or real send is performed.
        let service = NSSharingService(title: "Test service", image: image, alternateImage: nil, handler: {})
        model.show(items: [item])
        model.prepareService(service)
        XCTAssertNil(model.toast)
        XCTAssertEqual(model.lifecycle.phase, .service)
        model.close()
        XCTAssertNotNil(model.session)
        model.sharingService(service, willShareItems: [item.url as NSURL])
        XCTAssertNil(model.toast)
        model.sharingService(service, didShareItems: [item.url as NSURL])
        XCTAssertEqual(model.toast?.text, "Sent!")
        XCTAssertNotNil(model.flight)
        XCTAssertEqual(model.waveToken, 1)
        model.sharingService(service, didShareItems: [item.url as NSURL])
        XCTAssertEqual(model.waveToken, 1)
    }
    @MainActor
    func testFailureAndCancellationNeverReportSent() throws {
        let item = ShelfItem(url: try file("a.txt"))
        let model = ShareAction(catalog: { _ in [] })
        defer { model.stop() }
        let service = NSSharingService(title: "Test", image: NSImage(size: .zero), alternateImage: nil, handler: {})
        model.show(items: [item]); model.prepareService(service)
        model.sharingService(service, didFailToShareItems: [item.url], error: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        XCTAssertNil(model.toast)
        XCTAssertEqual(model.lifecycle.phase, .choosing)
        XCTAssertNil(model.flight)
        model.prepareService(service)
        model.sharingService(service, didFailToShareItems: [item.url], error: NSError(domain: "test", code: 1))
        XCTAssertTrue(model.toast?.isError == true)
        XCTAssertNotEqual(model.toast?.text, "Sent!")
        XCTAssertEqual(model.waveToken, 0)
        XCTAssertFalse(model.isBusy)
    }
    func testSaveCopyPreservesOriginalAndAtomicallyReplacesDestination() async throws {
        let original = try file("original.txt", contents: "new bytes")
        let target = try file("saved.txt", contents: "old bytes")
        try await SendFileExporter().export([original], to: target)
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "new bytes")
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "new bytes")
    }
    func testMultiSaveDisambiguatesNamesAndPreservesFolders() async throws {
        let a = try file("a/same.txt", contents: "one")
        let b = try file("b/same.txt", contents: "two")
        let nested = try file("folder/nested.txt", contents: "nested")
        let target = temporary.appendingPathComponent("saved")
        try await SendFileExporter().export([a, b, nested.deletingLastPathComponent()], to: target)
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("same.txt"), encoding: .utf8), "one")
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("same 2.txt"), encoding: .utf8), "two")
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("folder/nested.txt"), encoding: .utf8), "nested")
    }
    func testSaveRejectsOriginalAndNestedFolderDestinations() async throws {
        let source = try file("folder/source.txt")
        let exporter = SendFileExporter()
        do { try await exporter.export([source], to: source); XCTFail("Must preserve original") } catch { }
        let nested = source.deletingLastPathComponent().appendingPathComponent("nested")
        do { try await exporter.export([source.deletingLastPathComponent()], to: nested); XCTFail("Must not copy a folder into itself") } catch { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: nested.path))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "send sample")
    }
    func testFailedMultiSaveKeepsExistingDestinationAndCleansStaging() async throws {
        let a = try file("a.txt")
        let target = try file("existing.txt", contents: "keep")
        do {
            try await SendFileExporter().export([a, temporary.appendingPathComponent("missing.txt")], to: target)
            XCTFail("A missing input must fail")
        } catch { }
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "keep")
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: temporary.path).contains { $0.hasPrefix(".notchi-save-") })
    }
    func testFlightArcHasCorrectEndpointsAndRisesAboveStraightLine() {
        let path = SendFlightPath(start: CGPoint(x: 20, y: 80), end: CGPoint(x: 200, y: 240))
        XCTAssertEqual(path.point(at: 0), path.start)
        XCTAssertEqual(path.point(at: 1), path.end)
        XCTAssertEqual(path.point(at: -1), path.start)
        XCTAssertEqual(path.point(at: 2), path.end)
        XCTAssertLessThan(path.point(at: 0.5).y, (path.start.y + path.end.y) / 2)
    }

    func testAttachmentCopiesPreserveEveryExtensionBytesAndDuplicateNames() async throws {
        let names = ["a/Scan.pdf", "b/Scan.pdf", "notes.docx", "video.mkv", "audio.flac", "archive.zip", "हिंदी file.custom", "no-extension"]
        let sources = try names.enumerated().map { try file($0.element, contents: "bytes \($0.offset)") }
        let prepared = try await SendAttachmentPreparer(root: temporary.appendingPathComponent("attachments")).prepare(sources)
        XCTAssertEqual(prepared.urls.count, sources.count)
        XCTAssertEqual(prepared.urls[0].lastPathComponent, "Scan.pdf")
        XCTAssertEqual(prepared.urls[1].lastPathComponent, "Scan 2.pdf")
        for (source, output) in zip(sources, prepared.urls) {
            XCTAssertEqual(try Data(contentsOf: source), try Data(contentsOf: output))
            XCTAssertEqual(source.pathExtension, output.pathExtension)
            XCTAssertNotEqual(source, output)
        }
        try FileManager.default.removeItem(at: prepared.urls[0]) // recipient may consume its copy
        XCTAssertTrue(FileManager.default.fileExists(atPath: sources[0].path))
    }

    func testDocumentFoldersBecomeZIPAndArchiveCanFitAfterCompression() async throws {
        let nested = try file("folder/nested.txt", contents: String(repeating: "compress me ", count: 1000))
        let preparer = SendAttachmentPreparer(root: temporary.appendingPathComponent("attachments"))
        let folder = try await preparer.prepare([nested.deletingLastPathComponent()], zipFolders: true)
        XCTAssertEqual(folder.urls.first?.lastPathComponent, "folder.zip")
        XCTAssertTrue(try Data(contentsOf: XCTUnwrap(folder.urls.first)).starts(with: [0x50, 0x4b]))
        let archive = try await preparer.prepare([nested], archiveAll: true, maximumBytes: 4_000)
        let url = try XCTUnwrap(archive.urls.first)
        XCTAssertEqual(url.pathExtension, "zip")
        XCTAssertLessThan(try Data(contentsOf: url).count, 4_000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    }

    func testAttachmentFailureAndSizeLimitLeaveNoPartialCopies() async throws {
        let source = try file("Scan.pdf"), root = temporary.appendingPathComponent("attachments")
        let preparer = SendAttachmentPreparer(root: root)
        do { _ = try await preparer.prepare([source], maximumBytes: 2); XCTFail("Oversized attachment should fail before opening an app") }
        catch { XCTAssertTrue(error.localizedDescription.contains("size limit")) }
        do { _ = try await preparer.prepare([source, temporary.appendingPathComponent("missing.pdf")]); XCTFail("Missing source should fail") }
        catch { }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        XCTAssertEqual(try String(contentsOf: source), "send sample")
    }

    @MainActor
    func testWhatsAppHandoffCopiesPDFAndLaunchesWithoutOpeningDocumentURLs() async throws {
        let source = try file("Scan.pdf"), board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let app = InstalledSendApp(id: "net.whatsapp.WhatsApp", title: "WhatsApp", url: URL(fileURLWithPath: "/Applications/WhatsApp.app"))
        var launches = 0
        let model = ShareAction(catalog: { _ in [] }, attachments: SendAttachmentPreparer(root: temporary.appendingPathComponent("prepared")),
            clipboard: board, launchApp: { launched in XCTAssertEqual(launched.id, app.id); launches += 1 },
            recipientPicker: { _, urls in XCTAssertEqual(urls.count, 1) }, automationPermission: { true })
        defer { model.stop() }
        model.show(items: [ShelfItem(url: source)])
        model.prepareHandoff(app)
        try await waitForPreparation(model)
        XCTAssertEqual(launches, 1)
        XCTAssertEqual(model.handoff?.files.urls.first?.pathExtension, "pdf")
        let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        let copied = try XCTUnwrap(urls?.first)
        XCTAssertNotEqual(copied, source)
        XCTAssertEqual(try Data(contentsOf: copied), try Data(contentsOf: source))
        XCTAssertNil(model.flight); XCTAssertEqual(model.waveToken, 0)
        XCTAssertNotEqual(model.toast?.text, "Sent!")
        model.close()
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied.path), "The destination may read its attachment after the tray closes")
    }

    @MainActor
    func testLaunchFailureKeepsAttachmentsAndOffersManualFallback() async throws {
        let source = try file("report.pdf"), board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let app = InstalledSendApp(id: "test.chat", title: "Chat", url: temporary)
        let model = ShareAction(catalog: { _ in [] }, attachments: SendAttachmentPreparer(root: temporary.appendingPathComponent("prepared")), clipboard: board,
            launchApp: { _ in throw ActionError.failed("Couldn’t open the app.") })
        defer { model.stop() }
        model.show(items: [ShelfItem(url: source)]); model.prepareHandoff(app)
        try await waitForPreparation(model)
        XCTAssertNotNil(model.handoff)
        XCTAssertTrue(model.status.contains("Open the app yourself"))
        XCTAssertTrue(model.toast?.isError == true)
        XCTAssertEqual(model.lifecycle.phase, .choosing)
        XCTAssertNil(model.flight)
    }

    @MainActor
    private func waitForPreparation(_ model: ShareAction) async throws {
        let deadline = Date().addingTimeInterval(5)
        while model.isBusy {
            guard Date() < deadline else { XCTFail("Attachment preparation did not finish"); throw CancellationError() }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
