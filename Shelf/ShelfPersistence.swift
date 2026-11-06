import Foundation

struct ShelfBookmark: Codable {
    var id: UUID
    var bookmark: Data
    var addedAt: Date
    var isNew: Bool
    var originalSize: Int64?
}

protocol ShelfPersistence {
    func read() throws -> [ShelfBookmark]
    func write(_ records: [ShelfBookmark]) throws
}

struct BookmarkShelfPersistence: ShelfPersistence {
    let url: URL
    init(url: URL = ShelfLocations.support.appendingPathComponent("shelf.json")) { self.url = url }
    func read() throws -> [ShelfBookmark] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([ShelfBookmark].self, from: Data(contentsOf: url))
    }
    func write(_ records: [ShelfBookmark]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(records).write(to: url, options: .atomic)
    }
}

final class MemoryShelfPersistence: ShelfPersistence {
    var records: [ShelfBookmark] = []
    func read() throws -> [ShelfBookmark] { records }
    func write(_ records: [ShelfBookmark]) throws { self.records = records }
}

enum ShelfLocations {
    static var support: URL {
        BrandMigration.supportFolder(in: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
    }
    static var imports: URL { support.appendingPathComponent("Imports", isDirectory: true) }
    static func importFolder(root: URL = imports) throws -> URL {
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
