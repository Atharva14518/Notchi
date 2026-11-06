import AppKit
import SwiftUI

struct ShortcutsSettingsView: View {
    @ObservedObject var settings = SettingsStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsFormRow(String(localized: "Shortcuts app")) {
                Button(String(localized: "Open Shortcuts")) { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app")) }
                    .buttonStyle(NotchiButtonStyle(.primary))
            }
            suggestion(String(localized: "Open shelf"), symbol: "tray", phrase: String(localized: "Open my shelf in \(AppConfig.appName)"))
            suggestion(String(localized: "Compress latest"), symbol: "arrow.down.right.and.arrow.up.left", phrase: String(localized: "Compress my latest file with \(AppConfig.appName)"))
            suggestion(String(localized: "Read latest"), symbol: "text.viewfinder", phrase: String(localized: "Read my latest file with \(AppConfig.appName)"))
            suggestion(String(localized: "Scan"), symbol: "doc.viewfinder", phrase: String(localized: "Scan with \(AppConfig.appName)"))
            SettingsHoverRow { NotchiToggle(String(localized: "Recent suggestions"), isOn: $settings.value.suggestRecentActions) }
            SettingsFormRow(String(localized: "Help")) {
                Button(String(localized: "Testing guide")) {
                    if let url = Bundle.main.url(forResource: "SHORTCUTS", withExtension: "md") { NSWorkspace.shared.open(url) }
                }
            }
        }
    }
    private func suggestion(_ title: String, symbol: String, phrase: String) -> some View {
        SettingsHoverRow {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(Color.secondaryText).frame(width: 20)
                Text(title).font(Typography.settingsLabel)
                Spacer()
                Image(systemName: "waveform").foregroundStyle(Color.secondaryText)
            }.help(phrase).accessibilityElement(children: .ignore).accessibilityLabel(phrase)
        }
    }
}
