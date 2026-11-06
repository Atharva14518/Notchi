import XCTest
import AppKit

final class SettingsTests: XCTestCase {
    private var temporary: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent("NotchiSettingsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        suite = "NotchiSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: temporary)
    }
    private func file(_ name: String) throws -> URL {
        let url = temporary.appendingPathComponent(name)
        try Data("keep original bytes".utf8).write(to: url); return url
    }
    @MainActor
    func testFirstRunAndSettingsSurviveRelaunch() {
        let settings = SettingsStore(defaults: defaults)
        XCTAssertFalse(settings.value.onboardingComplete)
        settings.value.onboardingComplete = true
        settings.value.hoverEnabled = false
        settings.value.panelSize = .roomy
        settings.value.hoverSensitivity = .relaxed
        settings.value.displayID = 123
        settings.value.autoClearDays = 14
        settings.value.compression = QualityPreset.tiny.rawValue
        settings.value.outputFormat = ImageFormat.jpeg.rawValue
        settings.value.originals = .replace
        settings.value.shortcut = GlobalShortcut(keyCode: 49, modifiers: 256 | 2048)
        let restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.value, settings.value)
        XCTAssertEqual(restored.compressionPreset, .tiny)
        XCTAssertEqual(restored.imageFormat, .jpeg)
    }
    @MainActor
    func testPersistenceOptOutClearsReferencesButKeepsCurrentCardsAndFiles() throws {
        let settings = SettingsStore(defaults: defaults)
        let persistence = MemoryShelfPersistence()
        let url = try file("keep.txt")
        let store = ShelfStore(persistence: persistence, settings: settings)
        defer { store.shutdown() }
        store.add([url]); XCTAssertEqual(persistence.records.count, 1)
        settings.value.keepShelf = false
        XCTAssertTrue(persistence.records.isEmpty)
        XCTAssertEqual(store.files.count, 1)
        let relaunched = ShelfStore(persistence: persistence, settings: settings)
        defer { relaunched.shutdown() }
        XCTAssertTrue(relaunched.files.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        settings.value.keepShelf = true
        // Multiple stores are only used for the relaunch check; stop its subscription.
        relaunched.shutdown()
        store.add([try file("next.txt")])
        XCTAssertEqual(persistence.records.count, 2)
    }
    @MainActor
    func testExpirationPrunesOnlineAndOfflineRecordsWithoutDeletingFiles() throws {
        let persistence = MemoryShelfPersistence()
        let kept = try file("keep.txt"), offline = try file("offline.txt")
        let seed = ShelfStore(persistence: persistence)
        seed.add([kept, offline]); seed.shutdown()
        for index in persistence.records.indices { persistence.records[index].addedAt = Date().addingTimeInterval(-10 * 86400) }
        try FileManager.default.removeItem(at: offline)
        let settings = SettingsStore(defaults: defaults)
        settings.value.autoClearDays = 7
        let restored = ShelfStore(persistence: persistence, settings: settings)
        defer { restored.shutdown() }
        XCTAssertTrue(restored.files.isEmpty)
        XCTAssertTrue(persistence.records.isEmpty)
        XCTAssertEqual(try String(contentsOf: kept, encoding: .utf8), "keep original bytes")
        restored.add([kept])
        restored.expire(olderThanDays: 7, now: Date().addingTimeInterval(8 * 86400))
        XCTAssertTrue(restored.files.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path))
    }
    @MainActor
    func testReplacePolicyRemovesOnlyCardAfterOutputsAreAccepted() throws {
        let source = try file("source.txt"), result = try file("result.txt")
        let store = ShelfStore(persistence: MemoryShelfPersistence())
        defer { store.shutdown() }
        store.add([source])
        let original = try XCTUnwrap(store.files.first)
        store.addActionResult(ActionResult(outputs: [temporary.appendingPathComponent("missing.txt")]), source: original, policy: .replace)
        XCTAssertTrue(store.files.contains { $0.id == original.id })
        store.addActionResult(ActionResult(outputs: [result]), source: original, policy: .replace)
        XCTAssertEqual(store.files.map(\.url), [result])
        XCTAssertTrue(store.files[0].isNew)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "keep original bytes")
    }
    @MainActor
    func testPermissionRefreshDetectsGrantAndRevocationWithoutPrompting() {
        var trusted = false
        let manager = PermissionManager(check: { trusted })
        XCTAssertFalse(manager.isTrusted)
        trusted = true; manager.refresh(); XCTAssertTrue(manager.isTrusted)
        trusted = false; manager.refresh(); XCTAssertFalse(manager.isTrusted)
        XCTAssertFalse(manager.hasRequested)
        manager.stop()
    }
    @MainActor
    func testPermissionRefreshesWhenReturningFromSettingsAndStopsObservers() {
        var trusted = false
        let center = NotificationCenter()
        let manager = PermissionManager(check: { trusted }, notificationCenter: center)
        manager.start()
        trusted = true
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertTrue(manager.isTrusted)
        trusted = false
        center.post(name: NSWindow.didBecomeKeyNotification, object: nil)
        XCTAssertFalse(manager.isTrusted)
        manager.stop()
        trusted = true
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertFalse(manager.isTrusted)
        XCTAssertTrue(manager.refresh()) // Explicit Check again works even after polling stops.
    }
    @MainActor
    func testPermissionPollDetectsGrantAndRevocationWithoutAppActivation() async throws {
        var trusted = false
        let manager = PermissionManager(check: { trusted }, notificationCenter: NotificationCenter())
        manager.start()
        defer { manager.stop() }
        trusted = true
        try await Task.sleep(for: .milliseconds(1250))
        XCTAssertTrue(manager.isTrusted)
        trusted = false
        try await Task.sleep(for: .milliseconds(1250))
        XCTAssertFalse(manager.isTrusted)
    }
    func testSensitivityChangesDebounceAndPanelWidthPreservesAnchor() {
        var hover = HoverIntent()
        XCTAssertNil(hover.update(inside: true, expanded: false, heldOpen: false, now: 0, debounce: HoverSensitivity.precise.delay))
        XCTAssertNil(hover.update(inside: true, expanded: false, heldOpen: false, now: 0.1, debounce: HoverSensitivity.precise.delay))
        XCTAssertEqual(hover.update(inside: true, expanded: false, heldOpen: false, now: 0.19, debounce: HoverSensitivity.precise.delay), true)
        var geometry = NotchGeometry(screenFrame: CGRect(x: -1440, y: 0, width: 1440, height: 900), topInset: 0)
        geometry.preferredWidth = PanelSize.roomy.width
        XCTAssertEqual(geometry.expandedSize.width, 500)
        XCTAssertEqual(geometry.frame(expanded: true).midX, -720)
    }
    func testShortcutRecorderValidatesModifiersAndUsesCarbonFlags() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .option, .shift], timestamp: 0, windowNumber: 0, context: nil, characters: "n", charactersIgnoringModifiers: "n", isARepeat: false, keyCode: 45))
        XCTAssertEqual(GlobalShortcut.from(event), GlobalShortcut(keyCode: 45, modifiers: 256 | 2048 | 512))
        XCTAssertEqual(GlobalShortcut.standard.label, "⌃⌥N")
        let plain = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "n", charactersIgnoringModifiers: "n", isARepeat: false, keyCode: 45))
        XCTAssertNil(GlobalShortcut.from(plain))
    }
    @MainActor
    func testRetentionDoesNotOverwriteAnUnreadableSavedIndex() {
        final class UnreadableIndex: ShelfPersistence {
            var writes = 0
            func read() throws -> [ShelfBookmark] { throw CocoaError(.fileReadCorruptFile) }
            func write(_ records: [ShelfBookmark]) throws { writes += 1 }
        }
        let settings = SettingsStore(defaults: defaults)
        let persistence = UnreadableIndex()
        let store = ShelfStore(persistence: persistence, settings: settings)
        defer { store.shutdown() }
        store.expire(olderThanDays: 1)
        settings.value.autoClearDays = 7
        XCTAssertEqual(persistence.writes, 0)
        XCTAssertTrue(store.hasError)
        settings.value.keepShelf = false // Explicit opt-out may clear the saved reference index.
        XCTAssertEqual(persistence.writes, 1)
    }
    @MainActor
    func testDefaultSaveFolderRestoresFromBookmark() {
        let settings = SettingsStore(defaults: defaults)
        settings.setSaveLocation(temporary)
        let restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.saveLocation?.standardizedFileURL, temporary.standardizedFileURL)
        restored.stop(); settings.stop()
    }
    @MainActor
    func testOlderSettingsSchemaPreservesChoicesWhileAddingNewDefaults() throws {
        let old = Data(#"{"onboardingComplete":true,"keepShelf":false,"autoClearDays":13}"#.utf8)
        defaults.set(old, forKey: "notchi.settings.v1")
        let settings = SettingsStore(defaults: defaults)
        XCTAssertTrue(settings.value.onboardingComplete)
        XCTAssertFalse(settings.value.keepShelf)
        XCTAssertEqual(settings.value.autoClearDays, 13)
        XCTAssertEqual(settings.value.shortcut, .standard)
        XCTAssertEqual(settings.value.panelSize, .standard)
    }
    func testUnknownSettingsFieldsDoNotResetPrivacyChoicesOrClearedShortcut() throws {
        let data = Data(#"{"onboardingComplete":true,"keepShelf":false,"shortcut":null,"panelSize":"future-size","hoverSensitivity":"future-sensitivity","autoClearDays":99999}"#.utf8)
        let settings = try JSONDecoder().decode(SettingsSnapshot.self, from: data)
        XCTAssertTrue(settings.onboardingComplete)
        XCTAssertFalse(settings.keepShelf)
        XCTAssertTrue(settings.hoverEnabled) // Older builds did not have this preference.
        XCTAssertNil(settings.shortcut)
        XCTAssertEqual(settings.panelSize, .standard)
        XCTAssertEqual(settings.hoverSensitivity, .balanced)
        XCTAssertEqual(settings.autoClearDays, 3650)
    }
    @MainActor
    func testCustomRetentionIntervalClampsAndSurvivesRelaunch() {
        let settings = SettingsStore(defaults: defaults)
        settings.setAutoClearDays(13)
        XCTAssertEqual(SettingsStore(defaults: defaults).value.autoClearDays, 13)
        settings.setAutoClearDays(-5)
        XCTAssertEqual(settings.value.autoClearDays, 0)
        settings.setAutoClearDays(99999)
        XCTAssertEqual(settings.value.autoClearDays, 3650)
    }

    @MainActor
    func testPermissionRevocationDoesNotDisableHoverOrChangeUserPreference() {
        let settings = SettingsStore(defaults: defaults)
        var trusted = true
        let permission = PermissionManager(check: { trusted })
        trusted = false
        XCTAssertFalse(permission.refresh())
        XCTAssertTrue(settings.value.hoverEnabled)
        settings.value.hoverEnabled = false
        trusted = true
        XCTAssertTrue(permission.refresh())
        XCTAssertFalse(settings.value.hoverEnabled)
        XCTAssertFalse(SettingsStore(defaults: defaults).value.hoverEnabled)
    }

    @MainActor
    func testPermissionHelpRefreshesBeforeOpeningGuideAndNeverPrompts() {
        let center = NotificationCenter()
        var trusted = false
        let permission = PermissionManager(check: { trusted }, notificationCenter: center)
        var guideOpened = false
        let observer = center.addObserver(forName: .notchiPermissionHelp, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { guideOpened = permission.isTrusted }
        }
        defer { center.removeObserver(observer) }
        trusted = true
        permission.showHelp()
        XCTAssertTrue(guideOpened)
        XCTAssertFalse(permission.hasRequested)
    }

    func testArrowRecorderAcceptsMacOSFunctionFlagWithoutRegisteringFnLetters() throws {
        let arrow = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.control, .option, .function, .numericPad], timestamp: 0, windowNumber: 0,
            context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 123))
        XCTAssertEqual(GlobalShortcut.from(arrow), GlobalShortcut(keyCode: 123, modifiers: 4096 | 2048))
        let fnLetter = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.control, .function], timestamp: 0, windowNumber: 0,
            context: nil, characters: "n", charactersIgnoringModifiers: "n", isARepeat: false, keyCode: 45))
        XCTAssertNil(GlobalShortcut.from(fnLetter))
    }

}
