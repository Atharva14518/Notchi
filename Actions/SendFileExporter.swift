import Foundation

actor SendFileExporter {
    func export(_ sources: [URL], to destination: URL) throws {
        guard !sources.isEmpty else { throw ActionError.failed(String(localized: "Choose a file first.")) }
        let manager = FileManager.default
        let targetPath = destination.resolvingSymlinksInPath().standardizedFileURL.path
        for source in sources {
            let path = source.resolvingSymlinksInPath().standardizedFileURL.path
            let directory = (try source.resourceValues(forKeys: [.isDirectoryKey])).isDirectory ?? false
            let prefix = path == "/" ? "/" : path + "/"
            guard targetPath != path, !(directory && targetPath.hasPrefix(prefix)) else {
                throw ActionError.failed(String(localized: "Choose a different name or location to keep the originals in place."))
            }
        }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".notchi-save-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: staging) }
        if sources.count == 1 {
            try manager.copyItem(at: sources[0], to: staging)
        } else {
            try manager.createDirectory(at: staging, withIntermediateDirectories: false)
            for source in sources {
                try Task.checkCancellation()
                var target = staging.appendingPathComponent(source.lastPathComponent)
                var counter = 2
                while manager.fileExists(atPath: target.path) {
                    let ext = source.pathExtension.isEmpty ? "" : "." + source.pathExtension
                    target = staging.appendingPathComponent(source.deletingPathExtension().lastPathComponent + String(localized: " \(counter)") + ext)
                    counter += 1
                }
                try manager.copyItem(at: source, to: target)
            }
        }
        try Task.checkCancellation()
        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: staging)
        } else { try manager.moveItem(at: staging, to: destination) }
    }
}
