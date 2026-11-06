import AppKit
import ServiceManagement

@MainActor
final class LoginItemManager: ObservableObject {
    static let shared = LoginItemManager()
    @Published private(set) var enabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var message: String?
    init() { refresh() }
    func refresh() {
        let status = SMAppService.mainApp.status
        enabled = status == .enabled || status == .requiresApproval
        requiresApproval = status == .requiresApproval
    }
    func setEnabled(_ desired: Bool) {
        do {
            if desired { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            message = nil
        } catch { message = String(localized: "Couldn’t change launch at login. \(error.localizedDescription)") }
        refresh() // Never show success solely from a stored preference.
    }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
