import SwiftUI

/// A single animatable stroke changes from a progress arc into a checkmark.
struct ProgressRing: View {
    var progress: Double
    var isComplete: Bool
    var isIndeterminate = false
    var size: CGFloat = 26
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let spinning = isIndeterminate && !isComplete && !reduceMotion
        // A paused timeline has no repeating animation left to rotate the checkmark.
        // Keep the same stroke identity so its arc-to-check morph remains animated.
        TimelineView(.animation(minimumInterval: Motion.frameInterval, paused: !spinning)) { context in
            let turn = spinning ? context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: Motion.orbitDuration) / Motion.orbitDuration : 0
            ZStack {
                Circle().stroke(Color.shelfBorder, lineWidth: 2.5)
                    .opacity(isComplete ? 0 : 1)
                CompletionStroke(progress: min(max(progress, 0.02), 1), morph: isComplete ? 1 : 0)
                    .stroke(isComplete ? Color.mint : .acid,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .rotationEffect(.degrees(turn * 360))
            }
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .snappy, value: progress)
        .animation(reduceMotion ? nil : .bouncy, value: isComplete)
        .accessibilityLabel(isComplete ? "Complete" : "Progress")
        .accessibilityValue(isComplete ? String(localized: "Done") : (isIndeterminate ? String(localized: "Working") : String(localized: "\(Int(progress * 100)) percent")))
    }
}

private struct CompletionStroke: Shape {
    var progress: Double
    var morph: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(progress, morph) }
        set { progress = newValue.first; morph = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.42
        let start = CGPoint(x: rect.minX + rect.width * 0.20, y: rect.minY + rect.height * 0.52)
        let joint = CGPoint(x: rect.minX + rect.width * 0.43, y: rect.minY + rect.height * 0.75)
        let end = CGPoint(x: rect.minX + rect.width * 0.82, y: rect.minY + rect.height * 0.28)
        for index in 0...60 {
            let t = Double(index) / 60
            let angle: Double = -Double.pi / 2 + t * Double.pi * 2 * progress
            let arc = CGPoint(x: center.x + CGFloat(cos(angle)) * radius,
                              y: center.y + CGFloat(sin(angle)) * radius)
            let fraction = t < 0.4 ? t / 0.4 : (t - 0.4) / 0.6
            let a = t < 0.4 ? start : joint
            let b = t < 0.4 ? joint : end
            let check = CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
            let point = CGPoint(x: arc.x + (check.x - arc.x) * morph, y: arc.y + (check.y - arc.y) * morph)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
