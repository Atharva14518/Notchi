import SwiftUI

struct MediaTrimSheet: View {
    let request: MediaOptionsRequest
    @ObservedObject var actions: ActionCoordinator
    @ObservedObject var store: ShelfStore
    @State private var duration: Double = 0
    @State private var start: Double = 0
    @State private var end: Double = 0
    @State private var error: String?
    private var valid: Bool { start.isFinite && end.isFinite && start >= 0 && end > start && end <= duration }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(String(localized: "Trim")).font(Typography.title).foregroundStyle(Color.acid)
            Text(request.item.name).font(Typography.body).lineLimit(1)
            if duration > 0 {
                rangeRow("Start", value: $start)
                rangeRow("End", value: $end)
                Text(valid ? Self.time(end - start) : String(localized: "Check the range"))
                    .font(Typography.body).foregroundStyle(valid ? Color.secondaryText : .coral)
            } else if let error { NotchiAttention(message: error, isError: true) }
            else { BouncingDots().accessibilityLabel(String(localized: "Reading duration")) }
            HStack {
                Button(String(localized: "Cancel")) { actions.mediaOptions = nil }.buttonStyle(NotchiButtonStyle(.secondary))
                Spacer()
                PillButton(title: String(localized: "Trim"), symbol: "scissors", tint: .acid, prominent: true) {
                    actions.confirmTrim(MediaRange(start: start, end: end), item: request.item, store: store)
                }.disabled(!valid)
            }
        }
        .padding(24).frame(width: 390).foregroundStyle(Color.paper).background(Color.ink).preferredColorScheme(.dark)
        .buttonStyle(NotchiButtonStyle()).textFieldStyle(NotchiTextFieldStyle()).tint(Color.acid)
        .task(id: request.id) {
            do { let info = try await FFmpegRunner.shared.inspect(request.item.url); duration = info.duration; end = duration }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
    private func rangeRow(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(Typography.button)
                Spacer()
                TextField(String(localized: "Seconds"), value: value, format: .number.precision(.fractionLength(2)))
                    .frame(width: 95).textFieldStyle(NotchiTextFieldStyle()).accessibilityLabel(String(localized: "\(title) seconds"))
            }
            NotchiSlider(value: value, range: 0...duration).tint(Color.acid).accessibilityLabel(String(localized: "\(title) range"))
        }
    }
    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        return String(format: "%d:%05.2f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
    }
}
