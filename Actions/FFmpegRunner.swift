import Foundation
import AVFoundation
import Darwin

/// All blocking pipe reads/waits live on a utility queue. This actor coordinates
/// runs; cancellation targets its own Process, never a name or unrelated PID.
actor FFmpegRunner {
    static let shared = FFmpegRunner()
    private var running: [UUID: MediaProcess] = [:]
    private let resourceDirectory: URL?
    init(resourceDirectory: URL? = Bundle.main.resourceURL) { self.resourceDirectory = resourceDirectory }
    private func executable(_ name: String) throws -> URL {
        guard let url = resourceDirectory?.appendingPathComponent(name),
              FileManager.default.isExecutableFile(atPath: url.path) else { throw MediaError.missingEngine }
        return url
    }
    func inspect(_ input: URL) async throws -> MediaInfo {
        let probe = try executable("ffprobe")
        let process = MediaProcess(executable: probe,
            arguments: ["-v", "error", "-protocol_whitelist", "file,pipe", "-show_entries", "format=duration:stream=codec_type,width,height,duration:stream_disposition=attached_pic", "-of", "json", input.path], captureOutput: true)
        let id = UUID(); running[id] = process
        defer { running[id] = nil }
        let result = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await process.execute()
        } onCancel: { process.cancel() }
        guard let object = try JSONSerialization.jsonObject(with: result) as? [String: Any],
              let streams = object["streams"] as? [[String: Any]] else { throw MediaError.invalidDuration }
        let format = object["format"] as? [String: Any]
        let durations = ([format?["duration"] as? String] + streams.map { $0["duration"] as? String })
            .compactMap { $0.flatMap(Double.init) }.filter { $0.isFinite && $0 > 0 }
        let video = streams.first {
            $0["codec_type"] as? String == "video" && (($0["disposition"] as? [String: Any])?["attached_pic"] as? Int ?? 0) == 0
        }
        var duration = durations.max() ?? 0
        if duration == 0 {
            // Some native files omit container duration; use asynchronous AVAsset.
            let time = try? await AVURLAsset(url: input).load(.duration)
            duration = time.map(CMTimeGetSeconds) ?? 0
        }
        guard duration.isFinite, duration > 0 else { throw MediaError.invalidDuration }
        return MediaInfo(duration: duration, hasVideo: video != nil,
            hasAudio: streams.contains { $0["codec_type"] as? String == "audio" },
            width: video?["width"] as? Int ?? 0, height: video?["height"] as? Int ?? 0)
    }
    func run(input: URL, output: URL, command: MediaCommand, progress: ActionProgress.Reporter) async throws -> URL {
        try Task.checkCancellation()
        let process = MediaProcess(executable: try executable("ffmpeg"), arguments:
            ["-hide_banner", "-nostdin", "-y", "-protocol_whitelist", "file,pipe", "-i", input.path] + command.arguments +
            ["-progress", "pipe:2", "-stats_period", "0.2", "-nostats", output.path],
            duration: command.duration, progress: progress)
        let id = UUID(); running[id] = process
        defer { running[id] = nil }
        do {
            _ = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await process.execute()
            } onCancel: { process.cancel() }
            try Task.checkCancellation()
            guard (try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0 else {
                throw MediaError.engine(String(localized: "The encoder produced an empty file. Try another format."))
            }
            progress.yield(.init(fraction: 1, message: String(localized: "finishing…")))
            return output
        } catch { try? FileManager.default.removeItem(at: output); throw error }
    }
    func cancel() { for process in running.values { process.cancel() } }
}

/// A small synchronization boundary for Foundation.Process and its cancellation
/// flag. Buffers are local to the reader queues, not shared with the UI/actor.
private final class MediaProcess: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var cancelled = false
    private var started = false
    private let captureOutput: Bool
    private let duration: Double?
    private let progress: ActionProgress.Reporter?
    init(executable: URL, arguments: [String], captureOutput: Bool = false,
         duration: Double? = nil, progress: ActionProgress.Reporter? = nil) {
        process.executableURL = executable; process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        self.captureOutput = captureOutput; self.duration = duration; self.progress = progress
    }
    func cancel() {
        // Dispatch immediately; a cancelling MainActor never waits for a pipe,
        // process launch, termination, or lock held by the worker queue.
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            lock.lock(); cancelled = true
            let running = started && process.isRunning
            if running { process.terminate() }
            lock.unlock()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25) { [self] in
                lock.lock(); defer { lock.unlock() }
                if started && process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
    }
    func execute() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [self] in
                do { continuation.resume(returning: try blockingRun()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    private func blockingRun() throws -> Data {
        let stderr = Pipe(), stdout = Pipe()
        process.standardError = stderr
        if captureOutput { process.standardOutput = stdout } else { process.standardOutput = FileHandle.nullDevice }
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        do { try process.run(); started = true; lock.unlock() }
        catch { lock.unlock(); throw error }
        // Probe JSON is read concurrently so neither pipe can fill and deadlock.
        let capture = BoundedCapture()
        let group = DispatchGroup()
        if captureOutput {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { group.leave() }
                while let data = try? stdout.fileHandleForReading.read(upToCount: 8192), !data.isEmpty { capture.append(data) }
            }
        }
        var parser = FFmpegProgressParser(), tail = ""
        var progressDuration = duration
        let start = ProcessInfo.processInfo.systemUptime
        while let data = try? stderr.fileHandleForReading.read(upToCount: 8192), !data.isEmpty {
            let chunk = String(decoding: data, as: UTF8.self)
            tail += chunk; if tail.utf8.count > 16_384 { tail = String(tail.suffix(8192)) }
            if progressDuration == nil { progressDuration = FFmpegProgressParser.duration(in: tail) }
            if let duration = progressDuration, let fraction = parser.consume(chunk, duration: duration) {
                let elapsed = ProcessInfo.processInfo.systemUptime - start
                let eta: TimeInterval? = fraction > 0.02 ? max(0, elapsed * (1 - fraction) / fraction) : nil
                progress?.yield(.init(fraction: fraction, message: String(localized: "encoding…"), estimatedRemaining: eta))
            }
        }
        process.waitUntilExit(); group.wait()
        try? stderr.fileHandleForReading.close(); try? stdout.fileHandleForReading.close()
        lock.lock(); let wasCancelled = cancelled; lock.unlock()
        if wasCancelled { throw CancellationError() }
        guard process.terminationStatus == 0 else {
            let detail: String
            if tail.contains("videotoolbox") || tail.contains("VTCompressionSession") {
                detail = String(localized: "VideoToolbox couldn’t encode this clip. The encoder may be busy or unavailable on this Mac. Try WebM, or another video.")
            } else { detail = String(localized: "Couldn’t process this media. It may be damaged, protected, or use an unsupported stream.") }
            throw MediaError.engine(detail)
        }
        return capture.value
    }
}
private final class BoundedCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ chunk: Data) { lock.lock(); defer { lock.unlock() }; if data.count < 262_144 { data.append(chunk.prefix(262_144 - data.count)) } }
    var value: Data { lock.lock(); defer { lock.unlock() }; return data }
}
