import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @ObservedObject var settings = SettingsStore.shared
    @ObservedObject var permission = PermissionManager.shared
    @ObservedObject var login = LoginItemManager.shared
    @ObservedObject var hotkey = GlobalHotkeyManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab = Tab.general
    @State private var screens = NSScreen.screens
    @State private var updates = false
    enum Tab: String, CaseIterable {
        case general = "General", shelf = "Shelf", actions = "Actions", shortcuts = "Shortcuts", about = "About"
        var symbol: String {
            switch self { case .general: return "gearshape"; case .shelf: return "tray"; case .actions: return "wand.and.stars"; case .shortcuts: return "keyboard"; case .about: return "info.circle" }
        }
        var height: CGFloat {
            switch self { case .general: return 460; case .shelf: return 480; case .actions: return 280; case .shortcuts: return 480; case .about: return 430 }
        }
    }
    var body: some View {
        TabView(selection: $tab) {
            ForEach(Tab.allCases, id: \.self) { page in
                Form {
                    switch page {
                    case .general: general
                    case .shelf: shelf
                    case .actions: actions
                    case .shortcuts: shortcuts
                    case .about: about
                    }
                    if let error = settings.error { NotchiAttention(message: error, isError: true) }
                }.formStyle(.grouped).scrollContentBackground(.hidden)
                    .font(Typography.settingsLabel)
                    .transition(.opacity)
                    .tabItem { Label(page.rawValue.localized, systemImage: page.symbol) }.tag(page)
            }
        }.frame(width: 560, height: min(tab.height, (NSScreen.main?.visibleFrame.height ?? 800) - 100))
            .background(Color.ink).foregroundStyle(Color.paper).tint(Color.acid)
            .environment(\.notchiSettingsControl, true)
            .buttonStyle(NotchiButtonStyle(.secondary)).textFieldStyle(NotchiTextFieldStyle())
            .background(NotchiWindowChrome(title: tab.rawValue.localized, tabs: Tab.allCases.map { ($0.rawValue.localized, $0.symbol) }, onSelect: { label in
                if let next = Tab.allCases.first(where: { $0.rawValue.localized == label }) { tab = next }
            }))
            .navigationTitle(tab.rawValue.localized)
            .animation(Animations.settingsFade, value: tab)
            .onChange(of: tab) { _, _ in hotkey.cancelRecording() }
            .task { login.refresh(); permission.refresh() }
            .onDisappear { hotkey.cancelRecording() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.refresh(); permission.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in hotkey.cancelRecording() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in screens = NSScreen.screens }
    }
    private var general: some View {
        Group {
            Section { 
                SettingsHoverRow { LaunchAtLoginControl(login: login) }
                SettingsHoverRow { NotchiToggle(String(localized: "Open on hover"), isOn: $settings.value.hoverEnabled) }
                SettingsFormRow(String(localized: "Sensitivity")) {
                    NotchiPicker(String(localized: "Sensitivity"), selection: $settings.value.hoverSensitivity,
                                 options: HoverSensitivity.allCases.map { NotchiOption($0, $0.rawValue.capitalized) })
                }
                SettingsFormRow(String(localized: "Panel size")) {
                    NotchiPicker(String(localized: "Panel size"), selection: $settings.value.panelSize,
                                 options: PanelSize.allCases.map { NotchiOption($0, $0.rawValue.capitalized) })
                }
                SettingsFormRow(String(localized: "Display")) {
                    NotchiPicker(String(localized: "Display"), selection: $settings.value.displayID, options: displayOptions, segmented: false)
                }
            } header: { sectionTitle("GENERAL") }
            Section {
                SettingsHoverRow {
                    HStack(spacing: 8) {
                        Image(systemName: settings.value.hoverEnabled ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(settings.value.hoverEnabled ? Color.mint : .coral)
                            .help(permission.isTrusted ? String(localized: "WhatsApp access confirmed") : String(localized: "WhatsApp access unconfirmed"))
                        Text(settings.value.hoverEnabled ? String(localized: "Hover on") : String(localized: "Hover off"))
                        Spacer()
                        Button(String(localized: "Open Settings")) { permission.openSettings() }
                            .help(String(localized: "Accessibility for WhatsApp"))
                    }
                }
                // Hover itself requires no AX grant; never claim the toggle is
                // off just because WhatsApp automation permission is missing.
                if !settings.value.hoverEnabled {
                    Text(String(localized: "Hover off. Use the menu bar or shortcut.")).foregroundStyle(Color.secondaryText)
                }
            } header: { sectionTitle("ACCESSIBILITY") }
            Button(String(localized: "Reset to defaults")) { settings.resetGeneral() }
                .buttonStyle(NotchiButtonStyle(.secondary))
        }
    }
    private var displayOptions: [NotchiOption<UInt32?>] {
        var list = [NotchiOption<UInt32?>(nil, String(localized: "Follow cursor")), NotchiOption<UInt32?>(0, String(localized: "Main display"))]
        list += screens.compactMap { screen in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value, id != 0 else { return nil }
            return NotchiOption<UInt32?>(id,screen.localizedName)
        }
        if let id = settings.value.displayID, !list.contains(where: { $0.value == id }) { list.append(NotchiOption(id,String(localized: "Disconnected"))) }
        return list
    }
    private var shelf: some View {
        Group {
            Section {
                SettingsHoverRow { NotchiToggle(String(localized: "Keep files"), isOn: $settings.value.keepShelf) }
                SettingsFormRow(String(localized: "Auto-clear")) {
                    NotchiPicker(String(localized: "Auto-clear"), selection: $settings.value.autoClearDays,
                        options: [NotchiOption(0,String(localized: "Never")),NotchiOption(1,String(localized: "1 day")),NotchiOption(7,String(localized: "7 days")),NotchiOption(30,String(localized: "30 days"))] + (settings.value.autoClearDays > 0 && ![1,7,30].contains(settings.value.autoClearDays) ? [NotchiOption(settings.value.autoClearDays,String(localized: "\(settings.value.autoClearDays) days"))] : []))
                }
                SettingsFormRow(String(localized: "Days")) {
                    TextField(String(localized: "Days"), value: Binding(get: { settings.value.autoClearDays }, set: { settings.setAutoClearDays($0) }), format: .number.grouping(.never))
                        .frame(width: 70).accessibilityLabel(String(localized: "Auto-clear days"))
                }
                SettingsFormRow(String(localized: "Save folder")) {
                    Text(settings.saveLocation?.lastPathComponent ?? String(localized: "Ask each time")).lineLimit(1).truncationMode(.middle)
                    Button(String(localized: "Choose")) { settings.chooseSaveLocation() }
                    Button { settings.setSaveLocation(nil) } label: { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(NotchiButtonStyle(.icon)).accessibilityLabel(String(localized: "Reset folder"))
                }
            } header: { sectionTitle("SHELF") }
            Section { LinkAccountView().font(Typography.settingsLabel) } header: { sectionTitle("LINKS") }
        }
    }
    private var actions: some View {
        Section {
            SettingsFormRow(String(localized: "Compression")) {
                NotchiPicker(String(localized: "Compression"), selection: $settings.value.compression, options: QualityPreset.allCases.map { NotchiOption($0.rawValue,$0.rawValue) })
            }
            SettingsFormRow(String(localized: "Format")) {
                NotchiPicker(String(localized: "Format"), selection: $settings.value.outputFormat, options: ImageFormat.supported.map { NotchiOption($0.rawValue,$0.rawValue) })
            }
            SettingsFormRow(String(localized: "Originals")) {
                NotchiPicker(String(localized: "Originals"), selection: $settings.value.originals, options: OriginalPolicy.allCases.map { NotchiOption($0,$0 == .keep ? String(localized: "Keep both") : String(localized: "Replace card")) })
            }
        } header: { sectionTitle("DEFAULTS") }
    }
    private var shortcuts: some View {
        Group {
            Section { SettingsHoverRow { HotkeyRecorder(settings: settings, manager: hotkey) } } header: { sectionTitle("OPEN SHELF") }
            Section { ShortcutsSettingsView() } header: { sectionTitle("SIRI AND SHORTCUTS") }
        }
    }
    private var about: some View {
        Group {
            Section {
                HStack(spacing: 16) {
                    BlobMascot(gaze: .zero, isActive: true, isTargeted: false).scaleEffect(0.7).frame(width: 58,height: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppConfig.wordmark).font(Typography.wordmark)
                        Text(String(localized: "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))"))
                            .font(Typography.settingsLabel).foregroundStyle(Color.secondaryText)
                    }
                }.frame(minHeight: 60)
                SettingsFormRow(String(localized: "Updates")) {
                    Button(String(localized: "Check for updates")) { updates = true }
                }
                if updates { Text(String(localized: "Updates coming soon")).foregroundStyle(Color.secondaryText) }
                SettingsFormRow(String(localized: "Privacy")) {
                    Button(String(localized: "Privacy")) {
                        if let url = Bundle.main.url(forResource: "PRIVACY", withExtension: "md") { NSWorkspace.shared.open(url) }
                    }
                }
                SettingsFormRow(String(localized: "Tour")) {
                    Button(String(localized: "Replay setup")) { NotificationCenter.default.post(name: .notchiReplayOnboarding, object: nil) }
                }
            } header: { sectionTitle("ABOUT") }
            Section { AcknowledgementsView() } header: { sectionTitle("CREDITS") }
        }
    }
    private func sectionTitle(_ title: String) -> some View {
        Text(title.localized).font(Typography.settingsSection).foregroundStyle(Color.secondaryText)
    }
}

