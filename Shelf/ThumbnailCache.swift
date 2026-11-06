import AppKit
import QuickLookThumbnailing

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSURL, NSImage>()
    init() { cache.countLimit = 100 }
    func image(for item: ShelfItem) async -> NSImage {
        if let image = cache.object(forKey: item.url as NSURL) { return image }
        let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 88, height: 72),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .all)
        let generated: NSImage? = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
                continuation.resume(returning: thumbnail?.nsImage)
            }
        }
        let image = generated ?? NSWorkspace.shared.icon(forFile: item.url.path)
        cache.setObject(image, forKey: item.url as NSURL)
        return image
    }
}
