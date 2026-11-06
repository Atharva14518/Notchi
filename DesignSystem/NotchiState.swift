import SwiftUI

/// Empty/loading/error presentations share the character and one clear action.
struct NotchiState: View {
    let title: String
    var working = false
    var error = false
    let actionTitle: String
    let action: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            BlobMascot(gaze: .zero, isActive: true, isTargeted: false, isWorking: working, hasError: error)
                .scaleEffect(0.55).frame(width: 44, height: 40)
            Text(NotchiAttention.short(title).localized).font(Typography.body)
                .foregroundStyle(error ? Color.coral : .secondaryText).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(actionTitle.localized, action: action).buttonStyle(NotchiButtonStyle(.secondary))
        }.frame(minHeight: 48)
    }
}
