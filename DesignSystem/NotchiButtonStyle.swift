import SwiftUI

struct NotchiButtonStyle: PrimitiveButtonStyle {
    enum Variant { case primary, secondary, icon, destructive }
    var variant: Variant = .secondary
    init(_ variant: Variant = .secondary) { self.variant = variant }
    func makeBody(configuration: Configuration) -> some View {
        NotchiInteractiveControl(configuration: configuration, chrome: .button(variant))
    }
}
struct NotchiSurfaceButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        NotchiInteractiveControl(configuration: configuration, chrome: .surface)
    }
}
struct NotchiSidebarStyle: PrimitiveButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        NotchiInteractiveControl(configuration: configuration, chrome: .sidebar(selected))
    }
}
private enum NotchiButtonChrome {
    case button(NotchiButtonStyle.Variant), surface, sidebar(Bool)
    var icon: Bool { if case .button(.icon) = self { return true }; return false }
    var surface: Bool { if case .surface = self { return true }; return false }
    var sidebar: Bool { if case .sidebar = self { return true }; return false }
}

/// Own focus and activation instead of inheriting AppKit's blue focus halo.
/// The logical Button keeps its role, shortcut, label and accessibility action.
private struct NotchiInteractiveControl: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let chrome: NotchiButtonChrome
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.notchiSettingsControl) private var settingsControl
    @ObservedObject private var keyboard = KeyboardFocus.shared
    @FocusState private var focused: Bool
    @GestureState private var pressed = false
    @State private var hovering = false
    @State private var size = CGSize.zero
    private var foreground: Color {
        switch chrome {
        case .button(.primary), .sidebar(true): return .ink
        case .button(.destructive): return .coral
        case .surface, .sidebar(false): return .paper
        default: return settingsControl ? .paper : .acid
        }
    }
    private var fill: Color {
        switch chrome {
        case .button(.primary): return .acid.opacity(pressed ? 0.85 : 1)
        case .button(.secondary): return settingsControl ? .paper.opacity(pressed ? 0.12 : (hovering ? 0.08 : 0.04)) : .acid.opacity(pressed ? 0.24 : (hovering ? 0.18 : 0.12))
        case .button(.icon): return .acid.opacity(pressed ? 0.20 : (hovering ? 0.12 : 0))
        case .button(.destructive): return .coral.opacity(pressed ? 0.25 : (hovering ? 0.20 : 0.14))
        case .sidebar(let selected): return selected ? .acid : .acid.opacity(hovering ? 0.08 : 0)
        case .surface: return .clear
        }
    }
    private var border: Color {
        if case .button(.secondary) = chrome { return settingsControl ? .secondaryText.opacity(contrast == .increased ? 1 : 0.35) : .acid.opacity(contrast == .increased ? 0.8 : 0.35) }; return .clear
    }
    var body: some View {
        configuration.label
            .font(settingsControl ? Typography.settingsLabel : Typography.button).foregroundStyle(foreground)
            .lineLimit(chrome.sidebar ? 1 : nil)
            .padding(.horizontal, chrome.icon || chrome.surface ? 0 : 14)
            .padding(.vertical, chrome.icon || chrome.surface ? 0 : (chrome.sidebar ? 11 : (settingsControl ? 4 : 9)))
            .frame(width: chrome.icon ? 28 : nil, height: chrome.icon ? 28 : nil)
            .frame(maxWidth: chrome.sidebar ? .infinity : nil, alignment: chrome.sidebar ? .leading : .center)
            .background(fill, in: Capsule())
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
            .background(GeometryReader { proxy in
                Color.clear.onAppear { size = proxy.size }.onChange(of: proxy.size) { _, value in size = value }
            })
            .contentShape(Rectangle())
            .focusable(enabled).focused($focused).focusEffectDisabled()
            .overlay(Capsule().inset(by: -2).stroke(focused && keyboard.navigating ? Color.acid : .clear, lineWidth: 2).allowsHitTesting(false))
            .scaleEffect(pressed && !reduceMotion ? 0.94 : 1)
            .opacity(enabled ? 1 : 0.4)
            .onHover { hovering = $0 }
            .simultaneousGesture(DragGesture(minimumDistance: 0)
                .updating($pressed) { value, state, _ in
                    state = enabled && CGRect(origin: .zero, size: size).contains(value.location)
                }
                .onEnded { value in
                    guard enabled, abs(value.translation.width) < 10, abs(value.translation.height) < 10,
                          CGRect(origin: .zero, size: size).contains(value.location) else { return }
                    configuration.trigger()
                })
            .onKeyPress(.space) { activate() }
            .onKeyPress(.return) { activate() }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if enabled { configuration.trigger() } }
            .animation(reduceMotion ? Animations.fade : Animations.snappy, value: pressed)
            .animation(reduceMotion ? Animations.fade : Animations.snappy, value: hovering)
    }
    private func activate() -> KeyPress.Result {
        guard enabled else { return .ignored }
        configuration.trigger(); return .handled
    }
}
