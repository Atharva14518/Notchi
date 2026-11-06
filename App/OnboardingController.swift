import AppKit
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome, permissions, shelf, actions, scanning, sharing, setup
    var title: String {
        switch self {
        case .welcome: return String(localized: "Meet your new shelf")
        case .permissions: return String(localized: "Connect WhatsApp safely")
        case .shelf: return String(localized: "Drop it. Keep it handy.")
        case .actions: return String(localized: "Make files fit")
        case .scanning: return String(localized: "Scan, read, create")
        case .sharing: return String(localized: "Send it your way")
        case .setup: return String(localized: "Make it yours")
        }
    }
}

@MainActor
final class OnboardingController {
    private var window: NSWindow?
    private let settings: SettingsStore
    init(settings: SettingsStore) { self.settings = settings }
    func show(force: Bool = false, initialStep: OnboardingStep = .welcome) {
        guard force || !settings.value.onboardingComplete else { return }
        if let window, window.isVisible {
            // Recreate the content to navigate directly to permission help.
            if force { window.contentView = hostingView(step: initialStep, height: window.frame.height) }
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        let height = min(740, max(520, (NSScreen.main?.visibleFrame.height ?? 820) - 64))
        let window = OnboardingWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: height),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = AppConfig.appName
        window.isOpaque = false; window.backgroundColor = .clear
        window.hasShadow = true; window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.contentView = hostingView(step: initialStep, height: height)
        window.center(); self.window = window
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    private func hostingView(step: OnboardingStep, height: CGFloat) -> NSView {
        NSHostingView(rootView: OnboardingView(settings: settings, initialStep: step, height: height) { [weak self] in
            self?.settings.value.onboardingComplete = true
            self?.close()
        }.preferredColorScheme(.dark))
    }
    func close() { window?.close(); window = nil }
}
private final class OnboardingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct OnboardingView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permission = PermissionManager.shared
    @ObservedObject var login = LoginItemManager.shared
    @ObservedObject var hotkey = GlobalHotkeyManager.shared
    let height: CGFloat
    let finish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: OnboardingStep
    @State private var wave = 0
    @State private var happy = 0
    @State private var entered = false
    @State private var advanceAfterGrant = false
    init(settings: SettingsStore, initialStep: OnboardingStep = .welcome, height: CGFloat = 740, finish: @escaping () -> Void) {
        self.settings = settings; self.height = height; self.finish = finish
        _step = State(initialValue: initialStep)
    }
    private var transitionAnimation: Animation { reduceMotion ? Animations.fade : Animations.bouncy }
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(AppConfig.appName).font(Typography.heading).foregroundStyle(Color.acid)
                Spacer()
                Text(String(localized: "\(step.rawValue + 1) of \(OnboardingStep.allCases.count)"))
                    .font(Typography.mono).foregroundStyle(Color.secondaryText)
                Button(String(localized: "Skip tour")) { hotkey.cancelRecording(); finish() }.buttonStyle(NotchiButtonStyle(.secondary))
            }
            HStack(spacing: 7) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { chapter in
                    Button { move(to: chapter) } label: {
                        Capsule().fill(chapter == step ? Color.acid : Color.shelfBorder).frame(height: 6).padding(.vertical, 7)
                    }.buttonStyle(NotchiSurfaceButtonStyle()).help(chapter.title).accessibilityLabel(chapter.title)
                }
            }
            HStack(spacing: 20) {
                Text(step.title).font(Typography.title).tracking(-0.6).fixedSize(horizontal: false, vertical: true)
                Spacer()
                BlobMascot(gaze: .zero, isActive: true, isTargeted: false, happyToken: happy, waveToken: wave)
                    .scaleEffect(reduceMotion ? 1 : (entered ? 1.05 : 0.75)).opacity(entered ? 1 : 0)
                    .frame(width: 90, height: 70)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Color.clear.frame(height: 0).id("chapterTop")
                        chapterContent
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).padding(.bottom, 12)
                }.scrollIndicators(.visible)
                    .onChange(of: step) { _, _ in proxy.scrollTo("chapterTop", anchor: .top) }
            }
            HStack {
                if step != .welcome {
                    Button(String(localized: "Back")) { move(to: OnboardingStep(rawValue: step.rawValue - 1)!) }
                        .buttonStyle(NotchiButtonStyle(.secondary))
                }
                Spacer()
                PillButton(title: step == .setup ? String(localized: "Let’s go") : String(localized: "Continue"), symbol: "arrow.right", tint: .acid, prominent: true) {
                    hotkey.cancelRecording()
                    if step == .setup { finish() }
                    else { move(to: OnboardingStep(rawValue: step.rawValue + 1)!) }
                }
            }
        }.padding(30).frame(width: 720, height: height)
            .foregroundStyle(Color.paper).background(Color.ink, in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color.shelfBorder))
            .buttonStyle(NotchiButtonStyle()).textFieldStyle(NotchiTextFieldStyle()).tint(Color.acid)
            .task { permission.refresh(); withAnimation(transitionAnimation) { entered = true }; wave += 1 }
            .onChange(of: permission.isTrusted) { old, trusted in
                if trusted && !old { happy += 1; advanceAfterGrant = step == .permissions }
                else if !trusted { advanceAfterGrant = false }
            }
            .task(id: advanceAfterGrant) {
                guard advanceAfterGrant else { return }
                do {
                    try await Task.sleep(for: .seconds(Motion.permissionCelebration))
                    try Task.checkCancellation()
                    if step == .permissions && permission.isTrusted { move(to: .shelf) }
                } catch { }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in hotkey.cancelRecording() }
            .onDisappear { hotkey.cancelRecording() }
    }
    @ViewBuilder private var chapterContent: some View {
        switch step {
        case .welcome:
            paragraph(String(localized: "A tiny home for the files you’re moving between apps. Drop them at the top of your screen, make a quick edit, then send them on."))
            OnboardingDemo().frame(height: 245)
            lesson("cursorarrow", title: String(localized: "Always within reach"), text: String(localized: "Move your pointer to the notch to open the shelf. On a display without a notch, use the floating pill at the top. It follows your cursor between displays unless you choose a fixed display."))
            lesson("gearshape", title: String(localized: "Learn now, revisit anytime"), text: String(localized: "This tour explains the shelf, actions, scanning, sharing and permissions. Use Back or the progress bars to revisit a chapter. You can replay it from the menu bar or Settings → About."))
        case .permissions:
            PermissionControls(permission: permission)
        case .shelf:
            lesson("tray.and.arrow.down", title: String(localized: "Drop from any app"), text: String(localized: "Drag files, folders, images, links or text toward the top of the screen. The shelf opens during a drag; drop several files together to add multiple cards. Each card shows a preview, name and size."))
            lesson("pin", title: String(localized: "Keep the shelf open"), text: String(localized: "The pin keeps the panel open while you work. Otherwise it closes shortly after your pointer leaves, and stays open during an active task. Use the menu-bar icon or your shortcut if you prefer not to hover."))
            lesson("square.on.square", title: String(localized: "Select, move, remove"), text: String(localized: "Tap a card for its actions. Hold Command and click more cards to select several files for sharing or PDF merging. Drag cards back into Finder or another app. The × removes a card from the shelf; it does not delete the original."))
            lesson("externaldrive", title: String(localized: "Your files stay yours"), text: String(localized: "Keep files in Shelf settings remembers references across launches. Original files must stay accessible. Auto-clear removes old cards only. Temporary results should be saved or dragged into a folder when you want to keep them."))
        case .actions:
            lesson("wand.and.stars", title: String(localized: "Actions match your file"), text: String(localized: "Tap a card, then an action chip. Images can be converted, compressed, resized or stripped of metadata. PDFs can be compressed, split, merged with selected PDFs, or read as text. Any file can be zipped, revealed in Finder or copied as a path."))
            lesson("film", title: String(localized: "Video and audio too"), text: String(localized: "Choose a video size preset, change format, extract audio, trim or mute. Audio has conversion and compression actions. Availability depends on the bundled media engine and supported formats. A size target can require a lower resolution; check the final output size before sending."))
            lesson("checkmark.circle", title: String(localized: "Watch it work"), text: String(localized: "The ring shows progress while the mascot works. You can cancel a media job or retry a failed action. A successful result gets a New card with the before-and-after size. Settings → Actions chooses quality, image format and whether to keep both cards or replace the source card. Original files are never overwritten."))
        case .scanning:
            lesson("doc.viewfinder", title: String(localized: "Build a document"), text: String(localized: "Tap Scan to import with a compatible iPhone, choose images, or capture part of your screen. Continuity Camera availability depends on your Mac and iPhone setup. Screen capture may trigger a separate macOS permission prompt."))
            lesson("rectangle.on.rectangle", title: String(localized: "Give pages a scan look"), text: String(localized: "Document edges are detected and corrected on your Mac. Choose Color, Grayscale or B&W, add more pages, and drag pages into order. Turn on Searchable text layer before Create PDF if you want text search in the result."))
            lesson("text.viewfinder", title: String(localized: "Read text and codes"), text: String(localized: "Use OCR on an image or PDF to recognize text, including English and Hindi, then Copy text. Recognition depends on image clarity; review names and numbers. Barcode detection offers Open link for recognized web addresses. Vision processing stays on your Mac."))
        case .sharing:
            lesson("paperplane", title: String(localized: "Choose files, then a destination"), text: String(localized: "Tap a card’s forward arrow, or select several cards and use Send. The tray lists compatible macOS sharing services. More opens the full system picker; Copy puts files on the clipboard, and Save to saves a copy. Installed apps decide which services and file types they support."))
            lesson("bubble.left.and.bubble.right", title: String(localized: "WhatsApp: you choose who gets it"), text: String(localized: "Choose WhatsApp, then tap Send. With Accessibility confirmed, \(AppConfig.appName) opens WhatsApp, prepares the files as documents and opens its recipient picker. Search or select your contacts there, then press WhatsApp’s Send yourself. \(AppConfig.appName) never chooses recipients or sends a message for you."))
            lesson("exclamationmark.bubble", title: String(localized: "If WhatsApp needs attention"), text: String(localized: "Keep WhatsApp signed in with a chat available, and let it stay in front while the picker is prepared. Cancel another open draft or file chooser first. If access is unconfirmed, open Permission help. WhatsApp updates can change its interface; if automation fails, use Show in Finder and attach the files with WhatsApp’s File/Document control."))
            lesson("archivebox", title: String(localized: "Files, folders and limits"), text: String(localized: "Folders are zipped automatically. Use Make ZIP when you want one archive. Every destination has its own file and size limits, so no app can promise every format will be accepted everywhere. \(AppConfig.appName) reports preparation failures; the destination owns the final send."))
        case .setup:
            paragraph(String(localized: "Choose how you want to open your shelf. These preferences can be changed later from the gear inside the notch or the menu-bar Settings item."))
            LaunchAtLoginControl(login: login)
            NotchiToggle(String(localized: "Open on hover"), isOn: $settings.value.hoverEnabled)
            HotkeyRecorder(settings: settings, manager: hotkey)
            lesson("keyboard", title: String(localized: "Your shortcut"), text: String(localized: "Click the shortcut recorder, then press a key with Command, Control or Option. Escape cancels recording; Delete clears it. The shortcut and menu bar work even when hover is switched off."))
            lesson("slider.horizontal.3", title: String(localized: "Your settings"), text: String(localized: "General controls hover timing, panel size and display. Shelf controls persistence, auto-clear and saving. Actions sets conversion defaults. Shortcuts changes your global key. About includes this tour and Credits. Reduce Motion follows your macOS accessibility preference."))
        }
    }
    private func paragraph(_ text: String) -> some View {
        Text(text).font(Typography.body).foregroundStyle(Color.secondaryText).fixedSize(horizontal: false, vertical: true)
    }
    private func lesson(_ symbol: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: symbol).font(.system(size: 21, weight: .semibold)).foregroundStyle(Color.acid)
                .frame(width: 32, height: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(Typography.heading)
                paragraph(text)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func move(to next: OnboardingStep) {
        hotkey.cancelRecording(); advanceAfterGrant = false
        withAnimation(transitionAnimation) { step = next }
        if next == .setup { wave += 1 }
    }
}
