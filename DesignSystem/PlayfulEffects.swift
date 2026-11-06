import SwiftUI
import AppKit

struct SparkleBurst: View {
    var trigger: Int
    var poof = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var visible = false
    var body: some View {
        ZStack {
            if visible && !reduceMotion {
                ForEach(0..<8) { index in
                    let angle = Double(index) * .pi / 4
                    Group {
                        if poof { Circle().fill(Color.paper.opacity(0.6)) }
                        else { Image(systemName: index.isMultiple(of: 2) ? "sparkle" : "circle.fill")
                            .foregroundStyle([Color.acid, .acid, .sunnyYellow, .mint][index % 4]) }
                    }
                    .frame(width: poof ? 7 : 9, height: poof ? 7 : 9)
                    .scaleEffect(expanded ? 0.2 : 1)
                    .offset(x: expanded ? cos(angle) * 50 : 0, y: expanded ? sin(angle) * 42 : 0)
                    .opacity(expanded ? 0 : 1)
                }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .task(id: trigger) {
            guard trigger > 0 else { return }
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { expanded = false; visible = true }
            await Task.yield()
            withAnimation(poof ? Animations.poof : Animations.particles) { expanded = true }
            try? await Task.sleep(for: .seconds(poof ? Motion.poofDuration : Motion.particleDuration))
            if !Task.isCancelled { visible = false }
        }
    }
}

struct BouncingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bouncing = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle().fill(Color.acid).frame(width: 4, height: 4)
                    .offset(y: bouncing && !reduceMotion ? -4 : 0)
                    .animation(reduceMotion ? nil : Animations.bob.delay(Double(index) * Motion.cardStagger), value: bouncing)
            }
        }
        .onAppear { bouncing = true }
        .accessibilityLabel(String(localized: "Working"))
    }
}

struct CountUpSavings: View {
    let comparison: SizeComparison
    var compact = false
    @State private var value: Double = 0
    @State private var savedBytes: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if comparison.saved > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    AnimatedSavedBytes(value: savedBytes).font(compact ? Typography.button : Typography.heading).foregroundStyle(Color.acid)
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    AnimatedPercent(value: value).font(Typography.button).foregroundStyle(Color.acid)
                }
            } else { Text(comparison.after > comparison.before ? String(localized: "new file, larger size") : String(localized: "same size, new file"))
                    .font(Typography.button).foregroundStyle(Color.paper) }
            if !compact { Text(comparison.description).font(Typography.caption).foregroundStyle(Color.secondaryText).lineLimit(1) }
        }
        .onAppear { update(comparison) }
        .onChange(of: comparison) { _, newValue in update(newValue) }
    }
    private func update(_ comparison: SizeComparison) {
        withAnimation(reduceMotion ? nil : Animations.gentle) {
            value = Double(comparison.percent)
            savedBytes = Double(comparison.saved)
        }
    }
}

private struct AnimatedSavedBytes: View, Animatable {
    var value: Double
    var animatableData: Double { get { value } set { value = newValue } }
    var body: some View {
        let bytes = Int64(min(max(0, value.rounded()), Double(Int64.max).nextDown))
        Text(String(localized: "\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) saved")).monospacedDigit()
    }
}

private struct AnimatedPercent: View, Animatable {
    var value: Double
    var animatableData: Double { get { value } set { value = newValue } }
    var body: some View { Text(String(localized: "\(Int(value.rounded()))% smaller")).monospacedDigit() }
}

struct CardShake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat { get { amount } set { amount = newValue } }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(amount * .pi * 6) * 3, y: 0))
    }
}

/// Trackpad swipe-up removal is independent of drag-out and horizontal shelf scrolling.
struct SwipeRemovalMonitor: NSViewRepresentable {
    var removeHovered: () -> Bool
    func makeNSView(context: Context) -> MonitorView { MonitorView(action: removeHovered) }
    func updateNSView(_ view: MonitorView, context: Context) { view.action = removeHovered }
    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stop() }
    final class MonitorView: NSView {
        var action: () -> Bool
        private var monitor: Any?
        init(action: @escaping () -> Bool) {
            self.action = action
            super.init(frame: .zero)
            monitor = NSEvent.addLocalMonitorForEvents(matching: .swipe) { [weak self] event in
                guard let self, event.window == self.window, event.deltaY > 0,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                return self.action() ? nil : event
            }
        }
        required init?(coder: NSCoder) { fatalError(String(localized: "init(coder:) is not supported")) }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    }
}
