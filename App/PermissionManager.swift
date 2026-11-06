import AppKit
import ApplicationServices
import Combine

@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    @Published private(set) var isTrusted: Bool
    @Published private(set) var hasRequested = false
    private var timer: Timer?
    private var subscriptions: Set<AnyCancellable> = []
    private let check: () -> Bool
    private let notificationCenter: NotificationCenter
    var applicationURL: URL { Bundle.main.bundleURL }

    init(check: @escaping () -> Bool = { PermissionManager.currentTrust() },
         notificationCenter: NotificationCenter = .default) {
        self.check = check
        self.notificationCenter = notificationCenter
        isTrusted = check()
    }
    nonisolated static func currentTrust() -> Bool {
        // Always ask the public, non-prompting API again. Do not infer trust from
        // a System Settings toggle, cached preference, or another process's AX check.
        AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
        ] as CFDictionary)
    }
    func start() {
        stop(); refresh()
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didUnhideNotification,
                     NSWindow.didBecomeKeyNotification] {
            notificationCenter.publisher(for: name).sink { [weak self] _ in
                MainActor.assumeIsolated { _ = self?.refresh() }
            }.store(in: &subscriptions)
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    @discardableResult
    func refresh() -> Bool {
        let trusted = check()
        if trusted != isTrusted { isTrusted = trusted }
        return trusted
    }
    func request() {
        hasRequested = true
        // Mouse-only NSEvent monitoring does not require AX trust. This is an
        // explicit opt-in for WhatsApp UI automation, which prepares attachments
        // and opens its recipient picker. Hover remains available without it.
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        refresh()
    }
    func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
    func revealApplication() { NSWorkspace.shared.activateFileViewerSelecting([applicationURL]) }
    func copyApplicationPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(applicationURL.path, forType: .string)
    }
    func showHelp() {
        refresh()
        notificationCenter.post(name: .notchiPermissionHelp, object: nil)
    }
    func stop() { timer?.invalidate(); timer = nil; subscriptions.removeAll() }
}

extension Notification.Name {
    static let notchiPermissionHelp = Notification.Name("Notchi.permissionHelp")
}