struct SettingsHoverRow<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var hovered = false
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        // macOS grouped Form adds 20pt vertical row insets: 24 + 20 = 44.
        content().frame(maxWidth: .infinity, minHeight: 24)
            .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
            .listRowBackground(Color.shelfSurface)
            .background(Color.paper.opacity(hovered ? (contrast == .increased ? 0.12 : 0.035) : 0), in: RoundedRectangle(cornerRadius: 6))
            .onHover { hovered = $0 }
    }
}
struct SettingsFormRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) { self.title=title; self.content=content }
    var body: some View {
        SettingsHoverRow {
            HStack(spacing: 12) {
                Text(title).font(Typography.settingsLabel).fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                HStack(spacing: 8) { content() }.frame(maxWidth: 310, alignment: .trailing)
            }
        }
    }
}
struct LaunchAtLoginControl: View {
    @ObservedObject var login: LoginItemManager
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NotchiToggle(String(localized: "Launch at login"), isOn: Binding(get: { login.enabled }, set: { login.setEnabled($0) }))
            if login.requiresApproval { Button(String(localized: "Open Login Items")) { login.openSettings() } }
            if let message = login.message { NotchiAttention(message: message, isError: true) }
        }
    }
}
struct HotkeyRecorder: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var manager: GlobalHotkeyManager
    var body: some View {
        HStack(spacing: 10) {
            Text(manager.isRecording ? String(localized: "Press keys…") : settings.value.shortcut?.label ?? String(localized: "No shortcut"))
                .font(Typography.settingsLabel).frame(maxWidth: .infinity, alignment: .leading)
            Button(manager.isRecording ? String(localized: "Cancel") : String(localized: "Record")) {
                if manager.isRecording { manager.cancelRecording() } else { manager.beginRecording() }
            }.buttonStyle(NotchiButtonStyle(.secondary))
            Button { manager.cancelRecording(); settings.value.shortcut = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(NotchiButtonStyle(.icon)).help(String(localized: "Clear shortcut")).accessibilityLabel(String(localized: "Clear shortcut"))
            if let error = manager.error { NotchiAttention(message: error, isError: true) }
        }.onDisappear { manager.cancelRecording() }
    }
}
extension Notification.Name { static let notchiReplayOnboarding = Notification.Name("Notchi.replayOnboarding") }
