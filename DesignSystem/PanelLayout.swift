import SwiftUI

/// Shared spacing and height budgets keep the panel comfortable without clipping.
enum PanelLayout {
    static let padding: CGFloat = 20
    static let gap: CGFloat = 16
    static let emptyHeight: CGFloat = 296
    static let shelfHeight: CGFloat = 368
    static let workspaceHeight: CGFloat = 392
    static let shelfGap: CGFloat = 12
    static let chipHeight: CGFloat = 52
    static let chipStripHeight: CGFloat = 60
    static let actionRowHeight: CGFloat = 48
    static let messages = ["Feed me files", "Drop it here", "Compress? Convert? Send?", "Got something big?", "Hungry. Files please."]
}

struct PanelDropCard<Character: View>: View {
    let targeted: Bool
    let active: Bool
    let message: String
    @ViewBuilder let character: () -> Character
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        HStack(spacing: PanelLayout.gap) {
            character().scaleEffect(0.72).frame(width: 56, height: 48)
            Text(message.localized).font(Typography.heading).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.padding(.horizontal, 16).frame(maxWidth: .infinity).frame(minHeight: 64)
            .background(Color.shelfSurface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(
                Color.acid.opacity(targeted || contrast == .increased ? 1 : 0.3),
                style: StrokeStyle(lineWidth: 1.5, dash: targeted ? [] : [5, 5], dashPhase: phase)))
            .task(id: active && !reduceMotion && !targeted) {
                phase = 0
                guard active && !reduceMotion && !targeted else { return }
                withAnimation(Animations.marchingDashes) { phase = -20 }
            }
            .accessibilityElement(children: .combine)
    }
}
