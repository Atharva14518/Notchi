import Foundation
import PDFKit
import ImageIO
import UniformTypeIdentifiers

enum PDFActions {
    private static func open(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else {
            throw ActionError.failed(String(localized: "This PDF is locked or couldn’t be opened. Unlock it and try again."))
        }
        return document
    }
    static func compress(_ source: URL, destination: URL, quality: QualityPreset, progress: ActionProgress.Reporter) throws {
        let document = try open(source)
        guard let output = CGContext(destination as CFURL, mediaBox: nil, nil) else { throw ActionError.failed(String(localized: "Couldn’t create the new PDF.")) }
        defer { output.closePDF() }
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index), let reference = page.pageRef else { throw ActionError.failed(String(localized: "One PDF page couldn’t be read.")) }
            var bounds = reference.getBoxRect(.mediaBox)
            if abs(reference.rotationAngle % 180) == 90 { bounds.size = CGSize(width: bounds.height, height: bounds.width) }
            guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
                throw ActionError.failed(String(localized: "A PDF page has invalid dimensions."))
            }
            let scale = min(2, CGFloat(quality.maxDimension) / max(bounds.width, bounds.height))
            let width = max(1, Int(bounds.width * scale)), height = max(1, Int(bounds.height * scale))
            guard let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                throw ActionError.failed(String(localized: "That page is too large to render."))
            }
            bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
            bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
            bitmap.concatenate(reference.getDrawingTransform(.mediaBox, rect: CGRect(x: 0, y: 0, width: width, height: height), rotate: 0, preserveAspectRatio: true))
            bitmap.drawPDFPage(reference)
            for annotation in page.annotations where annotation.shouldDisplay {
                annotation.draw(with: .mediaBox, in: bitmap)
            }
            guard let image = bitmap.makeImage() else { throw ActionError.failed(String(localized: "Couldn’t render a PDF page.")) }
            let jpeg = NSMutableData()
            guard let encoder = CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil) else { throw ActionError.failed(String(localized: "Couldn’t compress a PDF page.")) }
            CGImageDestinationAddImage(encoder, image, [kCGImageDestinationLossyCompressionQuality: quality.quality] as CFDictionary)
            guard CGImageDestinationFinalize(encoder), let provider = CGDataProvider(data: jpeg),
                  let compressed = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
                throw ActionError.failed(String(localized: "Couldn’t encode a PDF page."))
            }
            var box = CGRect(origin: .zero, size: bounds.size)
            let media = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
            output.beginPDFPage([kCGPDFContextMediaBox: media] as CFDictionary)
            output.draw(compressed, in: box)
            output.endPDFPage()
            progress.yield(.init(fraction: Double(index + 1) / Double(document.pageCount), message: String(localized: "page \(index + 1) of \(document.pageCount)")))
        }
    }
    static func merge(_ urls: [URL], destination: URL, progress: ActionProgress.Reporter) throws {
        guard urls.count >= 2 else { throw ActionError.failed(String(localized: "Select at least two PDFs with ⌘-click.")) }
        let output = PDFDocument()
        for (index, url) in urls.enumerated() {
            let document = try open(url)
            for p in 0..<document.pageCount {
                guard let page = document.page(at: p)?.copy() as? PDFPage else { throw ActionError.failed(String(localized: "One PDF page couldn’t be copied.")) }
                output.insert(page, at: output.pageCount)
            }
            progress.yield(.init(fraction: Double(index + 1) / Double(urls.count), message: String(localized: "merging PDF \(index + 1)…")))
        }
        guard output.write(to: destination) else { throw ActionError.failed(String(localized: "Couldn’t save the merged PDF.")) }
    }
    static func split(_ source: URL, folder: URL, progress: ActionProgress.Reporter) throws -> [URL] {
        let document = try open(source)
        var outputs: [URL] = []
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index)?.copy() as? PDFPage else { throw ActionError.failed(String(localized: "One PDF page couldn’t be copied.")) }
            let output = PDFDocument()
            output.insert(page, at: 0)
            let url = folder.appendingPathComponent(String(format: String(localized: "Page %03d.pdf"), index + 1))
            guard output.write(to: url) else { throw ActionError.failed(String(localized: "Couldn’t save a split page.")) }
            outputs.append(url)
            progress.yield(.init(fraction: Double(index + 1) / Double(document.pageCount), message: String(localized: "splitting page \(index + 1)…")))
        }
        return outputs
    }
    static func extractText(_ source: URL, destination: URL, progress: ActionProgress.Reporter) throws {
        let document = try open(source)
        var pages: [String] = []
        for index in 0..<document.pageCount {
            pages.append(document.page(at: index)?.string ?? "")
            progress.yield(.init(fraction: Double(index + 1) / Double(document.pageCount), message: String(localized: "reading page \(index + 1)…")))
        }
        let text = pages.joined(separator: "\n\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ActionError.failed(String(localized: "This PDF has no selectable text. Scanned pages need OCR first."))
        }
        try text.write(to: destination, atomically: true, encoding: .utf8)
    }
}
