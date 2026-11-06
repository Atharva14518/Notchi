import SwiftUI

struct FilmReel: View {
    var isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: Motion.filmFrameInterval, paused: !isActive || reduceMotion)) { context in
            let phase = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Motion.filmReelDuration) / Motion.filmReelDuration
            HStack(spacing: 1) {
                reel(angle: phase * 360)
                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(Color.ink)
                    HStack(spacing: 4) {
                        ForEach(0..<10) { _ in
                            VStack(spacing: 3) {
                                Rectangle().fill(Color.acid).frame(width: 3, height: 2)
                                Rectangle().fill(Color.paper.opacity(0.65)).frame(width: 6, height: 5)
                                Rectangle().fill(Color.acid).frame(width: 3, height: 2)
                            }
                        }
                    }.offset(x: -CGFloat(phase) * 10)
                }.frame(width: 57, height: 17).clipped()
                reel(angle: phase * 360)
            }
        }.frame(width: 88, height: 21).accessibilityHidden(true)
    }
    private func reel(angle: Double) -> some View {
        ZStack {
            Circle().fill(Color.paper).frame(width: 17, height: 17)
            ForEach(0..<3) { index in
                Circle().fill(Color.ink).frame(width: 4, height: 4).offset(y: -4)
                    .rotationEffect(.degrees(Double(index) * 120 + angle))
            }
        }
    }
}
