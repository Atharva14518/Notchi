import Foundation

enum Compression {
    /// A staging directory retains folders and gives colliding names unique suffixes.
    /// Process arguments are passed directly; file names are never interpreted by a shell.
    static func archive(urls: [URL], destination: URL) throws {
        let manager = FileManager.default
        let staging = manager.temporaryDirectory.appendingPathComponent("Notchi-\(UUID().uuidString)")
        let contents = staging.appendingPathComponent("Files")
        try manager.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }

        for url in urls {
            var target = contents.appendingPathComponent(url.lastPathComponent)
            var suffix = 2
            while manager.fileExists(atPath: target.path) {
                let base = url.deletingPathExtension().lastPathComponent
                let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
                target = contents.appendingPathComponent(String(localized: "\(base) \(suffix)\(ext)"))
                suffix += 1
            }
            try manager.copyItem(at: url, to: target)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", contents.path, destination.path]
        // A file sink avoids a full stderr pipe blocking a large archive operation.
        let errorURL = staging.appendingPathComponent("stderr.txt")
        manager.createFile(atPath: errorURL.path, contents: nil)
        let errors = try FileHandle(forWritingTo: errorURL)
        defer { try? errors.close() }
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ActionError.failed(String(localized: "ZIP creation failed. Check file access and available disk space."))
        }
    }
}
