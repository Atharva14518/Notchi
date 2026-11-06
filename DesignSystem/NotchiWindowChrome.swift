import SwiftUI
import AppKit

/// Keep the native title bar and toolbar layout; theme each preference item.
struct NotchiWindowChrome: NSViewRepresentable {
    var title: String = AppConfig.appName
    var tabs: [(title: String, symbol: String)] = []
    var onSelect: ((String) -> Void)? = nil
    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ view: ChromeView, context: Context) {
        view.title = title; view.tabs = tabs; view.onSelect = onSelect; view.apply()
    }
    final class ChromeView: NSView {
        var title = AppConfig.appName
        var tabs: [(title: String, symbol: String)] = []
        var onSelect: ((String) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); apply() }
        func apply() {
            guard let window else { return }
            window.title = title
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(Color.ink)
            window.appearance = NSAppearance(named: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? .accessibilityHighContrastDarkAqua : .darkAqua)
            styleToolbar()
            // SwiftUI installs the preference toolbar after hosting the view.
            DispatchQueue.main.async { [weak self] in self?.styleToolbar() }
        }
        private func styleToolbar() {
            guard !tabs.isEmpty, let toolbar = window?.toolbar else { return }
            toolbar.displayMode = .iconOnly
            for item in toolbar.items {
                guard let tab = tabs.first(where: { $0.title == item.label }) else { continue }
                // A native NSToolbarItem retains standard positioning and TabView
                // selection. Its custom view prevents AppKit's forced blue tint.
                let label = tab.title
                let view = SettingsToolbarTab(title: label, symbol: tab.symbol, selected: title == label) { [weak self] in self?.onSelect?(label) }
                if let host = item.view as? NSHostingView<SettingsToolbarTab> {
                    host.rootView = view
                } else {
                    let host = NSHostingView(rootView: view)
                    host.frame = NSRect(x: 0, y: 0, width: 72, height: 50)
                    item.view = host
                }
            }
            toolbar.selectedItemIdentifier = nil // selection is drawn in lime by our tab view
        }
    }
}

private struct SettingsToolbarTab: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 19, weight: .regular))
                Text(title).font(Typography.font(size: 11)).lineLimit(1)
            }.foregroundStyle(selected ? Color.acid : .secondaryText)
                .frame(width: 68, height: 46)
                .background(selected ? Color.acid.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(NotchiSurfaceButtonStyle()).help(title).accessibilityLabel(title)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .preferredColorScheme(.dark)
    }
}
