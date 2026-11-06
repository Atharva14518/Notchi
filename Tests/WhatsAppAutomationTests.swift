import XCTest
import AppKit

private actor FakeWhatsAppUI: WhatsAppUIDriving {
    var calls: [String] = []
    var failAt: String?
    var gate: AsyncStream<Void>?
    init(failAt: String? = nil, gate: AsyncStream<Void>? = nil) { self.failAt = failAt; self.gate = gate }
    private func record(_ value: String) throws {
        calls.append(value)
        if failAt == value { throw WhatsAppAutomationError.changed }
    }
    func validateIdle() throws { try record("validate") }
    func press(_ control: WhatsAppControl) throws { try record(control.rawValue) }
    func chooseFiles(_ urls: [URL]) async throws {
        try record("files")
        if let gate { for await _ in gate { break } }
    }
    func clearPreselectedRecipients() throws { try record("clearRecipients") }
}

final class WhatsAppAutomationTests: XCTestCase {
    func testPreparesAttachmentBeforeOpeningRecipientPickerAndNeverSends() async throws {
        let driver = FakeWhatsAppUI()
        try await WhatsAppAutomation.prepare(files: [URL(fileURLWithPath: "/tmp/sample.pdf")], driver: driver)
        let calls = await driver.calls
        XCTAssertEqual(calls, ["validate", WhatsAppControl.attach.rawValue, WhatsAppControl.document.rawValue,
                               "files", WhatsAppControl.audience.rawValue, "clearRecipients"])
        XCTAssertFalse(calls.contains("ForwardPickerView_ForwardButton"))
        XCTAssertFalse(calls.contains("WAMultiSendBottomBarView_SendButton"))
    }
    func testExistingDialogFailureStopsBeforeChangingWhatsApp() async throws {
        let driver = FakeWhatsAppUI(failAt: "validate")
        do { try await WhatsAppAutomation.prepare(files: [], driver: driver); XCTFail("Must stop") } catch { }
        let calls = await driver.calls; XCTAssertEqual(calls, ["validate"])
    }
    func testUnconfirmedFileSelectionNeverOpensRecipientPicker() async throws {
        let driver = FakeWhatsAppUI(failAt: "files")
        do { try await WhatsAppAutomation.prepare(files: [], driver: driver); XCTFail("Must stop") } catch { }
        let calls = await driver.calls
        XCTAssertEqual(calls.last, "files")
        XCTAssertFalse(calls.contains(WhatsAppControl.audience.rawValue))
    }
    func testCancelledLateFileSelectionCannotContinueToRecipients() async throws {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        defer { continuation.finish() }
        let driver = FakeWhatsAppUI(gate: stream)
        let task = Task { try await WhatsAppAutomation.prepare(files: [], driver: driver) }
        for _ in 0..<100 {
            if await driver.calls.contains("files") { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        task.cancel(); continuation.yield(())
        do { try await task.value; XCTFail("Must cancel") } catch { XCTAssertTrue(error is CancellationError) }
        let calls = await driver.calls
        XCTAssertFalse(calls.contains(WhatsAppControl.audience.rawValue))
    }

    @MainActor
    func testPermissionGateDoesNotLaunchWhatsAppOrRunAutomation() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("sample.pdf"); try Data("test".utf8).write(to: source)
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        var requests = 0
        let model = ShareAction(catalog: { _ in [] }, attachments: SendAttachmentPreparer(root: folder.appendingPathComponent("prepared")), clipboard: board,
            launchApp: { _ in XCTFail("Must not launch before permission") },
            recipientPicker: { _, _ in XCTFail("Must not automate before permission") },
            automationPermission: { false }, requestAutomationPermission: { requests += 1 })
        defer { model.stop() }
        model.show(items: [ShelfItem(url: source)])
        model.prepareHandoff(InstalledSendApp(id: "net.whatsapp.WhatsApp", title: "WhatsApp", url: folder))
        try await settle(model)
        XCTAssertEqual(requests, 1)
        XCTAssertFalse(model.isExternalHandoffActive)
        XCTAssertNotNil(model.handoff)
        XCTAssertTrue(model.toast?.text.contains("Accessibility") == true)
        XCTAssertNil(model.flight)
    }

    @MainActor
    func testRepeatChooseRecipientsReusesCopiesAndYieldsOverlayUntilReady() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("sample.pdf"); try Data("test".utf8).write(to: source)
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        var launched = 0, pickers = 0
        var model: ShareAction!
        model = ShareAction(catalog: { _ in [] }, attachments: SendAttachmentPreparer(root: folder.appendingPathComponent("prepared")), clipboard: board,
            launchApp: { _ in launched += 1; XCTAssertTrue(model.isExternalHandoffActive) },
            recipientPicker: { _, urls in
                pickers += 1; XCTAssertTrue(model.isExternalHandoffActive)
                XCTAssertTrue(FileManager.default.fileExists(atPath: urls[0].path))
            }, automationPermission: { true })
        defer { model.stop(); model = nil }
        model.show(items: [ShelfItem(url: source)])
        model.prepareHandoff(InstalledSendApp(id: "net.whatsapp.WhatsApp", title: "WhatsApp", url: folder))
        try await settle(model)
        let first = model.handoff?.files.urls
        model.copyAndOpenHandoff(); try await settle(model)
        XCTAssertEqual(launched, 2); XCTAssertEqual(pickers, 2)
        XCTAssertEqual(model.handoff?.files.urls, first)
        XCTAssertFalse(model.isExternalHandoffActive)
        XCTAssertTrue(model.status.contains("Choose recipients"))
        XCTAssertNil(model.flight); XCTAssertNotEqual(model.toast?.text, "Sent!")
    }
    @MainActor
    private func settle(_ model: ShareAction) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.isBusy {
            guard ContinuousClock.now < deadline else { XCTFail("Flow did not finish"); throw CancellationError() }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
