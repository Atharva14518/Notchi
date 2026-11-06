import AppIntents
import Foundation

struct ShelfItemEntity: AppEntity, Sendable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Shelf file"
    static var defaultQuery = ShelfItemQuery()
    let id: UUID
    let name: String
    let detail: String
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(detail)", image: .init(systemName: "doc"))
    }
    init(_ item: ShelfItem) { id = item.id; name = item.name; detail = item.detail }
}

/// Stable bookmark UUIDs, never filenames or an arbitrary file path supplied by Siri.
/// Resolve again at execution time so removed/offline cards are not silently reused.
struct ShelfItemQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [ShelfItemEntity] {
        await IntentRuntime.current.entities(identifiers: identifiers)
    }
    func suggestedEntities() async throws -> [ShelfItemEntity] {
        await IntentRuntime.current.entities()
    }
    func entities(matching string: String) async throws -> [ShelfItemEntity] {
        await IntentRuntime.current.entities(matching: string)
    }
}

enum ShortcutCompressionPreset: String, AppEnum {
    case tiny, balanced, best
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Quality"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .tiny: "Tiny", .balanced: "Balanced", .best: "Best"
    ]
    var quality: QualityPreset {
        switch self { case .tiny: return .tiny; case .balanced: return .balanced; case .best: return .best }
    }
}

enum ShortcutTargetFormat: String, AppEnum {
    case png, jpg, heic, webp, mp4, mov, gif, webm, mp3, m4a, wav, flac
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Format"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .png: "PNG", .jpg: "JPG", .heic: "HEIC", .webp: "WebP", .mp4: "MP4", .mov: "MOV",
        .gif: "GIF", .webm: "WebM", .mp3: "MP3", .m4a: "M4A", .wav: "WAV", .flac: "FLAC"
    ]
    var imageFormat: ImageFormat? {
        switch self { case .png: return .png; case .jpg: return .jpeg; case .heic: return .heic; case .webp: return .webp; default: return nil }
    }
    var mediaFormat: MediaFormat? { MediaFormat(rawValue: rawValue) }
}
