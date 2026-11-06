import Foundation

actor MediaActionWorker {
    static let shared = MediaActionWorker()
    func discard(_ outputs: [URL]) {
        for folder in Set(outputs.map { $0.deletingLastPathComponent() }) { try? FileManager.default.removeItem(at: folder) }
    }
    func execute(_ operation: MediaOperation, item: ShelfItem, progress: ActionProgress.Reporter) async throws -> ActionResult {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Notchi/Results/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            progress.yield(.init(fraction: nil, message: String(localized: "reading media…")))
            let info = try await FFmpegRunner.shared.inspect(item.url)
            try Task.checkCancellation()
            let command = try MediaPlanner.command(operation: operation, info: info)
            let stem = item.url.deletingPathExtension().lastPathComponent
            let output = folder.appendingPathComponent(stem + "-" + AppConfig.appName.lowercased() + "." + command.format.rawValue)
            _ = try await FFmpegRunner.shared.run(input: item.url, output: output, command: command, progress: progress)
            try Task.checkCancellation()
            let after = Int64(try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            if let target = command.targetBytes, after > target,
               case .preset(let preset, let lower) = operation { throw MediaError.targetTooSmall(preset, lowerResolution: lower) }
            return ActionResult(outputs: [output], beforeBytes: item.size ?? 0, afterBytes: after,
                message: command.targetBytes != nil ? String(localized: "fits the size target.") : String(localized: "ready to go."))
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }
}
