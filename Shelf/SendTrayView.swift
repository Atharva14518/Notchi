import SwiftUI
import AppKit

struct SendOriginFrames: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
struct SendTileFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
struct SendTrayView: View {
    @ObservedObject var sharing: ShareAction
    @ObservedObject private var permission = PermissionManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        if sharing.handoff != nil { sharing.leaveHandoff() } else { sharing.close() }
                    } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(NotchiButtonStyle(.icon)).disabled(sharing.isBusy)
                        .help(String(localized: "Back")).accessibilityLabel(String(localized: "Back"))
                    Text(String(localized: "\(sharing.session?.items.count ?? 0)"))
                        .font(Typography.caption).foregroundStyle(Color.acid)
                        .padding(6).background(Color.acid.opacity(0.12), in: Circle())
                    if let handoff = sharing.handoff {
                        ForEach(handoff.files.urls, id: \.self) { url in
                            SendFilePreview(item: ShelfItem(url: url)).onDrag { NSItemProvider(object: url as NSURL) }
                        }
                    } else {
                        ForEach(sharing.session?.items ?? []) { item in
                            SendFilePreview(item: item).opacity(sharing.isFlying ? 0 : 1)
                                .background(GeometryReader { geometry in
                                    Color.clear.preference(key: SendOriginFrames.self, value: [item.id: geometry.frame(in: .named("NotchiSend"))])
                                })
                        }
                    }
                }.padding(3)
            }.frame(minHeight: 60, maxHeight: 60)
            if let handoff = sharing.handoff {
                Spacer(minLength: 0)
                Button { sharing.copyAndOpenHandoff() } label: {
                    HStack(spacing: 9) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: handoff.app.url.path)).resizable().scaledToFit().frame(width: 22, height: 22)
                        Text(String(localized: "Send")).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity).frame(minHeight: 26)
                }.buttonStyle(NotchiButtonStyle(.primary)).disabled(sharing.isBusy)
                    .help(String(localized: "Choose recipients")).accessibilityLabel(String(localized: "Send with \(handoff.app.title)"))
                HStack(spacing: 14) {
                    Button { sharing.showHandoffFiles() } label: { Image(systemName: "folder") }
                        .help(String(localized: "Show in Finder")).accessibilityLabel(String(localized: "Show in Finder"))
                    Button { sharing.prepareHandoff(handoff.app, archiveAll: true) } label: { Image(systemName: "doc.zipper") }
                        .help(String(localized: "Make ZIP")).accessibilityLabel(String(localized: "Make ZIP"))
                    Button { sharing.copyHandoffLocation() } label: { Image(systemName: "link") }
                        .help(String(localized: "Copy path")).accessibilityLabel(String(localized: "Copy path"))
                }.buttonStyle(NotchiButtonStyle(.icon)).disabled(sharing.isBusy)
                Spacer(minLength: 0)
                if handoff.app.isWhatsApp && !permission.isTrusted {
                    Button { permission.showHelp() } label: {
                        NotchiAttention(message: String(localized: "Permission help"), isError: true)
                    }.buttonStyle(NotchiSurfaceButtonStyle()).help(String(localized: "Accessibility troubleshooting"))
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Array(sharing.targets.enumerated()), id: \.element.id) { index, target in
                            SendAppTile(target: target, index: index) { sharing.choose(target) }
                                .disabled(sharing.isBusy)
                                .background(GeometryReader { geometry in
                                    Color.clear.preference(key: SendTileFrames.self, value: [target.id: geometry.frame(in: .named("NotchiSend"))])
                                })
                        }
                    }.padding(.vertical, 4)
                }
            }
            HStack(spacing: 10) {
                BlobMascot(gaze: .zero, isActive: true, isTargeted: false,
                           isWorking: sharing.isBusy && !sharing.isFlying, hasError: sharing.toast?.isError == true, waveToken: sharing.waveToken)
                    .scaleEffect(0.42).frame(width: 34, height: 30)
                if let toast = sharing.toast {
                    NotchiAttention(message: toast.text, isError: toast.isError).id(toast.id).transition(.opacity)
                } else if sharing.isBusy { BouncingDots().accessibilityLabel(String(localized: "Preparing")) }
                Spacer(minLength: 0)
            }
        }
        .animation(reduceMotion ? Animations.fade : Animations.snappy, value: sharing.toast?.id)
        .onPreferenceChange(SendOriginFrames.self) { sharing.originFrames = $0 }
        .onPreferenceChange(SendTileFrames.self) { sharing.tileFrames = $0 }
        .accessibilityElement(children: .contain).accessibilityLabel(String(localized: "Send files"))
    }
}

struct SendFilePreview: View {
    let item: ShelfItem
    @State private var image: NSImage?
    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: image ?? NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().scaledToFit().frame(width: 29, height: 29).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(Typography.caption).lineLimit(1).truncationMode(.middle)
                Text(item.detail).font(Typography.caption).foregroundStyle(Color.secondaryText).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(8).frame(width: 142, height: 48)
        .foregroundStyle(Color.paper)
        .background(Color.shelfSurface, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.shelfBorder))
        .task(id: item.url) { image = await ThumbnailCache.shared.image(for: item) }
    }
}

