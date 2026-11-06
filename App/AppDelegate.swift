import AppKit
import SwiftUI
import AppIntents

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let showShelfNotification = Notification.Name("com.notchi.Notchi.showShelf")
    private var panelController: NotchPanelController?
    private var onboarding: OnboardingController?
    private let runtime = IntentRuntime.shared
    private var store: ShelfStore { runtime.store }
    private var actions: ActionCoordinator { runtime.actions }
    private let bootstrapHover = HoverDetector()
    private var didLaunch = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Debug and Release live at different paths, so Launch Services alone
        // does not cover every launch (notably direct launches from Xcode).
        if let identifier = Bundle.main.bundleIdentifier {
            let others = (NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                + NSRunningApplication.runningApplications(withBundleIdentifier: BrandMigration.previousBundle))
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
            if let existing = others.first {
                DistributedNotificationCenter.default().postNotificationName(
                    Self.showShelfNotification, object: identifier, userInfo: nil, deliverImmediately: true)
                existing.activate(options: [])
                NSApp.terminate(nil)
                return
            }
            DistributedNotificationCenter.default().addObserver(
                self, selector: #selector(showShelf), name: Self.showShelfNotification, object: identifier)
        }
        PermissionManager.shared.start()
        LinkCoordinator.shared.start()
        // App Intents can cold-launch this agent in the background. Defer every
        // window until activation, a hover/drag, or an explicit navigation intent.
        didLaunch = true
        GlobalHotkeyManager.shared.start(settings: SettingsStore.shared) { [weak self] in self?.showShelf() }
        runtime.openShelfHandler = { [weak self] in self?.showShelf() }
        runtime.openScanHandler = { [weak self] in self?.ensurePanel(); self?.panelController?.showScanner() }
        runtime.canChangeShelf = { [weak self] in
            guard let self else { return true }
            return !self.actions.isPresentingDialog && !self.store.isPresentingDialog && self.panelController?.hasActiveWorkspace != true
        }
        if panelController == nil {
            bootstrapHover.start { [weak self] point, _, systemDrag in
                guard let self, SettingsStore.shared.value.hoverEnabled,
                      let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return }
                if systemDrag || NotchGeometry(screen: screen).hotZone.contains(point) { self.ensurePanel() }
            }
        }
        NotchiShortcuts.updateAppShortcutParameters()
        NotificationCenter.default.addObserver(self, selector: #selector(replayOnboarding), name: .notchiReplayOnboarding, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showPermissionHelp), name: .notchiPermissionHelp, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showLinks), name: .notchiShowLinks, object: nil)
        let replayOnboarding = ProcessInfo.processInfo.arguments.contains("--onboarding")
        if replayOnboarding {
            ensurePanel()
            DispatchQueue.main.async { [weak self] in self?.onboarding?.show(force: true) }
        } else if NSApp.isActive { activateInterface() }
        if ProcessInfo.processInfo.arguments.contains("--show-shelf") { showShelf() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showShelf()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard actions.isBusy || panelController?.hasActiveSend == true || panelController?.hasActiveScan == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = String(localized: "A file operation is still running")
        alert.informativeText = String(localized: "Finish or cancel first.")
        alert.addButton(withTitle: String(localized: "Keep Working"))
        alert.runModal()
        return .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        bootstrapHover.stop()
        GlobalHotkeyManager.shared.stop()
        PermissionManager.shared.stop()
        onboarding?.close()
        SettingsStore.shared.stop()
        panelController?.stop()
        store.shutdown()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if didLaunch { activateInterface() }
    }
    private func activateInterface() {
        ensurePanel()
        onboarding?.show()
    }
    private func ensurePanel() {
        guard panelController == nil else { return }
        bootstrapHover.stop()
        panelController = NotchPanelController(store: store, actions: actions, settings: .shared)
        onboarding = OnboardingController(settings: .shared)
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "notchi" && url.host == "auth" {
            Task { await LinkAuthStore.shared.handle(url) }
        }
    }
    @objc func showLinks() { ensurePanel(); panelController?.showLinks() }
    @objc func showShelf() { ensurePanel(); panelController?.showShelf() }
    @objc func replayOnboarding() { ensurePanel(); onboarding?.show(force: true) }
    @objc func showPermissionHelp() { ensurePanel(); onboarding?.show(force: true, initialStep: .permissions) }
}
