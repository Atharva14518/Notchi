import SwiftUI

struct NotchiOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var id: Value { value }
    init(_ value: Value, _ title: String) { self.value = value; self.title = title }
}

struct NotchiToggle: View {
    let title: String
    @Binding var isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @Environment(\.notchiSettingsControl) private var settingsControl
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var squashed = false
    init(_ title: String, isOn: Binding<Bool>) { self.title = title; _isOn = isOn }
    var body: some View {
        HStack {
            Text(title.localized).font(settingsControl ? Typography.settingsLabel : Typography.body).opacity(enabled ? 1 : 0.4)
            Spacer(minLength: 12)
            Button { withAnimation(reduceMotion ? Animations.fade : Animations.snappy) { isOn.toggle() } } label: {
                Capsule().fill(isOn ? Color.acid : .shelfSurface)
                    .overlay(Capsule().strokeBorder(isOn ? Color.acid : (contrast == .increased ? .secondaryText : .shelfBorder)))
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle().fill(isOn ? Color.ink : .secondaryText).frame(width: 18, height: 18)
                            .scaleEffect(x: squashed && !reduceMotion ? 1.12 : 1, y: squashed && !reduceMotion ? 0.9 : 1).padding(3)
                    }.frame(width: 46, height: 24)
                    .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
            }.buttonStyle(NotchiSurfaceButtonStyle())
                .accessibilityLabel(title.localized)
                .accessibilityValue(isOn ? String(localized: "On") : String(localized: "Off"))
                .accessibilityRepresentation { Toggle(title.localized, isOn: $isOn) }
                .task(id: isOn) {
                    guard !reduceMotion else { squashed = false; return }
                    withAnimation(Animations.squash) { squashed = true }
                    try? await Task.sleep(for: .seconds(Motion.pressDuration))
                    if !Task.isCancelled { withAnimation(Animations.snappy) { squashed = false } }
                }
        }.frame(minHeight: 32)
    }
}

struct NotchiSegmented<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [NotchiOption<Value>]
    @Environment(\.notchiSettingsControl) private var settingsControl
    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(_ title: String, selection: Binding<Value>, options: [NotchiOption<Value>]) {
        self.title = title; _selection = selection; self.options = options
    }
    var body: some View {
        HStack(spacing: 3) {
            ForEach(options) { option in
                Button { withAnimation(reduceMotion ? Animations.fade : Animations.snappy) { selection = option.value } } label: {
                    Text(option.title.localized).font(settingsControl ? Typography.settingsLabel : Typography.button).lineLimit(1).minimumScaleFactor(0.85)
                        .foregroundStyle(selection == option.value ? Color.ink : .secondaryText)
                        .padding(.horizontal, settingsControl ? 8 : 11).padding(.vertical, settingsControl ? 2 : 8).frame(maxWidth: .infinity)
                        .background {
                            if selection == option.value {
                                if reduceMotion { Capsule().fill(Color.acid).transition(.opacity) }
                                else { Capsule().fill(Color.acid).matchedGeometryEffect(id: "selected", in: highlight) }
                            }
                        }.contentShape(Capsule())
                }.buttonStyle(NotchiSurfaceButtonStyle())
                    .accessibilityLabel(option.title.localized)
                    .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }.padding(settingsControl ? 2 : 3).background(Color.shelfSurface, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.shelfBorder))
            .accessibilityElement(children: .contain)
    }
}

struct NotchiPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [NotchiOption<Value>]
    var segmented: Bool
    @State private var open = false
    init(_ title: String, selection: Binding<Value>, options: [NotchiOption<Value>], segmented: Bool = true) {
        self.title = title; _selection = selection; self.options = options; self.segmented = segmented
    }
    var body: some View {
        if segmented && (2...3).contains(options.count) {
            NotchiSegmented(title, selection: $selection, options: options)
        } else {
            Button { open.toggle() } label: {
                HStack(spacing: 12) {
                    Text((options.first { $0.value == selection }?.title ?? title).localized).lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                }
            }.buttonStyle(NotchiButtonStyle(.secondary))
                .accessibilityLabel(title.localized)
                .accessibilityValue((options.first { $0.value == selection }?.title ?? title).localized)
                .popover(isPresented: $open, arrowEdge: .bottom) {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(options) { option in
                                Button { selection = option.value; open = false } label: {
                                    HStack {
                                        Text(option.title.localized).lineLimit(1)
                                        Spacer()
                                        if selection == option.value { Image(systemName: "checkmark") }
                                    }
                                }.buttonStyle(NotchiSidebarStyle(selected: selection == option.value))
                            }
                        }.padding(8)
                    }.frame(width: 240, height: min(CGFloat(options.count) * 42 + 16, 280))
                        .foregroundStyle(Color.paper).background(Color.ink).presentationBackground(Color.ink)
                        .preferredColorScheme(.dark).tint(Color.acid)
                }
        }
    }
}

