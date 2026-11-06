import Foundation

actor LinkUploadStore {
    static let shared = LinkUploadStore()
    let root: URL
    init(root: URL = ShelfLocations.support.appendingPathComponent("LinkUploads", isDirectory: true)) { self.root = root }
    func stage(_ source: URL) throws -> URL {
        let scope = source.startAccessingSecurityScopedResource()
        defer { if scope { source.stopAccessingSecurityScopedResource() } }
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let values = try source.resourceValues(forKeys: [.isDirectoryKey])
            let target = folder.appendingPathComponent(source.lastPathComponent + (values.isDirectory == true ? ".zip" : ""))
            if values.isDirectory == true { try Compression.archive(urls: [source], destination: target) }
            else { try FileManager.default.copyItem(at: source, to: target) }
            try Task.checkCancellation()
            return target
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }
    func size(_ url: URL) throws -> Int64 { Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
    func read() throws -> [PendingLinkUpload] {
        let file = root.appendingPathComponent("jobs.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try JSONDecoder().decode([PendingLinkUpload].self, from: Data(contentsOf: file))
    }
    func save(_ jobs: [PendingLinkUpload]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(jobs).write(to: root.appendingPathComponent("jobs.json"), options: [.atomic, .completeFileProtectionUnlessOpen])
    }
    func discard(_ file: URL) {
        guard file.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }
}
