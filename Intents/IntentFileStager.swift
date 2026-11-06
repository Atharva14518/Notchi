import AppIntents
import Foundation

/// IntentFile may be a temporary security-scoped URL or in-memory data. Work
/// off MainActor and keep added files in app-owned storage after Shortcuts exits.
actor IntentFileStager {
    static let shared = IntentFileStager()
    let root: URL
    init(root: URL = ShelfLocations.imports.appendingPathComponent("Shortcuts", isDirectory: true)) { self.root = root }
    func stage(_ input: IntentFile) throws -> URL {
        try Task.checkCancellation()
        let name = (input.filename as NSString).lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", !name.contains("\0") else {
            throw ActionError.failed(String(localized: "That file has no usable name."))
        }
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let destination = folder.appendingPathComponent(name)
            if let source = input.fileURL {
                let scoped = source.startAccessingSecurityScopedResource()
                defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                guard source.isFileURL, FileManager.default.isReadableFile(atPath: source.path) else {
                    throw ActionError.failed(String(localized: "Shortcuts couldn’t read that file. Choose it again."))
                }
                try FileManager.default.copyItem(at: source, to: destination)
            } else {
                try input.data.write(to: destination, options: .atomic)
            }
            try Task.checkCancellation()
            return destination
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }
    func discard(_ url: URL) {
        let folder = url.deletingLastPathComponent()
        guard folder.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: folder)
    }
    func text(from url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
}
