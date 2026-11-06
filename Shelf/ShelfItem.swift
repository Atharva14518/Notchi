import Foundation
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case image, video, audio, pdf, doc, other }
    let id: UUID
    let url: URL
    let type: UTType
    let size: Int64?
    let kind: Kind
    let addedAt: Date
    let isDirectory: Bool
    var isNew: Bool
    var originalSize: Int64?

    init(url: URL, id: UUID = UUID(), addedAt: Date = Date(), isNew: Bool = false, originalSize: Int64? = nil) {
        self.id = id
        self.url = url.standardizedFileURL
        self.addedAt = addedAt
        self.isNew = isNew
        self.originalSize = originalSize
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .contentTypeKey])
        isDirectory = values?.isDirectory ?? false
        size = isDirectory ? nil : values?.fileSize.map(Int64.init)
        type = values?.contentType ?? UTType(filenameExtension: url.pathExtension) ?? .data
        if type.conforms(to: .image) { kind = .image }
        else if !isDirectory && (type.conforms(to: .movie) || ["mp4", "mov", "m4v", "webm", "mkv", "avi", "mts", "m2ts"].contains(url.pathExtension.lowercased())) { kind = .video }
        else if !isDirectory && (type.conforms(to: .audio) || ["mp3", "m4a", "wav", "flac", "aiff", "aif", "ogg", "opus", "aac"].contains(url.pathExtension.lowercased())) { kind = .audio }
        else if type.conforms(to: .pdf) { kind = .pdf }
        else if type.conforms(to: .text) || type.conforms(to: .content) && !isDirectory { kind = .doc }
        else { kind = .other }
    }
    var name: String { url.lastPathComponent }
    var isImage: Bool { kind == .image }
    var detail: String {
        if isDirectory { return String(localized: "Folder") }
        guard let size else { return type.preferredFilenameExtension?.uppercased() ?? String(localized: "File") }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    var savings: SizeComparison? {
        guard let before = originalSize, let after = size else { return nil }
        return SizeComparison(before: before, after: after)
    }
}

struct SizeComparison: Equatable, Sendable {
    var before: Int64
    var after: Int64
    var saved: Int64 { max(0, before - after) }
    var percent: Int { before > 0 ? Int((max(0, 1 - Double(after) / Double(before)) * 100).rounded()) : 0 }
    var description: String {
        let a = ByteCountFormatter.string(fromByteCount: before, countStyle: .file)
        let b = ByteCountFormatter.string(fromByteCount: after, countStyle: .file)
        return "\(a) → \(b)" + (after < before ? String(localized: ", \(percent)% smaller") : (after > before ? String(localized: ", larger") : String(localized: ", same size")))
    }
}
