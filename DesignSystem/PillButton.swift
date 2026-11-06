import SwiftUI

struct PillButton: View {
    let title: String
    let symbol: String
    var tint: Color = .paper
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label { Text(title.localized) } icon: { Image(systemName: symbol) }

        }
        .buttonStyle(NotchiButtonStyle(tint == .coral ? .destructive : (prominent ? .primary : .secondary)))
    }
}

