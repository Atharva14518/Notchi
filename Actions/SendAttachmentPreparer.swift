import Foundation

struct PreparedSendFiles: Sendable {
    let folder: URL
    let urls: [URL]
}

/// Recipients receive disposable copies, never the shelf's originals. Keep the
/// copies after closing the tray/quit because other apps may read URLs later.
actor SendAttachmentPreparer {
    private let root: URL
    init(root: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Notchi/SendAttachments", isDirectory: true)) { self.root = root }

    func prepare(_ sources: [URL], zipFolders: Bool = false, archiveAll: Bool = false,
                 maximumBytes: Int64? = nil) throws -> PreparedSendFiles {
        guard !sources.isEmpty else { throw ActionError.failed(String(localized: "Choose a file first.")) }
        let manager = FileManager.default
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        var scoped: [URL] = []
        defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
        do {
            for source in sources {
                try Task.checkCancellation()
                guard source.isFileURL else { throw ActionError.failed(String(localized: "Add this file to the shelf before sharing it.")) }
                if source.startAccessingSecurityScopedResource() { scoped.append(source) }
                guard manager.isReadableFile(atPath: source.path) else {
                    throw ActionError.failed(String(localized: "\(source.lastPathComponent) moved or can’t be read. Add it again, then retry."))
                }
                let values = try source.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                if !archiveAll, values.isDirectory != true { try checkSize(Int64(values.fileSize ?? 0), maximum: maximumBytes) }
            }
            var outputs: [URL] = []
            if archiveAll {
                let target = folder.appendingPathComponent(String(localized: "\(AppConfig.appName) Files.zip"))
                try Compression.archive(urls: sources, destination: target)
                outputs = [target]
            } else {
                for source in sources {
                    try Task.checkCancellation()
                    let isFolder = try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
                    let name = isFolder && zipFolders ? source.lastPathComponent + ".zip" : source.lastPathComponent
                    let target = unique(name, in: folder)
                    if isFolder && zipFolders { try Compression.archive(urls: [source], destination: target) }
                    else { try manager.copyItem(at: source, to: target) }
                    outputs.append(target)
                }
            }
            try Task.checkCancellation()
            for url in outputs {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                if values.isDirectory != true { try checkSize(Int64(values.fileSize ?? 0), maximum: maximumBytes) }
            }
            return PreparedSendFiles(folder: folder, urls: outputs)
        } catch { try? manager.removeItem(at: folder); throw error }
    }

    private func checkSize(_ bytes: Int64, maximum: Int64?) throws {
        if let maximum, bytes > maximum {
            throw ActionError.failed(String(localized: "This attachment exceeds this app’s document size limit. Compress it, split it, or send it using another service."))
        }
    }
    private func unique(_ name: String, in folder: URL) -> URL {
        let original = folder.appendingPathComponent(name)
        var candidate = original, suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let ext = original.pathExtension.isEmpty ? "" : "." + original.pathExtension
            candidate = folder.appendingPathComponent(original.deletingPathExtension().lastPathComponent + String(localized: " \(suffix)") + ext)
            suffix += 1
        }
        return candidate
    }
}
