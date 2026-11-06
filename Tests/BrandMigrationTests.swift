import XCTest
import Foundation

final class BrandMigrationTests: XCTestCase {
    func testRenamedSettingsAreCopiedOnceWithoutOverwritingCurrentChoices() throws {
        let name = "NotchiMigrationTests.\(UUID().uuidString)", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let old = Data("legacy preferences".utf8), current = Data("current preferences".utf8)
        defaults.set(old, forKey: "notchly.settings.v1")
        XCTAssertEqual(BrandMigration.settingsData(in: defaults), old)
        defaults.set(current, forKey: "notchi.settings.v1")
        XCTAssertEqual(BrandMigration.settingsData(in: defaults), current)
        XCTAssertEqual(defaults.data(forKey: "notchly.settings.v1"), old)
    }
    func testSupportMigrationPreservesOldImportURLsAndExistingNewFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let previous = root.appendingPathComponent("Notchly/Imports", isDirectory: true)
        try FileManager.default.createDirectory(at: previous, withIntermediateDirectories: true)
        let original = previous.appendingPathComponent("sample.txt")
        try Data("source".utf8).write(to: original)
        let target = BrandMigration.supportFolder(in: root)
        XCTAssertEqual(target.lastPathComponent, AppConfig.appName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        let copied = target.appendingPathComponent("Imports/sample.txt")
        XCTAssertEqual(try Data(contentsOf: copied), Data("source".utf8))
        try Data("updated".utf8).write(to: copied)
        _ = BrandMigration.supportFolder(in: root)
        XCTAssertEqual(try Data(contentsOf: copied), Data("updated".utf8))
    }
}