struct SendAppTile: View {
    let target: SendTarget
    let index: Int
    let select: () -> Void
    @State private var appeared = false
    @State private var hovering = false
    @State private var angle: Double = 0
    @State private var nativeFocused = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        control
        .rotationEffect(.degrees(reduceMotion ? 0 : angle))
        .scaleEffect(reduceMotion || appeared ? 1 : 0.75)
        .opacity(appeared ? 1 : 0)
        .onHover { hovering = $0 }
        .accessibilityLabel(target.title)
        .task {
            if !reduceMotion { try? await Task.sleep(for: .seconds(Double(min(index, 12)) * Motion.sendTileStagger)) }
            if !Task.isCancelled { withAnimation(reduceMotion ? nil : Animations.bouncy) { appeared = true } }
        }
        .task(id: hovering) {
            guard hovering, !reduceMotion else { angle = 0; return }
            defer { angle = 0 }
            do {
                for value in [-3.0, 2, -1, 0] {
                    try Task.checkCancellation()
                    withAnimation(Animations.snappy) { angle = value }
                    try await Task.sleep(for: .seconds(Motion.sendWiggleStep))
                }
            } catch { }
        }
    }

    @ViewBuilder private var control: some View {
        if case .more = target.kind {
            // Keep one accessible native button. It opens the picker on mouse-down.
            tileVisual.accessibilityHidden(true)
                .overlay(PickerMouseDownTrigger(open: select, focusChanged: { nativeFocused = $0 }))
        } else {
            Button(action: select) { tileVisual }.buttonStyle(NotchiSurfaceButtonStyle())
        }
    }

    private var tileVisual: some View {
        VStack(spacing: 7) {
            Image(nsImage: target.image).resizable().scaledToFit().frame(width: 32, height: 32)
            Text(target.title).font(Typography.button).lineLimit(2).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

        }
        .foregroundStyle(Color.paper)
        .frame(maxWidth: .infinity).frame(height: 89)
        .background(hovering ? Color.acid.opacity(0.19) : .shelfSurface,
                    in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(hovering || nativeFocused ? Color.acid : .shelfBorder, lineWidth: nativeFocused ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 17))
    }

}

/// NSSharingServicePicker documents show(...) as a mouse-down operation.
/// Use a transparent native control for More instead of waiting for mouse-up.
private struct PickerMouseDownTrigger: NSViewRepresentable {
    let open: () -> Void
    let focusChanged: (Bool) -> Void
    func makeNSView(context: Context) -> PickerButton {
        let button = PickerButton(frame: .zero)
        button.isTransparent = true
        button.isBordered = false
        button.title = ""
        button.focusRingType = .none
        button.target = button
        button.action = #selector(PickerButton.activate)
        button.setAccessibilityLabel(String(localized: "More…"))
        return button
    }
    func updateNSView(_ view: PickerButton, context: Context) {
        view.open = open
        view.focusChanged = focusChanged
        view.isEnabled = context.environment.isEnabled
    }
    final class PickerButton: NSButton {
        var open: (() -> Void)?
        var focusChanged: ((Bool) -> Void)?
        override func becomeFirstResponder() -> Bool {
            let result = super.becomeFirstResponder(); if result { focusChanged?(true) }; return result
        }
        override func resignFirstResponder() -> Bool {
            let result = super.resignFirstResponder(); if result { focusChanged?(false) }; return result
        }
        override func mouseDown(with event: NSEvent) { if isEnabled { open?() } }
        @objc func activate() { if isEnabled { open?() } }
        override func accessibilityPerformPress() -> Bool {
            guard isEnabled else { return false }
            open?()
            return true
        }
    }
}

struct SendFlightOverlay: View {
    let flight: SendFlight
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(flight.items.enumerated()), id: \.element.id) { index, item in
                let source = flight.origins[item.id] ?? .zero
                SendFilePreview(item: item)
                    .modifier(SendFlightModifier(progress: progress,
                        path: SendFlightPath(start: CGPoint(x: source.midX, y: source.midY),
                            end: CGPoint(x: flight.target.midX, y: flight.target.midY)),
                        tilt: index.isMultiple(of: 2) ? -12 : 12))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false).accessibilityHidden(true)
        .task(id: flight.id) {
            guard !reduceMotion else { progress = 1; return }
            await Task.yield()
            withAnimation(Animations.sendFlight) { progress = 1 }
        }
    }
}

private struct SendFlightModifier: AnimatableModifier {
    var progress: CGFloat
    let path: SendFlightPath
    let tilt: Double
    var animatableData: CGFloat { get { progress } set { progress = newValue } }
    func body(content: Content) -> some View {
        let point = path.point(at: progress)
        content.scaleEffect(1 - progress * 0.8)
            .rotationEffect(.degrees(Double(progress) * tilt))
            .position(point)
            .opacity(progress < 0.8 ? 1 : max(0, (1 - progress) / 0.2))
    }
}
