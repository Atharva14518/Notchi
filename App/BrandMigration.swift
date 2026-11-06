import Foundation

/// Historical names are restricted to migration. Leave the old domain and
/// files intact: existing security-scoped bookmarks must keep resolving.
enum BrandMigration {
    static let previousBundle = "com.notchly.Notchly"
    static let previousKeychain = "com.notchly.links.credentials"
    static func settingsData(in defaults: UserDefaults) -> Data? {
        if let data = defaults.data(forKey: "notchi.settings.v1") { return data }
        let previous = defaults === UserDefaults.standard
            ? defaults.persistentDomain(forName: previousBundle)?["notchly.settings.v1"] as? Data : nil
        let data = defaults.data(forKey: "notchly.settings.v1") ?? previous
        if let data { defaults.set(data, forKey: "notchi.settings.v1") }
        return data
    }
    static func migratePreferences() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "notchi.brandMigration.v1") else { return }
        for (key, value) in defaults.persistentDomain(forName: previousBundle) ?? [:] {
            let updated = key.replacingOccurrences(of: "notchly", with: "notchi")
            if defaults.object(forKey: updated) == nil { defaults.set(value, forKey: updated) }
        }
        defaults.set(true, forKey: "notchi.brandMigration.v1")
    }
    static func supportFolder(in parent: URL) -> URL {
        let target = parent.appendingPathComponent(AppConfig.appName, isDirectory: true)
        let previous = parent.appendingPathComponent("Notchly", isDirectory: true)
        let manager = FileManager.default
        if !manager.fileExists(atPath: target.path), manager.fileExists(atPath: previous.path) {
            // Copy, rather than move, because persisted URLs may point into the
            // old Imports folder. Never erase an existing destination or source.
            let staged = parent.appendingPathComponent(".notchi-migration-\(UUID().uuidString)", isDirectory: true)
            defer { try? manager.removeItem(at: staged) }
            do {
                try manager.copyItem(at: previous, to: staged)
                try manager.moveItem(at: staged, to: target)
            } catch { return manager.fileExists(atPath: target.path) ? target : previous }
        }
        return target
    }
}
