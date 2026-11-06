import AppIntents

struct NotchiShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .lime
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenShelfIntent(), phrases: [
            "Open my shelf in \(.applicationName)", "Show my files in \(.applicationName)"
        ], shortTitle: "Open shelf", systemImageName: "tray")
        AppShortcut(intent: CompressFileIntent(), phrases: [
            "Compress my latest file with \(.applicationName)", "Make my latest file smaller with \(.applicationName)"
        ], shortTitle: "Compress latest", systemImageName: "arrow.down.right.and.arrow.up.left")
        AppShortcut(intent: ConvertFileIntent(), phrases: [
            "Convert my latest file with \(.applicationName)"
        ], shortTitle: "Convert latest", systemImageName: "arrow.triangle.2.circlepath")
        AppShortcut(intent: ExtractTextIntent(), phrases: [
            "Read my latest file with \(.applicationName)", "Extract text with \(.applicationName)"
        ], shortTitle: "Read latest", systemImageName: "text.viewfinder")
        AppShortcut(intent: OpenScanIntent(), phrases: [
            "Scan with \(.applicationName)", "Open the scanner in \(.applicationName)"
        ], shortTitle: "Scan", systemImageName: "doc.viewfinder")
        AppShortcut(intent: AddToShelfIntent(), phrases: [
            "Add files to \(.applicationName)"
        ], shortTitle: "Add files", systemImageName: "tray.and.arrow.down")
        AppShortcut(intent: ClearShelfIntent(), phrases: [
            "Clear my shelf in \(.applicationName)"
        ], shortTitle: "Clear shelf", systemImageName: "tray.badge.minus")
    }
}

/// Donate action patterns, never private filenames, URLs, file data or OCR text.
/// Donation is a suggestion, not a promise that Spotlight will rank it immediately.
/// Avoid suggesting destructive Clear Shelf automatically.
enum ShortcutDonations {
    static func record(_ action: NativeFileAction) async {
        switch action.operation {
        case .compressImage(let quality), .compressPDF(let quality):
            let intent = CompressFileIntent()
            intent.preset = quality == .tiny ? .tiny : (quality == .best ? .best : .balanced)
            _ = try? await intent.donate()
        case .convert(let format):
            let intent = ConvertFileIntent()
            switch format { case .png: intent.targetFormat = .png; case .jpeg: intent.targetFormat = .jpg; case .heic: intent.targetFormat = .heic; case .webp: intent.targetFormat = .webp }
            _ = try? await intent.donate()
        case .recognizeText, .extractText: _ = try? await ExtractTextIntent().donate()
        default: break
        }
    }
}
