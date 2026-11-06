import SwiftUI

struct IconBadge: View {
    let symbol: String
    var tint: Color = .acid
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.ink)
            .frame(width: size, height: size)
            .background(tint, in: RoundedRectangle(cornerRadius: size * 0.22))
            .accessibilityHidden(true)
    }
}
