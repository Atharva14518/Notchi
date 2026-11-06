import SwiftUI

/// Detailed guidance belongs in onboarding; panel controls link here instead of
/// repeatedly asking to enable a switch which may already be on.
struct PermissionControls: View {
    @ObservedObject var permission: PermissionManager
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(permission.isTrusted ? String(localized: "Accessibility confirmed for this app") : String(localized: "Accessibility not yet confirmed"),
                  systemImage: permission.isTrusted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(Typography.heading).foregroundStyle(permission.isTrusted ? Color.mint : Color.coral)
            Text(String(localized: "Hover and drag-and-drop work without Accessibility. WhatsApp needs it so \(AppConfig.appName) can attach your files and open the recipient picker. You choose the contacts and press Send yourself."))
            if !permission.isTrusted {
                HStack(spacing: 10) {
                    Button(String(localized: "Open Settings")) { permission.request(); permission.openSettings() }
                        .buttonStyle(NotchiButtonStyle(.primary))
                    Button(String(localized: "Check now")) { permission.refresh() }
                        .buttonStyle(NotchiButtonStyle(.secondary))
                }
                guideStep("1", title: String(localized: "Open Accessibility settings"),
                          detail: String(localized: "Click Open Settings. In System Settings, go to Privacy & Security → Accessibility and unlock with your password or Touch ID if asked."))
                guideStep("2", title: String(localized: "Add this exact app"),
                          detail: String(localized: "Click + and select the app shown below. You can use Copy app path, then press ⌘⇧G in the file chooser and paste it. Turn on the switch beside the app."))
                guideStep("3", title: String(localized: "Return here to verify"),
                          detail: String(localized: "\(AppConfig.appName) checks every second and when you return. Once macOS confirms access for this process, this status turns green and the tour continues automatically."))
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "This running app")).font(Typography.button)
                Text(permission.applicationURL.path).font(Typography.mono).foregroundStyle(Color.acid)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(String(localized: "Show app")) { permission.revealApplication() }
                    Button(copied ? String(localized: "Copied") : String(localized: "Copy app path")) {
                        permission.copyApplicationPath(); copied = true
                    }
                }.buttonStyle(NotchiButtonStyle(.secondary))
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.shelfSurface, in: RoundedRectangle(cornerRadius: 18))
            if !permission.isTrusted {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "Already enabled, but still not working?")).font(Typography.heading)
                    Text(String(localized: "A switch for an older app copy does not necessarily approve this build. Quit other copies. Remove the old entry with −, click +, and add the exact app above again. If macOS asks you to quit and reopen, finish or cancel any running task, quit from \(AppConfig.appName)’s menu bar, then reopen this same app."))
                    Text(String(localized: "Local development rebuilds can change the app’s signing identity and invalidate an earlier approval. A stable signing certificate is needed for consistent approvals across updates. \(AppConfig.appName) cannot change macOS permission decisions itself."))
                        .foregroundStyle(Color.secondaryText)
                }
                Text(String(localized: "You can continue without this permission and return from Settings → Permission help. WhatsApp automation stays unavailable until access is confirmed."))
                    .foregroundStyle(Color.secondaryText)
            } else {
                Text(String(localized: "You’re ready. If access is revoked later, hover keeps working and WhatsApp will ask you to return here."))
                Button(String(localized: "Open Settings")) { permission.openSettings() }.buttonStyle(NotchiButtonStyle(.secondary))
            }
        }.font(Typography.body).fixedSize(horizontal: false, vertical: true)
            .onAppear { permission.refresh() }
    }
    private func guideStep(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(Typography.button).foregroundStyle(Color.ink)
                .frame(width: 28, height: 28).background(Color.acid, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(Typography.button)
                Text(detail).foregroundStyle(Color.secondaryText)
            }
        }
    }
}