struct NotchiInfo: View {
    let text: String
    @State private var open = false
    var body: some View {
        Button { open.toggle() } label: { Image(systemName: "info.circle").font(.system(size: 11)) }
            .buttonStyle(NotchiButtonStyle(.icon)).help(text.localized)
            .accessibilityLabel(String(localized: "More information"))
            .popover(isPresented: $open) {
                Text(text.localized).font(Typography.body).foregroundStyle(Color.paper)
                    .fixedSize(horizontal: false, vertical: true).padding(14).frame(maxWidth: 260)
                    .background(Color.ink).presentationBackground(Color.ink)
            }
    }
}

struct NotchiSettingRow<Content: View>: View {
    let title: String
    let info: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 0) { Text(title.localized).font(Typography.button); NotchiInfo(text: info); Spacer() }
            content()
        }
    }
}

struct NotchiTextFieldStyle: TextFieldStyle {
    @FocusState private var focused: Bool
    @ObservedObject private var keyboard = KeyboardFocus.shared
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.textFieldStyle(.plain).focused($focused).font(Typography.body).foregroundStyle(Color.paper)
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(Color.shelfSurface, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.acid.opacity(focused && keyboard.navigating ? 1 : 0.35), lineWidth: focused && keyboard.navigating ? 2 : 1)).tint(Color.acid)
    }
}

struct NotchiSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var body: some View {
        GeometryReader { geometry in
            let fraction = min(1, max(0, (value - range.lowerBound) / max(0.001, range.upperBound - range.lowerBound)))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.shelfBorder).frame(height: 4)
                Capsule().fill(Color.acid).frame(width: max(0, geometry.size.width * fraction), height: 4)
                Circle().fill(Color.acid).frame(width: 16, height: 16).offset(x: max(0, geometry.size.width - 16) * fraction)
            }.frame(height: 24).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                    value = range.lowerBound + min(1, max(0, event.location.x / max(1, geometry.size.width))) * (range.upperBound - range.lowerBound)
                })
        }.frame(height: 24).accessibilityElement().accessibilityValue(value.formatted(.number.precision(.fractionLength(1))))
            .accessibilityAdjustableAction { direction in
                let step = max(0.01, (range.upperBound - range.lowerBound) / 100)
                value = min(range.upperBound, max(range.lowerBound, value + (direction == .increment ? step : -step)))
            }
    }
}

struct NotchiAttention: View {
    let message: String
    var isError = false
    var body: some View {
        Text(Self.short(message).localized).font(Typography.caption)
            .foregroundStyle(isError ? Color.coral : .acid)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background((isError ? Color.coral : .acid).opacity(0.12), in: Capsule())
            .fixedSize(horizontal: false, vertical: true).help(message.localized).accessibilityLabel(message.localized)
    }
    static func short(_ message: String) -> String {
        let lower = message.lowercased()
        if message.split(whereSeparator: \.isWhitespace).count <= 4 { return message }
        if lower.contains("size limit") || lower.contains("too large") || lower.contains("exceeds") { return "File too large" }
        if lower.contains("accessibility") || lower.contains("access for") { return "Enable Accessibility" }
        if lower.hasPrefix("cancelled") || lower.hasPrefix("stopped") { return "Cancelled" }
        if lower.contains("copied") { return "Copied" }
        if lower.contains("saved") { return "Saved" }
        if lower.contains("offline") || lower.contains("moved") { return "File unavailable" }
        if lower.contains("reading") { return "Reading…" }
        if lower.contains("building") || lower.contains("preparing") { return "Preparing…" }
        if lower.contains("no text") || lower.contains("no readable text") { return "No text found" }
        if lower.contains("dark") { return "Needs more light" }
        return String(localized: "Try again")
    }
}
