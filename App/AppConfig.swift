import Foundation

enum AppConfig {
    static let appName = "Notchi"
    static var wordmark: String { appName.lowercased() }
}

extension String {
    /// Dynamic labels such as preset names use the same catalog as SwiftUI.
    var localized: String { Bundle.main.localizedString(forKey: self, value: self, table: "Localizable") }
}
