import SwiftUI

struct AcknowledgementsView: View {
    @State private var expanded = false
    @State private var notices = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsFormRow(String(localized: "Open source")) {
                Button(expanded ? String(localized: "Hide licenses") : String(localized: "Show licenses")) { withAnimation(Animations.settingsFade) { expanded.toggle() } }
            }
            Text(String(localized: "FFmpeg · LAME · libvpx · Opus · Poppins")).font(Typography.settingsLabel).foregroundStyle(Color.secondaryText)
            if expanded {
                Text(notices).font(Typography.settingsLabel).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(String(localized: "Sources")) { reveal("FFmpegSources") }
                    Button(String(localized: "Licenses")) { reveal("FFmpegLicenses") }
                }
            }
        }.task {
            if let url = Bundle.main.url(forResource: "THIRD_PARTY_LICENSES", withExtension: "md"), let text = try? String(contentsOf: url, encoding: .utf8) { notices = text }
            else { notices = String(localized: "Credits unavailable") }
        }
    }
    private func reveal(_ folder: String) {
        if let url = Bundle.main.resourceURL?.appendingPathComponent(folder) { NSWorkspace.shared.open(url) }
    }
}
