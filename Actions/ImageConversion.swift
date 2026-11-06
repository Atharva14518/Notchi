import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageFormat: String, CaseIterable, Sendable {
    case png = "PNG", jpeg = "JPG", heic = "HEIC", webp = "WebP"
    var contentType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .webp: return .webP
        }
    }
    var fileExtension: String {
        switch self { case .png: return "png"; case .jpeg: return "jpg"; case .heic: return "heic"; case .webp: return "webp" }
    }
    static var supported: [ImageFormat] {
        let identifiers = CGImageDestinationCopyTypeIdentifiers() as! [String]
        return allCases.filter { identifiers.contains($0.contentType.identifier) }
    }
}

enum QualityPreset: String, CaseIterable, Sendable, Identifiable {
    case tiny = "Tiny", balanced = "Balanced", best = "Best"
    var id: Self { self }
    var quality: Double { switch self { case .tiny: return 0.32; case .balanced: return 0.65; case .best: return 0.9 } }
    var maxDimension: Int { switch self { case .tiny: return 1280; case .balanced: return 2560; case .best: return 4096 } }
    var detail: String { String(localized: "\(Int(quality * 100))% · \(maxDimension) px") }
}

enum ResizeSpec: Sendable {
    case fraction(Double), maxDimension(Int)
}

enum ImageConversion {
    static func convert(source: URL, destination: URL, format: ImageFormat) throws {
        try process(source: source, destination: destination, format: format)
    }
    static func process(source: URL, destination: URL, format: ImageFormat, quality: Double = 0.9,
                        resize: ResizeSpec? = nil, stripMetadata: Bool = false) throws {
        guard ImageFormat.supported.contains(format) else { throw ActionError.failed("macOS can’t encode \(format.rawValue) on this Mac.") }
        guard let input = CGImageSourceCreateWithURL(source as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let original = CGImageSourceCopyPropertiesAtIndex(input, 0, nil) as? [CFString: Any],
              let width = original[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = original[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw ActionError.failed(String(localized: "This image couldn’t be opened. Try another file."))
        }
        let longest = max(width.intValue, height.intValue)
        guard longest > 0 else { throw ActionError.failed(String(localized: "This image has no readable pixels.")) }
        var limit = longest
        switch resize {
        case .fraction(let fraction):
            guard fraction > 0, fraction <= 1 else { throw ActionError.failed(String(localized: "Choose a resize percentage between 1 and 100.")) }
            limit = max(1, Int(Double(longest) * fraction))
        case .maxDimension(let dimension):
            guard (1...20000).contains(dimension) else { throw ActionError.failed("Use a maximum dimension from 1 to 20,000 pixels.") }
            limit = min(longest, dimension)
        case nil: break
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: limit,
            kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(input, 0, options as CFDictionary),
              let output = CGImageDestinationCreateWithURL(destination as CFURL,
                  format.contentType.identifier as CFString, 1, nil) else {
            throw ActionError.failed(String(localized: "macOS couldn’t prepare the image export."))
        }
        var properties: [CFString: Any] = stripMetadata ? [:] : original
        if stripMetadata {
            properties[kCGImageDestinationMetadata] = CGImageMetadataCreateMutable()
            properties[kCGImageDestinationMergeMetadata] = false
            properties[kCGImagePropertyExifDictionary] = [:] as [String: Any]
            properties[kCGImagePropertyGPSDictionary] = [:] as [String: Any]
            properties[kCGImagePropertyTIFFDictionary] = [:] as [String: Any]
            properties[kCGImageMetadataShouldExcludeGPS] = true
            properties[kCGImageMetadataShouldExcludeXMP] = true
        }
        // The decoded pixels already have their display orientation baked in.
        // A clean export needs no EXIF/TIFF orientation tag at all.
        if !stripMetadata {
            properties[kCGImagePropertyOrientation] = 1
            properties[kCGImagePropertyPixelWidth] = image.width
            properties[kCGImagePropertyPixelHeight] = image.height
            if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiff[kCGImagePropertyTIFFOrientation] = 1
                properties[kCGImagePropertyTIFFDictionary] = tiff
            }
            if var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                exif[kCGImagePropertyExifPixelXDimension] = image.width
                exif[kCGImagePropertyExifPixelYDimension] = image.height
                properties[kCGImagePropertyExifDictionary] = exif
            }
        }
        properties[kCGImageDestinationLossyCompressionQuality] = min(1, max(0, quality))
        properties[kCGImageDestinationBackgroundColor] = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        properties[kCGImageDestinationEmbedThumbnail] = false
        CGImageDestinationAddImage(output, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(output) else {
            try? FileManager.default.removeItem(at: destination)
            throw ActionError.failed(String(localized: "That image couldn’t be encoded. Try PNG or JPG instead."))
        }
        // ImageIO generates a basic eXIf block even with explicitly empty metadata.
        // The public strip action exports PNG, so remove those complete chunks
        // without touching its compressed pixels or color-management data.
        if stripMetadata && format == .png { try PNGMetadataStripper.strip(at: destination) }
    }
}
