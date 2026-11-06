import Foundation
import Vision
import CoreImage
import ImageIO
import PDFKit
import CoreText
import UniformTypeIdentifiers

/// Vision, Core Image, image decoding, PDF rendering and writing stay off MainActor.
actor ScanVisionWorker {
    static let shared = ScanVisionWorker()
    private let context = CIContext(options: [.cacheIntermediates: false])
    static let maximumPages = 20
    static let maximumDimension = 2200

    func importPages(_ inputs: [ScanInput], into folder: URL, look: ScanLook,
                     progress: ActionProgress.Reporter? = nil) async throws -> [ScanPage] {
        var pages: [ScanPage] = []
        for (index, input) in inputs.enumerated() {
            try Task.checkCancellation()
            let images = try load(input)
            guard pages.count + images.count <= Self.maximumPages else { throw ScanError.tooManyPages }
            for image in images {
                try Task.checkCancellation()
                progress?.yield(.init(fraction: Double(index) / Double(max(1, inputs.count)), message: String(localized: "finding page edges…")))
                let id = UUID(), pageFolder = folder.appendingPathComponent(id.uuidString)
                try FileManager.default.createDirectory(at: pageFolder, withIntermediateDirectories: true)
                let original = pageFolder.appendingPathComponent("original.png")
                try write(image, to: original)
                pages.append(try await process(image, id: id, original: original, folder: pageFolder, look: look))
            }
        }
        return pages
    }
    func restyle(_ page: ScanPage, look: ScanLook) throws -> ScanPage {
        try Task.checkCancellation()
        guard let image = try load(.file(page.originalURL)).first else { throw ScanError.unreadable }
        return try finish(image, id: page.id, original: page.originalURL,
                          folder: page.originalURL.deletingLastPathComponent(), look: look, quad: page.quad)
    }
    private func process(_ image: CGImage, id: UUID, original: URL, folder: URL, look: ScanLook) async throws -> ScanPage {
        if brightness(image) < 0.07 { throw ScanError.lowLight }
        let request = VNDetectDocumentSegmentationRequest()
        try await perform([request], image: image)
        let quad = request.results?.first.map {
            DocumentQuad(topLeft: $0.topLeft, topRight: $0.topRight, bottomRight: $0.bottomRight, bottomLeft: $0.bottomLeft)
        }
        return try finish(image, id: id, original: original, folder: folder, look: look, quad: quad)
    }
    private func finish(_ image: CGImage, id: UUID, original: URL, folder: URL, look: ScanLook, quad: DocumentQuad?) throws -> ScanPage {
        var output = CIImage(cgImage: image)
        if let quad {
            func vector(_ p: CGPoint) -> CIVector { CIVector(x: p.x * CGFloat(image.width), y: p.y * CGFloat(image.height)) }
            output = output.applyingFilter("CIPerspectiveCorrection", parameters: [
                "inputTopLeft": vector(quad.topLeft), "inputTopRight": vector(quad.topRight),
                "inputBottomLeft": vector(quad.bottomLeft), "inputBottomRight": vector(quad.bottomRight)])
        }
        output = output.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: look == .blackAndWhite ? 1.45 : 1.12,
            kCIInputSaturationKey: look == .color ? 1 : 0, kCIInputBrightnessKey: 0.025])
        if look == .blackAndWhite { output = output.applyingFilter("CIColorThreshold", parameters: ["inputThreshold": 0.57]) }
        guard let corrected = context.createCGImage(output, from: output.extent) else { throw ScanError.unreadable }
        let target = folder.appendingPathComponent("corrected-\(UUID().uuidString).png")
        try write(corrected, to: target)
        return ScanPage(id: id, originalURL: original, correctedURL: target,
            originalPreview: try thumbnail(image), preview: try thumbnail(corrected), quad: quad,
            warning: quad == nil ? String(localized: "No clear page edges found; using the full image. Try a contrasting background for a tighter crop.") : nil, look: look)
    }

    func recognize(_ input: ScanInput, mode: ScanMode = .text, progress: ActionProgress.Reporter? = nil) async throws -> RecognitionReport {
        let images = try load(input)
        var pages: [RecognitionPage] = [], notice: String?
        for (index, image) in images.enumerated() {
            try Task.checkCancellation()
            progress?.yield(.init(fraction: Double(index) / Double(max(1, images.count)), message: String(localized: "reading page \(index + 1)…")))
            let recognized = try await recognizeImage(image, mode: mode)
            notice = recognized.notice ?? notice
            pages.append(RecognitionPage(image: try thumbnail(image), lines: recognized.lines, barcodes: recognized.codes))
        }
        return RecognitionReport(pages: pages, languageNotice: notice)
    }
    private func recognizeImage(_ image: CGImage, mode: ScanMode,
                                progress: (@Sendable (Double) -> Void)? = nil) async throws -> (lines: [OCRLine], codes: [DetectedBarcode], notice: String?) {
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate; text.usesLanguageCorrection = true; text.automaticallyDetectsLanguage = true
        let supported = try text.supportedRecognitionLanguages()
        let preferred = ["en-US", "hi-IN"].filter { supported.contains($0) }
        text.recognitionLanguages = preferred.isEmpty ? [supported.first ?? "en-US"] : preferred
        text.progressHandler = { _, fraction, error in
            if error == nil { progress?(min(1, max(0, fraction))) }
        }
        let notice = supported.contains("hi-IN") ? nil : "Hindi OCR isn’t provided by Vision on this macOS version. English and other supported languages remain available."
        let barcode = VNDetectBarcodesRequest()
        try await perform(mode == .text ? [text, barcode] : [barcode], image: image)
        let lines = (text.results ?? []).compactMap { observation -> OCRLine? in
            guard let candidate = observation.topCandidates(1).first, !candidate.string.isEmpty else { return nil }
            return OCRLine(text: candidate.string, bounds: observation.boundingBox, confidence: candidate.confidence)
        }.sorted { a, b in abs(a.bounds.midY - b.bounds.midY) > 0.015 ? a.bounds.midY > b.bounds.midY : a.bounds.minX < b.bounds.minX }
        let codes = (barcode.results ?? []).compactMap { observation -> DetectedBarcode? in
            guard let value = observation.payloadStringValue else { return nil }
            return DetectedBarcode(payload: value, symbology: observation.symbology.rawValue, bounds: observation.boundingBox)
        }
        return (lines, codes, notice)
    }
    private func perform(_ requests: [VNRequest], image: CGImage) async throws {
        let execution = VisionCancellation(requests, image: image)
        try await ScanRequestExecution(operation: { try execution.perform() }, cancel: { execution.cancel() }).run()
    }

    func export(_ pages: [ScanPage], searchable: Bool, into folder: URL,
                progress: ActionProgress.Reporter? = nil) async throws -> URL {
        guard !pages.isEmpty else { throw ScanError.emptyPDF }
        let document = PDFDocument()
        for (index, page) in pages.enumerated() {
            try Task.checkCancellation()
            let label = String(localized: "page \(index + 1) of \(pages.count)")
            let weight = 0.95 / Double(pages.count), base = Double(index) * weight
            progress?.yield(.init(fraction: base, message: searchable ? String(localized: "reading text · \(label)…") : String(localized: "building PDF · \(label)…")))
            guard let image = try load(.file(page.correctedURL)).first else { throw ScanError.unreadable }
            let lines = searchable ? try await recognizeImage(image, mode: .text, progress: { fraction in
                progress?.yield(.init(fraction: base + fraction * weight * 0.85, message: String(localized: "reading text · \(label)…")))
            }).lines : []
            try Task.checkCancellation()
            progress?.yield(.init(fraction: base + weight * 0.9, message: String(localized: "building PDF · \(label)…")))
            let data = try pdfPage(image, lines: lines)
            guard let single = PDFDocument(data: data), let pdfPage = single.page(at: 0) else { throw ScanError.exportFailed }
            document.insert(pdfPage, at: document.pageCount)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let output = folder.appendingPathComponent("Scan.pdf")
        progress?.yield(.init(fraction: 0.98, message: String(localized: "saving PDF…")))
        guard document.write(to: output) else { throw ScanError.exportFailed }
        try Task.checkCancellation()
        progress?.yield(.init(fraction: 1, message: String(localized: "PDF ready!")))
        return output
    }
    func pdfPage(_ image: CGImage, lines: [OCRLine]) throws -> Data {
        let scale = min(1, 842 / CGFloat(max(image.width, image.height)))
        var bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data), let pdf = CGContext(consumer: consumer, mediaBox: &bounds, nil) else { throw ScanError.exportFailed }
        pdf.beginPDFPage(nil)
        pdf.draw(image, in: bounds)
        for line in lines where !line.text.isEmpty && line.bounds.width > 0 && line.bounds.height > 0 {
            let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
            let attributed = NSAttributedString(string: line.text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            let text = CTLineCreateWithAttributedString(attributed)
            let glyphs = CTLineGetBoundsWithOptions(text, [.useGlyphPathBounds])
            guard glyphs.width > 0, glyphs.height > 0 else { continue }
            let target = CGRect(x: line.bounds.minX * bounds.width, y: line.bounds.minY * bounds.height,
                                width: line.bounds.width * bounds.width, height: line.bounds.height * bounds.height)
            pdf.saveGState()
            let sx = target.width / glyphs.width, sy = target.height / glyphs.height
            pdf.translateBy(x: target.minX - glyphs.minX * sx, y: target.minY - glyphs.minY * sy)
            pdf.scaleBy(x: sx, y: sy); pdf.textMatrix = .identity; pdf.textPosition = .zero
            pdf.setTextDrawingMode(.invisible); CTLineDraw(text, pdf)
            pdf.restoreGState()
        }
        pdf.endPDFPage(); pdf.closePDF()
        return data as Data
    }

    private func load(_ input: ScanInput) throws -> [CGImage] {
        let data: Data
        switch input { case .file(let url): data = try Data(contentsOf: url, options: .mappedIfSafe); case .data(let bytes): data = bytes }
        if data.starts(with: Data("%PDF".utf8)) {
            guard let pdf = PDFDocument(data: data) else { throw ScanError.emptyPDF }
            guard !pdf.isLocked else { throw ScanError.lockedPDF }
            guard pdf.pageCount > 0 else { throw ScanError.emptyPDF }
            guard pdf.pageCount <= Self.maximumPages else { throw ScanError.tooManyPages }
            return try (0..<pdf.pageCount).map { index in
                guard let page = pdf.page(at: index), let reference = page.pageRef else { throw ScanError.emptyPDF }
                var bounds = reference.getBoxRect(.mediaBox)
                if abs(reference.rotationAngle % 180) == 90 { bounds.size = CGSize(width: bounds.height, height: bounds.width) }
                guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { throw ScanError.emptyPDF }
                let scale = min(2, CGFloat(Self.maximumDimension) / max(bounds.width, bounds.height))
                let width = max(1, Int(bounds.width * scale)), height = max(1, Int(bounds.height * scale))
                guard let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ScanError.unreadable }
                bitmap.setFillColor(CGColor(gray: 1, alpha: 1)); bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
                bitmap.concatenate(reference.getDrawingTransform(.mediaBox, rect: CGRect(x: 0, y: 0, width: width, height: height), rotate: 0, preserveAspectRatio: true))
                bitmap.drawPDFPage(reference)
                for annotation in page.annotations where annotation.shouldDisplay { annotation.draw(with: .mediaBox, in: bitmap) }
                guard let image = bitmap.makeImage() else { throw ScanError.unreadable }; return image
            }
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: Self.maximumDimension] as CFDictionary) else { throw ScanError.unreadable }
        return [image]
    }
    private func thumbnail(_ image: CGImage) throws -> CGImage {
        let scale = min(1, 720 / CGFloat(max(image.width, image.height)))
        let ci = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let result = context.createCGImage(ci, from: ci.extent) else { throw ScanError.unreadable }; return result
    }
    private func brightness(_ image: CGImage) -> Double {
        let average = CIImage(cgImage: image).applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: CGRect(x: 0, y: 0, width: image.width, height: image.height))])
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(average, toBitmap: &bytes, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return (Double(bytes[0]) + Double(bytes[1]) + Double(bytes[2])) / (3 * 255)
    }
    private func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw ScanError.unreadable }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ScanError.unreadable }
    }
    func removeFolder(_ url: URL) { try? FileManager.default.removeItem(at: url) }
}
private final class VisionCancellation: @unchecked Sendable {
    let requests: [VNRequest]
    let image: CGImage
    init(_ requests: [VNRequest], image: CGImage) { self.requests = requests; self.image = image }
    func perform() throws { try VNImageRequestHandler(cgImage: image, options: [:]).perform(requests) }
    func cancel() { requests.forEach { $0.cancel() } }
}
