import AppKit
import UniformTypeIdentifiers

struct ActionProgress: Sendable {
    var fraction: Double?
    var message: String
    var estimatedRemaining: TimeInterval? = nil
    typealias Reporter = AsyncStream<ActionProgress>.Continuation
}
struct ActionResult: Sendable {
    var outputs: [URL] = []
    var beforeBytes: Int64 = 0
    var afterBytes: Int64 = 0
    var message: String = "done."
    var hasSizeComparison = true
    var comparison: SizeComparison? { outputs.isEmpty || !hasSizeComparison ? nil : SizeComparison(before: beforeBytes, after: afterBytes) }
}
protocol Action: Identifiable, Sendable where ID == String {
    var id: String { get }
    var title: String { get }
    var icon: String { get }
    func isSupported(for item: ShelfItem) -> Bool
    func run(item: ShelfItem, progress: ActionProgress.Reporter) async throws -> ActionResult
}

enum NativeOperation: Sendable {
    case convert(ImageFormat), compressImage(QualityPreset), resize(ResizeSpec), stripMetadata
    case compressPDF(QualityPreset), mergePDFs([ShelfItem]), splitPDF, extractText
    case zip, copyPath, reveal
    case media(MediaOperation)
    case recognizeText, detectBarcodes
}

struct NativeFileAction: Action {
    let operation: NativeOperation
    var id: String {
        switch operation {
        case .recognizeText: return "ocr"
        case .detectBarcodes: return "detect-barcodes"
        case .media(let operation): return operation.id
        case .convert(let format): return "convert-\(format.rawValue)"
        case .compressImage: return "compress-image"
        case .resize: return "resize"
        case .stripMetadata: return "strip-metadata"
        case .compressPDF: return "compress-pdf"
        case .mergePDFs: return "merge-pdf"
        case .splitPDF: return "split-pdf"
        case .extractText: return "extract-text"
        case .zip: return "zip"
        case .copyPath: return "copy-path"
        case .reveal: return "reveal"
        }
    }
    var isMedia: Bool { if case .media = operation { return true }; return false }
    var title: String {
        switch operation {
        case .recognizeText: return String(localized: "read text")
        case .detectBarcodes: return String(localized: "QR / barcode")
        case .media(let operation): return operation.title
        case .convert: return "convert"
        case .compressImage, .compressPDF: return "compress"
        case .resize: return "resize"
        case .stripMetadata: return String(localized: "strip metadata")
        case .mergePDFs: return String(localized: "merge PDFs")
        case .splitPDF: return String(localized: "split pages")
        case .extractText: return String(localized: "extract text")
        case .zip: return "zip"
        case .copyPath: return String(localized: "copy path")
        case .reveal: return String(localized: "in Finder")
        }
    }
    var icon: String {
        switch operation {
        case .recognizeText: return "text.viewfinder"
        case .detectBarcodes: return "qrcode.viewfinder"
        case .media(let operation): return operation.icon
        case .convert: return "arrow.triangle.2.circlepath"
        case .compressImage, .compressPDF: return "arrow.down.right.and.arrow.up.left"
        case .resize: return "arrow.up.left.and.arrow.down.right"
        case .stripMetadata: return "eye.slash"
        case .mergePDFs: return "rectangle.stack.badge.plus"
        case .splitPDF: return "scissors"
        case .extractText: return "text.alignleft"
        case .zip: return "archivebox"
        case .copyPath: return "link"
        case .reveal: return "folder"
        }
    }
    func isSupported(for item: ShelfItem) -> Bool {
        switch operation {
        case .recognizeText, .detectBarcodes: return item.isImage || item.kind == .pdf
        case .media(let operation):
            switch operation {
            case .preset, .mute, .extract: return item.kind == .video
            case .convert(let format): return item.kind == .video || (item.kind == .audio && format.isAudio)
            case .compressAudio: return item.kind == .audio
            case .trim: return item.kind == .video || item.kind == .audio
            }
        case .convert(let format): return item.isImage && ImageFormat.supported.contains(format)
        case .compressImage, .resize, .stripMetadata: return item.isImage
        case .compressPDF, .splitPDF, .extractText: return item.kind == .pdf
        case .mergePDFs(let items): return item.kind == .pdf && items.count >= 2 && items.allSatisfy { $0.kind == .pdf }
        default: return true
        }
    }
    func run(item: ShelfItem, progress: ActionProgress.Reporter) async throws -> ActionResult {
        try await NativeActionWorker.shared.execute(self, item: item, progress: progress)
    }
}

enum ActionCatalog {
    static func actions(for item: ShelfItem, selected: [ShelfItem]) -> [NativeFileAction] {
        var operations: [NativeOperation] = []
        if item.isImage { operations = [.convert(.png), .compressImage(.balanced), .resize(.fraction(0.5)), .stripMetadata] }
        if item.kind == .pdf {
            operations = [.compressPDF(.balanced), .splitPDF, .extractText]
            if selected.filter({ $0.kind == .pdf }).count >= 2 { operations.insert(.mergePDFs(selected.filter { $0.kind == .pdf }), at: 1) }
        }
        if item.kind == .video {
            operations = VideoPreset.allCases.map { .media(.preset($0)) }
            operations += [MediaFormat.mp4, .mov, .gif, .webm].map { .media(.convert($0)) }
            operations += [MediaFormat.mp3, .m4a, .wav].map { .media(.extract($0)) }
            operations += [.media(.trim(nil)), .media(.mute)]
        }
        if item.kind == .audio {
            operations = [MediaFormat.mp3, .m4a, .wav, .flac].map { .media(.convert($0)) }
            operations += [.media(.compressAudio), .media(.trim(nil))]
        }
        if item.isImage || item.kind == .pdf { operations += [.recognizeText, .detectBarcodes] }
        operations += [.zip, .copyPath, .reveal]
        return operations.map(NativeFileAction.init)
    }
}
