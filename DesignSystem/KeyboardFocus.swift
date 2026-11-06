import AppKit
import SwiftUI

/// Input modality is local to this process. No global monitor or permission.
@MainActor
final class KeyboardFocus: ObservableObject {
    static let shared = KeyboardFocus()
    @Published private(set) var navigating = false
    private var monitor: Any?
    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            if event.type == .keyDown {
                if event.keyCode == 48 { self?.navigating = true }
            } else { self?.navigating = false }
            return event
        }
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}

private struct SettingsControlKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var notchiSettingsControl: Bool {
        get { self[SettingsControlKey.self] }
        set { self[SettingsControlKey.self] = newValue }
    }
}
