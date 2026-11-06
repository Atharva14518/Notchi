import SwiftUI

struct BlobMascot: View {
    var gaze: CGPoint
    var isActive: Bool
    var isTargeted: Bool
    var gulpToken = 0
    var isWorking = false
    var happyToken = 0
    var hasError = false
    var waveToken = 0
    var isReeling = false
    var isReading = false
    var thumbToken = 0
    var isSleepy = false
    @State private var happy = false
    @State private var thumbsUp = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blinking = false
    @State private var gulpScale: CGFloat = 1
    @State private var bobbing = false
    @State private var hop: CGFloat = 0
    @State private var handAngle: Double = 0
    @State private var waving = false

    var body: some View {
        ZStack {
            BlobBody().fill(hasError ? Color.coral : (isTargeted ? .mint : .acid))
            if thumbsUp {
                Image(systemName: "hand.thumbsup.fill").font(.system(size: 25, weight: .bold))
                    .foregroundStyle(Color.acid).rotationEffect(.degrees(-15)).offset(x: 39, y: -12)
                    .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.5)))
            }
            if waving {
                ZStack(alignment: .top) {
                    Capsule().fill(Color.acid).frame(width: 8, height: 28)
                    HStack(spacing: 1) {
                        Capsule().fill(Color.acid).frame(width: 4, height: 9)
                        Capsule().fill(Color.acid).frame(width: 4, height: 12)
                        Capsule().fill(Color.acid).frame(width: 4, height: 9)
                    }.offset(y: -4)
                }
                .rotationEffect(.degrees(handAngle), anchor: .bottom)
                .offset(x: 36, y: -16)
            }
            if isWorking && !isReading {
                Capsule().fill(Color.ink.opacity(0.65)).frame(width: 60, height: 4).offset(y: -3)
            }
            HStack(spacing: 12) { eye; eye }
                .offset(x: reduceMotion ? 0 : gaze.x * 3, y: -3 + (reduceMotion ? 0 : gaze.y * 3))
                .animation(reduceMotion ? nil : Animations.gentle, value: gaze)
            if isReading {
                HStack(spacing: 2) {
                    ForEach(0..<2) { _ in Circle().stroke(Color.ink, lineWidth: 2.2).frame(width: 21, height: 21) }
                }.overlay(Capsule().fill(Color.ink).frame(width: 5, height: 2)).offset(y: -3)
            } else if isWorking {
                HStack(spacing: 3) {
                    ForEach(0..<2) { _ in
                        RoundedRectangle(cornerRadius: 5).fill(Color.paper.opacity(0.25))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.ink, lineWidth: 2))
                            .frame(width: 20, height: 19)
                    }
                }.offset(y: -3)
            }
            if isReeling { FilmReel(isActive: isWorking).offset(y: 28) }
            Ellipse().fill(Color.ink)
                .frame(width: isTargeted ? 16 : 8, height: isTargeted ? 18 : (happy ? 6 : 3))
                .offset(y: 15)
                .animation(reduceMotion ? nil : Animations.bouncy, value: isTargeted)
        }
        .frame(width: 76, height: 68)
        .scaleEffect(gulpScale)
        .rotationEffect(.degrees(isTargeted && !reduceMotion ? -5 : 0))
        .offset(y: isWorking && bobbing && !reduceMotion ? -4 : hop)
        .animation(isWorking && !reduceMotion ? Animations.bob : nil, value: bobbing)
        .animation(reduceMotion ? nil : Animations.bouncy, value: isTargeted)
        .overlay(SparkleBurst(trigger: gulpToken))
        .task(id: isWorking) { bobbing = isWorking }
        .task(id: thumbToken) {
            guard thumbToken > 0 else { return }
            withAnimation(reduceMotion ? Animations.fade : Animations.bouncy) { thumbsUp = true }
            try? await Task.sleep(for: .seconds(Motion.linkCelebration))
            withAnimation(Animations.fade) { thumbsUp = false }
        }
        .task(id: waveToken) {
            guard waveToken > 0 else { return }
            waving = true
            defer { waving = false; handAngle = 0 }
            do {
                for angle in [-18.0, 18, -18, 18, 0] {
                    try Task.checkCancellation()
                    withAnimation(reduceMotion ? nil : Animations.snappy) { handAngle = reduceMotion ? 0 : angle }
                    try await Task.sleep(for: .seconds(Motion.waveStep))
                }
            } catch { }
        }
        .task(id: gulpToken) {
            guard gulpToken > 0, !reduceMotion else { return }
            defer { gulpScale = 1 }
            do {
                withAnimation(Animations.squash) { gulpScale = 1.15 }
                try await Task.sleep(for: .seconds(Motion.gulpBeat))
                withAnimation(Animations.squash) { gulpScale = 0.95 }
                try await Task.sleep(for: .seconds(Motion.gulpBeat))
                withAnimation(Animations.bouncy) { gulpScale = 1 }
            } catch { }
        }
        .task(id: happyToken) {
            guard happyToken > 0 else { return }
            happy = true
            defer { happy = false }
            if reduceMotion { try? await Task.sleep(for: .seconds(Motion.linkCelebration)); return }
            defer { hop = 0 }
            withAnimation(Animations.bouncy) { hop = -12 }
            try? await Task.sleep(for: .seconds(Motion.gulpBeat * 2))
            if !Task.isCancelled { withAnimation(Animations.bouncy) { hop = 0 } }
        }
        .task(id: isActive && !reduceMotion) {
            guard isActive && !reduceMotion else { blinking = false; return }
            defer { blinking = false }
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(Double.random(in: Motion.blinkInterval)))
                    blinking = true
                    try await Task.sleep(for: .seconds(Motion.blinkDuration))
                    blinking = false
                }
            } catch { }
        }
        .accessibilityHidden(true)
    }
    private var eye: some View {
        Capsule().fill(Color.ink).frame(width: isTargeted ? 9 : 7, height: blinking || isSleepy ? 1.5 : (isTargeted ? 13 : 9))
            .animation(reduceMotion ? nil : Animations.squash, value: blinking)
    }
}

private struct BlobBody: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        p.move(to: point(0.12, 0.71))
        p.addCurve(to: point(0.3, 0.11), control1: point(-0.03, 0.4), control2: point(0.14, 0.1))
        p.addCurve(to: point(0.83, 0.25), control1: point(0.53, -0.04), control2: point(0.78, 0.04))
        p.addCurve(to: point(0.88, 0.82), control1: point(0.98, 0.45), control2: point(1.03, 0.77))
        p.addCurve(to: point(0.62, 0.9), control1: point(0.81, 1.01), control2: point(0.74, 0.91))
        p.addCurve(to: point(0.37, 0.94), control1: point(0.51, 0.83), control2: point(0.48, 1.03))
        p.addCurve(to: point(0.12, 0.71), control1: point(0.18, 1.01), control2: point(0.18, 0.84))
        p.closeSubpath()
        return p
    }
}
