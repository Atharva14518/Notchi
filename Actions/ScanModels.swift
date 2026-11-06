import Foundation
import CoreGraphics

enum ScanLook: String, CaseIterable, Sendable { case color = "Color", grayscale = "Grayscale", blackAndWhite = "B&W" }
struct DocumentQuad: Equatable, Sendable {
    var topLeft: CGPoint; var topRight: CGPoint; var bottomRight: CGPoint; var bottomLeft: CGPoint
    static let full = DocumentQuad(topLeft: CGPoint(x: 0, y: 1), topRight: CGPoint(x: 1, y: 1), bottomRight: CGPoint(x: 1, y: 0), bottomLeft: .zero)
}
struct OCRLine: Identifiable, Sendable {
    let id = UUID()
    var text: String
    var bounds: CGRect // Vision coordinates, normalized, origin at bottom-left.
    var confidence: Float
}
struct DetectedBarcode: Identifiable, Sendable {
    let id = UUID()
    var payload: String
    var symbology: String
    var bounds: CGRect
    var webURL: URL? {
        guard let components = URLComponents(string: payload.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil else { return nil }
        return components.url
    }
}
struct RecognitionPage: Identifiable, @unchecked Sendable {
    let id = UUID()
    let image: CGImage
    var lines: [OCRLine]
    var barcodes: [DetectedBarcode]
    var text: String { lines.map(\.text).joined(separator: "\n") }
}
struct RecognitionReport: Identifiable, @unchecked Sendable {
    let id = UUID()
    var pages: [RecognitionPage]
    var languageNotice: String?
    var text: String { pages.enumerated().compactMap { index, page -> String? in
        guard !page.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return pages.count > 1 ? String(localized: "Page \(index + 1)\n\(page.text)") : page.text
    }.joined(separator: "\n\n") }
}
struct ScanPage: Identifiable, @unchecked Sendable {
    let id: UUID
    let originalURL: URL
    let correctedURL: URL
    let originalPreview: CGImage
    let preview: CGImage
    let quad: DocumentQuad?
    var warning: String?
    var look: ScanLook
}
enum ScanInput: Sendable { case file(URL), data(Data) }
enum ScanMode: Sendable { case text, barcodes }
enum ScanError: LocalizedError {
    case unreadable, lowLight, emptyPDF, lockedPDF, tooManyPages, noText, noBarcode, exportFailed, recognitionTimedOut
    var errorDescription: String? {
        switch self {
        case .unreadable: return String(localized: "Couldn’t read that image. Try a PNG, JPG, HEIC, or PDF.")
        case .lowLight: return String(localized: "This photo is too dark to scan clearly. Try brighter light and keep the whole page in view.")
        case .emptyPDF: return String(localized: "That PDF has no readable pages. Try another copy.")
        case .lockedPDF: return String(localized: "That PDF is locked. Unlock it before scanning or reading its text.")
        case .tooManyPages: return String(localized: "Let’s scan up to 20 pages at a time. Split a larger document into smaller batches.")
        case .noText: return String(localized: "No readable text found. Try a sharper image with larger, well-lit text.")
        case .noBarcode: return String(localized: "No QR code or barcode found. Try a closer, sharper image.")
        case .exportFailed: return String(localized: "Couldn’t create the PDF. Your scan pages are still here—please try again.")
        case .recognitionTimedOut: return String(localized: "Text recognition took too long. Your pages are safe. Try again, or turn off Searchable text layer to create the PDF without OCR.")
        }
    }
}

/// Normalized Vision coordinates -> aspect-fit SwiftUI overlay coordinates.
enum ScanCoordinates {
    static func fittedRect(imageSize: CGSize, canvas: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(canvas.width / imageSize.width, canvas.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2, width: size.width, height: size.height)
    }
    static func box(_ normalized: CGRect, in imageRect: CGRect) -> CGRect {
        CGRect(x: imageRect.minX + normalized.minX * imageRect.width,
               y: imageRect.minY + (1 - normalized.maxY) * imageRect.height,
               width: normalized.width * imageRect.width, height: normalized.height * imageRect.height)
    }
    static func reordered<T: Identifiable>(_ values: [T], source: T.ID, target: T.ID) -> [T] {
        guard source != target, let from = values.firstIndex(where: { $0.id == source }), let to = values.firstIndex(where: { $0.id == target }) else { return values }
        var copy = values; let value = copy.remove(at: from); copy.insert(value, at: to); return copy
    }
}
