import SwiftUI

@main
struct NotchiApp: App {
    init() { BrandMigration.migratePreferences(); Typography.registerFonts() }
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView().preferredColorScheme(.dark).font(Typography.body)
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appSettings) {
                Button(String(localized: "Show Shelf")) { appDelegate.showShelf() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
        MenuBarExtra {
            Text(AppConfig.appName)
            Button(String(localized: "Show Shelf")) { appDelegate.showShelf() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            SettingsLink { Text(String(localized: "Settings…")) }.keyboardShortcut(",")
            Button(String(localized: "Replay setup")) { appDelegate.replayOnboarding() }
            Divider()
            Button(String(localized: "Quit \(AppConfig.appName)")) { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(nsImage: BrandImages.menuBar).accessibilityLabel(AppConfig.appName)
        }
        .menuBarExtraStyle(.menu)
    }
}
