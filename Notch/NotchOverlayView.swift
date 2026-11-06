import SwiftUI
import UniformTypeIdentifiers

struct NotchOverlayView: View {
    @ObservedObject var presentation: OverlayPresentation
    @ObservedObject var store: ShelfStore
    @ObservedObject var actions: ActionCoordinator
    @ObservedObject var sharing: ShareAction
    @ObservedObject var scanner: ScanCoordinator
    @ObservedObject var links: LinkCoordinator
    let onPresentation: @Sendable (SilhouetteMetrics) -> Void
    @State private var glowPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let callback = onPresentation
        ZStack(alignment: .top) {
            NotchSilhouette(metrics: presentation.metrics, onPresentation: { @Sendable metrics in callback(metrics) }).fill(Color.ink)
            NotchSilhouette(metrics: presentation.metrics).stroke(Color.white.opacity(0.08), lineWidth: 1)
            NotchSilhouette(metrics: presentation.metrics)
                .stroke(Color.acid, lineWidth: 2)
                .shadow(color: .acid.opacity(glowPulse ? 0.8 : 0.25), radius: glowPulse ? 12 : 4)
                .opacity(store.isDropTargeted ? 1 : 0)
                .animation(store.isDropTargeted && !reduceMotion ? Animations.glow : nil, value: glowPulse)
                .allowsHitTesting(false)
            expandedContent
                .frame(width: presentation.geometry.expandedSize.width,
                       height: presentation.geometry.expandedSize.height)
                .frame(maxWidth: .infinity, alignment: .top)
                .clipShape(NotchSilhouette(metrics: presentation.metrics))
                .allowsHitTesting(presentation.contentStage > 0)
                .accessibilityHidden(presentation.contentStage == 0)
            if !presentation.geometry.hasNotch {
                Text(AppConfig.wordmark).font(Typography.wordmark)
                .foregroundStyle(Color.paper)
                .frame(width: presentation.geometry.collapsedSize.width,
                       height: presentation.geometry.collapsedSize.height)
                .opacity(presentation.wantsExpanded ? 0 : 1)
                .accessibilityLabel(AppConfig.appName)
            }
            if let flight = sharing.flight { SendFlightOverlay(flight: flight).zIndex(5) }
            if links.phase == .flying { LinkPlaneFlightOverlay().zIndex(6) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(NotchSilhouette(metrics: presentation.metrics))
        .coordinateSpace(name: "NotchiSend")
        .font(Typography.body)
        .onDrop(of: [UTType.fileURL, .url, .image, .plainText, .data], isTargeted: Binding(
            get: { store.isDropTargeted }, set: { if !sharing.isPresenting && !scanner.isPresenting && !links.isPresenting { store.setDropTargeted($0) } }),
            perform: { (sharing.isPresenting || scanner.isPresenting || links.isPresenting) ? false : store.acceptDrop($0) })
        .task(id: store.isDropTargeted) { glowPulse = store.isDropTargeted }
        .sheet(item: $actions.mediaOptions) { request in
            MediaTrimSheet(request: request, actions: actions, store: store)
        }
        .sheet(item: $actions.options) { request in
            ActionOptionsSheet(request: request, actions: actions, store: store)
        }
    }

    @State private var messageIndex = 0
    @State private var lastInput = Date()
    @State private var sleepy = false
    @ObservedObject private var settings = SettingsStore.shared
    private var hasWorkspace: Bool { sharing.isPresenting || scanner.isPresenting || links.isPresenting }
    private var working: Bool { links.isBusy || actions.isBusy || scanner.isBusy || store.isImporting }

    private var expandedContent: some View {
        VStack(spacing: PanelLayout.gap) {
            HStack(spacing: 8) {
                Text(AppConfig.wordmark).font(Typography.wordmark)
                Spacer(minLength: 12)
                SettingsLink { Image(systemName: "gearshape.fill") }
                    .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
                    .help(String(localized: "Settings")).accessibilityLabel(String(localized: "Open Settings"))
                Button { store.isPinned.toggle() } label: {
                    Image(systemName: store.isPinned ? "pin.fill" : "pin")
                }.help(store.isPinned ? String(localized: "Unpin overlay") : String(localized: "Pin overlay"))
                    .accessibilityLabel(store.isPinned ? String(localized: "Unpin overlay") : String(localized: "Pin overlay"))
                Button {
                    if links.isPresenting { links.close() }
                    else if scanner.isPresenting { scanner.close() }
                    else if sharing.isPresenting { sharing.close() }
                    else { store.isPinned = false; store.isExpanded = false }
                } label: { Image(systemName: "xmark") }
                    .disabled(actions.isBusy || store.isDropTargeted || sharing.isBusy)
                    .help(String(localized: "Close")).accessibilityLabel(String(localized: "Close"))
            }.font(.system(size: 12, weight: .medium)).buttonStyle(NotchiButtonStyle(.icon))
                .frame(height: 28).revealed(presentation.contentStage >= 1)
            if links.isPresenting {
                LinkWorkspaceView(links: links, store: store, actions: actions).frame(maxHeight: .infinity)
            } else if scanner.isPresenting {
                ScanWorkspaceView(scanner: scanner, store: store).frame(maxHeight: .infinity)
            } else if sharing.isPresenting {
                SendTrayView(sharing: sharing).frame(maxHeight: .infinity)
            } else {
                PanelDropCard(targeted: store.isDropTargeted, active: presentation.wantsExpanded,
                              message: dropMessage) { mascot }
                    .revealed(presentation.contentStage >= 1)
                ShelfView(store: store, actions: actions, sharing: sharing, links: links)
                    .revealed(presentation.contentStage >= 2)
                HStack(spacing: 12) {
                    footerButton("Files", icon: "plus", primary: true) { store.chooseFiles() }
                    footerButton("Scan", icon: "doc.viewfinder") { scanner.open() }
                    footerButton("Link", icon: "link") {
                        if let item = store.activeItem ?? store.files.last { links.show(item) }
                        else { links.showMyLinks() }
                    }
                }.disabled(working).revealed(presentation.contentStage >= 3)
                HStack {
                    Spacer()
                    if let shortcut = settings.value.shortcut {
                        Text(shortcut.label).font(Typography.caption).foregroundStyle(Color.secondaryText)
                            .accessibilityLabel(String(localized: "Open shelf: \(shortcut.label)"))
                    }
                }.frame(height: 12)
            }
        }
        .padding(.horizontal, PanelLayout.padding)
        .padding(.top, presentation.geometry.topInset + PanelLayout.padding)
        .padding(.bottom, PanelLayout.padding)
        .foregroundStyle(Color.paper)
        .onContinuousHover { phase in if case .active = phase { wake() } }
        .simultaneousGesture(TapGesture().onEnded { wake() })
        .onKeyPress(phases: .down) { _ in wake(); return .ignored }
        .onChange(of: store.gulpToken) { _, _ in wake() }
        .onChange(of: working) { _, _ in wake() }
        .task(id: presentation.wantsExpanded) {
            guard presentation.wantsExpanded else { sleepy = false; return }
            messageIndex = (messageIndex + 1) % PanelLayout.messages.count; wake()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                withAnimation(reduceMotion ? Animations.fade : Animations.gentle) {
                    sleepy = !working && !store.isDropTargeted && Date().timeIntervalSince(lastInput) >= Motion.sleepyDelay
                }
            }
        }
    }
    private var dropMessage: String {
        if store.isDropTargeted { return String(localized: "Yes, that one") }
        if store.isImporting { return String(localized: "Adding…") }
        if actions.isBusy { return String(localized: "Working on it") }
        if actions.isComplete { return String(localized: "Looking good") }
        if store.hasError { return NotchiAttention.short(store.message ?? String(localized: "Try again")) }
        return PanelLayout.messages[messageIndex].localized
    }
    private func wake() { lastInput = .now; sleepy = false }
    private func footerButton(_ title: String, icon: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title.localized, systemImage: icon).frame(maxWidth: .infinity).frame(height: 22)
        }.buttonStyle(NotchiButtonStyle(primary ? .primary : .secondary)).frame(maxWidth: .infinity)
    }

    private var mascot: some View {
        BlobMascot(gaze: presentation.gaze, isActive: presentation.wantsExpanded,
                   isTargeted: store.isDropTargeted, gulpToken: store.gulpToken,
                   isWorking: links.isBusy || actions.isBusy || scanner.isBusy || (sharing.isBusy && !sharing.isFlying), happyToken: actions.successToken + scanner.successToken + links.successToken,
                   hasError: sharing.isPresenting ? sharing.toast?.isError == true : actions.job?.phase == .failure,
                   waveToken: sharing.waveToken, isReeling: actions.isMediaWorking, isReading: scanner.reading, thumbToken: links.successToken, isSleepy: sleepy)
    }
}

private extension View {
    func revealed(_ visible: Bool) -> some View {
        opacity(visible ? 1 : 0).scaleEffect(visible ? 1 : 0.96, anchor: .top)
    }
}
