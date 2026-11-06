import SwiftUI

/// Decorative flight. The actual shelf file remains in place; no filenames or
/// public URLs are embedded in particles or accessibility descriptions.
struct LinkPlaneFlightOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var launched = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Color.shelfSurface)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.acid))
                .opacity(launched ? 0 : 1)
            Image(systemName: "paperplane.fill").resizable().scaledToFit().foregroundStyle(Color.acid)
                .padding(22).opacity(launched ? 1 : 0)
        }.frame(width: 118, height: 137)
            .scaleEffect(reduceMotion ? 1 : (launched ? 0.34 : 1))
            .rotationEffect(.degrees(reduceMotion ? 0 : (launched ? -23 : 0)))
            .offset(x: reduceMotion ? 0 : (launched ? 62 : -70), y: reduceMotion ? 100 : (launched ? -150 : 140))
            .opacity(reduceMotion && launched ? 0 : 1)
            .allowsHitTesting(false).accessibilityHidden(true)
            .task { withAnimation(reduceMotion ? Animations.fade : Animations.sendFlight) { launched = true } }
    }
}
