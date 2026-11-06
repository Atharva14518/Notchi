import AppKit
import ImageIO

/// Serial background isolation keeps PDFKit objects and CPU-heavy decoding off the UI executor.
actor NativeActionWorker {
    static let shared = NativeActionWorker()
    func execute(_ action: NativeFileAction, item: ShelfItem, progress: ActionProgress.Reporter) async throws -> ActionResult {
        guard action.isSupported(for: item) else { throw ActionError.failed(String(localized: "That action doesn’t work with this file.")) }
        guard FileManager.default.fileExists(atPath: item.url.path) else { throw ActionError.failed(String(localized: "The original file moved or went offline. Drop it again, then retry.")) }
        if case .media(let operation) = action.operation {
            return try await MediaActionWorker.shared.execute(operation, item: item, progress: progress)
        }
        progress.yield(ActionProgress(fraction: nil, message: String(localized: "getting ready…")))
        if case .copyPath = action.operation {
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
            return ActionResult(message: String(localized: "path copied."))
        }
        if case .reveal = action.operation {
            await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            return ActionResult(message: String(localized: "there it is."))
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Notchi/Results/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let stem = item.url.deletingPathExtension().lastPathComponent
            var outputs: [URL] = []
            var before = item.size ?? 0
            func output(_ suffix: String, _ ext: String) -> URL { folder.appendingPathComponent(stem + suffix + "." + ext) }
            switch action.operation {
            case .recognizeText, .detectBarcodes:
                let mode: ScanMode
                if case .recognizeText = action.operation { mode = .text } else { mode = .barcodes }
                let recognized = try await ScanVisionWorker.shared.recognize(.file(item.url), mode: mode, progress: progress)
                let text = mode == .text ? recognized.text : recognized.pages.flatMap(\.barcodes).map(\.payload).joined(separator: "\n")
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw mode == .text ? ScanError.noText : ScanError.noBarcode }
                let target = output(mode == .text ? "-ocr" : "-codes", "txt")
                try Data(text.utf8).write(to: target); outputs = [target]
            case .convert(let format):
                let target = output("", format.fileExtension)
                progress.yield(.init(fraction: 0.2, message: String(localized: "converting to \(format.rawValue)…")))
                try ImageConversion.process(source: item.url, destination: target, format: format)
                outputs = [target]
            case .compressImage(let quality):
                let target = output("-\(quality.rawValue.lowercased())", "jpg")
                progress.yield(.init(fraction: 0.2, message: String(localized: "making it \(quality.rawValue.lowercased())…")))
                try ImageConversion.process(source: item.url, destination: target, format: .jpeg,
                    quality: quality.quality, resize: .maxDimension(quality.maxDimension))
                outputs = [target]
            case .resize(let spec):
                let target = output("-resized", "png")
                progress.yield(.init(fraction: 0.2, message: String(localized: "resizing…")))
                try ImageConversion.process(source: item.url, destination: target, format: .png, resize: spec)
                outputs = [target]
            case .stripMetadata:
                let target = output("-clean", "png")
                progress.yield(.init(fraction: 0.2, message: String(localized: "removing EXIF and GPS…")))
                try ImageConversion.process(source: item.url, destination: target, format: .png, stripMetadata: true)
                outputs = [target]
            case .compressPDF(let quality):
                let target = output("-compressed", "pdf")
                try PDFActions.compress(item.url, destination: target, quality: quality, progress: progress)
                outputs = [target]
            case .mergePDFs(let items):
                let target = folder.appendingPathComponent("Merged.pdf")
                try PDFActions.merge(items.map(\.url), destination: target, progress: progress)
                before = items.reduce(0) { $0 + ($1.size ?? 0) }
                outputs = [target]
            case .splitPDF:
                outputs = try PDFActions.split(item.url, folder: folder, progress: progress)
            case .extractText:
                let target = output("-text", "txt")
                try PDFActions.extractText(item.url, destination: target, progress: progress)
                outputs = [target]
            case .zip:
                let target = output("", "zip")
                progress.yield(.init(fraction: nil, message: String(localized: "zipping…")))
                try Compression.archive(urls: [item.url], destination: target)
                outputs = [target]
            case .copyPath, .reveal, .media: break
            }
            let after = try outputs.reduce(Int64(0)) { total, url in
                total + Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            }
            progress.yield(.init(fraction: 1, message: String(localized: "done.")))
            return ActionResult(outputs: outputs, beforeBytes: before, afterBytes: after, hasSizeComparison: !item.isDirectory)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
}
