import SwiftUI

struct ActionOptionsSheet: View {
    let request: ActionOptionsRequest
    @ObservedObject var actions: ActionCoordinator
    @ObservedObject var store: ShelfStore
    @State private var format: ImageFormat = .png
    @State private var quality: QualityPreset = .balanced
    @State private var resizeChoice = "50%"
    @State private var dimension = 1600

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(request.action.title).font(Typography.title).foregroundStyle(Color.acid)
            Text(request.item.name).font(Typography.body).lineLimit(1).truncationMode(.middle)
            switch request.action.operation {
            case .convert:
                NotchiPicker(String(localized: "Format"), selection: $format, options: ImageFormat.supported.map { NotchiOption($0, $0.rawValue) })
                NotchiInfo(text: String(localized: "macOS formats only."))
            case .compressImage, .compressPDF:
                NotchiSegmented(String(localized: "Quality"), selection: $quality, options: QualityPreset.allCases.map { NotchiOption($0, $0.rawValue) })
                HStack { Text(quality.detail).font(Typography.mono).foregroundStyle(Color.secondaryText); NotchiInfo(text: compressionNote) }
            case .resize:
                NotchiSegmented(String(localized: "Size"), selection: $resizeChoice, options: ["25%", "50%", "Custom"].map { NotchiOption($0, $0) })
                if resizeChoice == "Custom" {
                    TextField(String(localized: "Pixels"), value: $dimension, format: .number.grouping(.never))
                    NotchiInfo(text: String(localized: "1–20,000 px. Preserves proportions."))
                }
            default: EmptyView()
            }
            HStack {
                Button(String(localized: "Cancel")) { actions.options = nil }.buttonStyle(NotchiButtonStyle(.secondary))
                Spacer()
                PillButton(title: String(localized: "Apply"), symbol: "arrow.right", tint: .acid, prominent: true) {
                    let resize: ResizeSpec = resizeChoice == "Custom" ? .maxDimension(dimension)
                        : .fraction(resizeChoice == "25%" ? 0.25 : 0.5)
                    actions.confirm(format: format, quality: quality, resize: resize, store: store)
                }
                .disabled(resizeChoice == "Custom" && !(1...20000).contains(dimension))
            }
        }
        .onAppear {
            format = SettingsStore.shared.imageFormat
            quality = SettingsStore.shared.compressionPreset
        }
        .padding(24).frame(width: 390)
        .foregroundStyle(Color.paper).background(Color.ink).preferredColorScheme(.dark)
        .buttonStyle(NotchiButtonStyle()).textFieldStyle(NotchiTextFieldStyle()).tint(Color.acid)
    }
    private var compressionNote: String {
        if case .compressPDF = request.action.operation {
            return String(localized: "Raster PDF; text and forms flatten.")
        }
        return String(localized: "JPG; transparency becomes white.")
    }
}
