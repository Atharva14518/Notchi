import AppIntents
import UniformTypeIdentifiers

struct CompressFileIntent: AppIntent, ProgressReportingIntent {
    static var title: LocalizedStringResource = "Compress File"
    static var description = IntentDescription("Compress an input file or a shelf file. With neither selected, use the latest shelf file. Images/PDFs use Tiny, Balanced or Best; other documents become ZIP archives.", categoryName: "Files")
    static var openAppWhenRun = false
    @Parameter(title: "Input file") var file: IntentFile?
    @Parameter(title: "Shelf file") var shelfFile: ShelfItemEntity?
    @Parameter(title: "Preset", default: .balanced) var preset: ShortcutCompressionPreset
    static var parameterSummary: some ParameterSummary {
        Summary("Compress \(\.$shelfFile) with \(\.$preset)") { \.$file }
    }
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let runtime = await IntentRuntime.current
        let progress = self.progress
        progress.totalUnitCount = 100
        let result = try await runtime.perform(file: file, shelfFile: shelfFile, operation: {
            IntentRuntime.compression(for: $0, preset: preset)
        }, progress: { update in
            if let fraction = update.fraction { progress.completedUnitCount = Int64(fraction * 100) }
        })
        progress.completedUnitCount = 100
        return .result(value: try outputFile(result))
    }
}

struct ConvertFileIntent: AppIntent, ProgressReportingIntent {
    static var title: LocalizedStringResource = "Convert File"
    static var description = IntentDescription("Convert an input file or a shelf file. Leave both empty to use the latest card. Images and media use the same formats and engines as the shelf.", categoryName: "Files")
    static var openAppWhenRun = false
    @Parameter(title: "Input file") var file: IntentFile?
    @Parameter(title: "Shelf file") var shelfFile: ShelfItemEntity?
    @Parameter(title: "Format", default: .png) var targetFormat: ShortcutTargetFormat
    static var parameterSummary: some ParameterSummary {
        Summary("Convert \(\.$shelfFile) to \(\.$targetFormat)") { \.$file }
    }
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let runtime = await IntentRuntime.current
        let progress = self.progress
        progress.totalUnitCount = 100
        let result = try await runtime.perform(file: file, shelfFile: shelfFile, operation: {
            try IntentRuntime.conversion(for: $0, format: targetFormat)
        }, progress: { update in
            if let fraction = update.fraction { progress.completedUnitCount = Int64(fraction * 100) }
        })
        progress.completedUnitCount = 100
        return .result(value: try outputFile(result))
    }
}

struct AddToShelfIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Shelf"
    static var description = IntentDescription("Add files from Shortcuts to the shelf without opening the panel. Incoming temporary files are retained as app-owned imports.", categoryName: "Shelf")
    static var openAppWhenRun = false
    @Parameter(title: "Files") var files: [IntentFile]
    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$files) to the shelf") }
    func perform() async throws -> some IntentResult & ReturnsValue<[ShelfItemEntity]> {
        .result(value: try await IntentRuntime.current.add(files))
    }
}

struct OpenShelfIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Shelf"
    static var description = IntentDescription("Open and pin the notch shelf.", categoryName: "Shelf")
    static var openAppWhenRun = true
    static var parameterSummary: some ParameterSummary { Summary("Open the shelf") }
    func perform() async throws -> some IntentResult {
        await IntentRuntime.current.openShelf()
        return .result()
    }
}

struct ExtractTextIntent: AppIntent, ProgressReportingIntent {
    static var title: LocalizedStringResource = "Extract Text"
    static var description = IntentDescription("Read text from an image or PDF with on-device Vision OCR. Leave file choices empty to read the latest shelf card. English and Hindi depend on this macOS version’s Vision support.", categoryName: "Files")
    static var openAppWhenRun = false
    @Parameter(title: "Input file") var file: IntentFile?
    @Parameter(title: "Shelf file") var shelfFile: ShelfItemEntity?
    static var parameterSummary: some ParameterSummary { Summary("Extract text from \(\.$shelfFile)") { \.$file } }
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let runtime = await IntentRuntime.current
        let progress = self.progress
        progress.totalUnitCount = 100
        let result = try await runtime.perform(file: file, shelfFile: shelfFile,
            operation: { _ in NativeFileAction(operation: .recognizeText) }, progress: { update in
                if let fraction = update.fraction { progress.completedUnitCount = Int64(fraction * 100) }
            })
        let text = try await runtime.text(from: result)
        progress.completedUnitCount = 100
        return .result(value: text)
    }
}

struct ClearShelfIntent: AppIntent {
    static var title: LocalizedStringResource = "Clear Shelf"
    static var description = IntentDescription("Remove all shelf cards and saved references. Original files on disk remain untouched.", categoryName: "Shelf")
    static var openAppWhenRun = false
    static var parameterSummary: some ParameterSummary { Summary("Clear the shelf") }
    func perform() async throws -> some IntentResult {
        try await IntentRuntime.current.clear()
        return .result()
    }
}

/// Scan is deliberately foreground-only: choosing a camera, files or capture area
/// needs the real workspace. OCR and file transforms above remain headless.
struct OpenScanIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Scanner"
    static var description = IntentDescription("Open the scanner’s source chooser.", categoryName: "Scanning")
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        await IntentRuntime.current.openScan()
        return .result()
    }
}

private func outputFile(_ result: ActionResult) throws -> IntentFile {
    guard let url = result.outputs.first else { throw ActionError.failed(String(localized: "No output file was created.")) }
    var output = IntentFile(fileURL: url, filename: url.lastPathComponent, type: UTType(filenameExtension: url.pathExtension))
    // The result also has a shelf bookmark and may be read asynchronously by
    // later Shortcuts actions. Never ask App Intents to delete it on completion.
    output.removedOnCompletion = false
    return output
}
