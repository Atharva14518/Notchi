import Foundation

struct MediaInfo: Sendable {
    var duration: Double
    var hasVideo: Bool
    var hasAudio: Bool
    var width: Int = 0
    var height: Int = 0
}
struct MediaRange: Sendable { var start: Double; var end: Double; var duration: Double { end - start } }
enum VideoPreset: String, Sendable, CaseIterable {
    case whatsapp = "WhatsApp", email = "Email", instagramStory = "Instagram story", instagramSquare = "Instagram square", smallest = "Smallest", highQuality = "High quality"
    var targetBytes: Int64? { switch self { case .whatsapp: return 16_000_000; case .email: return 25_000_000; default: return nil } }
}
enum MediaFormat: String, Sendable, CaseIterable {
    case mp4, mov, gif, webm, mp3, m4a, wav, flac
    var isAudio: Bool { [.mp3, .m4a, .wav, .flac].contains(self) }
}
enum MediaOperation: Sendable {
    case preset(VideoPreset, lowerResolution: Bool = false)
    case convert(MediaFormat), extract(MediaFormat), trim(MediaRange?), mute, compressAudio
    var id: String {
        switch self {
        case .preset(let p, let lower): return "preset-\(p.rawValue)-\(lower)"
        case .convert(let f): return "media-convert-\(f.rawValue)"
        case .extract(let f): return "extract-\(f.rawValue)"
        case .trim: return "trim"
        case .mute: return "mute"
        case .compressAudio: return "compress-audio"
        }
    }
    var title: String {
        switch self {
        case .preset(let p, let lower): return p.rawValue + (lower ? String(localized: " · 360p") : String(localized: ""))
        case .convert(let f): return f.rawValue.uppercased()
        case .extract(let f): return String(localized: "audio · \(f.rawValue)")
        case .trim: return String(localized: "trim")
        case .mute: return String(localized: "mute")
        case .compressAudio: return String(localized: "compress audio")
        }
    }
    var icon: String {
        switch self { case .extract, .compressAudio: return "waveform"; case .mute: return "speaker.slash"; case .trim: return "scissors"; default: return "film" }
    }
}
enum MediaError: LocalizedError {
    case invalidDuration, missingEngine, engine(String), targetTooSmall(VideoPreset, lowerResolution: Bool), invalidRange
    var errorDescription: String? {
        switch self {
        case .invalidDuration: return String(localized: "Couldn’t read a finite duration from this file. Try a different copy.")
        case .missingEngine: return String(localized: "Bundled media engine is missing.")
        case .engine(let detail): return detail
        case .targetTooSmall(let preset, let lower):
            return String(localized: "This clip can’t fit the \(preset.rawValue) limit at \(lower ? "360p" : "this quality"). \(lower ? "Try trimming it shorter." : "Try 360p, or trim it shorter.")")
        case .invalidRange: return String(localized: "Choose an end after the start, within the clip’s duration.")
        }
    }
}

struct TargetBitrate: Equatable, Sendable {
    let video: Int
    let audio: Int
    let targetBytes: Int64
    /// Reserve 10% plus 64 KB for container headers/encoder variation. Actual
    /// output is checked as well: this estimate is never a delivery guarantee.
    static func calculate(targetBytes: Int64, duration: Double, audioBitrate: Int = 64_000,
                          minimumVideo: Int = 120_000, safety: Double = 0.90) throws -> TargetBitrate {
        guard duration.isFinite, duration > 0, targetBytes > 65_536, audioBitrate >= 0,
              safety > 0, safety <= 1 else { throw MediaError.invalidDuration }
        let budget = (Double(targetBytes) * safety - 65_536) * 8 / duration - Double(audioBitrate)
        guard budget.isFinite, budget >= Double(minimumVideo), budget < Double(Int.max) else {
            throw MediaError.engine(String(localized: "This duration leaves too little room for usable video. Try a lower resolution or trim the clip."))
        }
        return TargetBitrate(video: min(Int(budget.rounded(.down)), 8_000_000), audio: audioBitrate, targetBytes: targetBytes)
    }
}

/// Handles both human stderr stats (`time=`) and `-progress pipe:2`
/// (`out_time=`/microseconds). Carries partial lines across arbitrary pipe chunks.
struct FFmpegProgressParser {
    private var pending = ""
    private(set) var seconds: Double = 0
    mutating func consume(_ text: String, duration: Double) -> Double? {
        pending += text
        let lines = pending.components(separatedBy: .newlines)
        pending = lines.last ?? ""
        if pending.utf8.count > 16_384 { pending = String(pending.suffix(4096)) }
        var changed = false
        for line in lines.dropLast() {
            if let value = Self.time(in: line), value.isFinite, value >= 0 {
                seconds = max(seconds, value); changed = true
            }
        }
        guard changed, duration.isFinite, duration > 0 else { return nil }
        return min(0.995, max(0, seconds / duration)) // 1 only after a successful exit + valid output.
    }
    static func time(in line: String) -> Double? {
        if line.hasPrefix("out_time_us="), let us = Double(line.dropFirst(12)), us >= 0 { return us / 1_000_000 }
        let pattern = #"(?:^|\s)(?:out_)?time=\s*(\d+):(\d{2}):(\d{2}(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        let values = (1...3).compactMap { index -> Double? in
            guard let range = Range(match.range(at: index), in: line) else { return nil }; return Double(line[range])
        }
        guard values.count == 3, values[1] < 60, values[2] < 60 else { return nil }
        return values[0] * 3600 + values[1] * 60 + values[2]
    }
    static func duration(in stderr: String) -> Double? {
        guard let range = stderr.range(of: String(localized: "Duration: ")) else { return nil }
        return time(in: "time=" + stderr[range.upperBound...].prefix(32))
    }
}

struct MediaCommand: Sendable {
    var arguments: [String]
    var format: MediaFormat
    var duration: Double
    var targetBytes: Int64?
}
enum MediaPlanner {
    static func command(operation: MediaOperation, info: MediaInfo) throws -> MediaCommand {
        guard info.duration.isFinite, info.duration > 0 else { throw MediaError.invalidDuration }
        let video = ["-map", "0:v:0", "-map", "0:a:0?", "-c:v", "h264_videotoolbox", "-allow_sw", "1", "-pix_fmt", "yuv420p"]
        let aac = ["-c:a", "aac", "-b:a", "128k"]
        let fit = fitted(width: 1920, height: 1080)
        var args: [String] = [], format: MediaFormat = info.hasVideo ? .mp4 : .m4a
        var duration = info.duration, target: Int64?
        switch operation {
        case .preset(let preset, let lower):
            guard info.hasVideo else { throw MediaError.engine(String(localized: "This preset needs a video track.")) }
            args = video
            if let bytes = preset.targetBytes {
                let rate: TargetBitrate
                do { rate = try TargetBitrate.calculate(targetBytes: bytes, duration: duration,
                    audioBitrate: info.hasAudio ? 64_000 : 0, minimumVideo: lower ? 40_000 : 120_000) }
                catch { throw MediaError.targetTooSmall(preset, lowerResolution: lower) }
                args += ["-b:v", "\(rate.video)", "-maxrate", "\(rate.video)", "-bufsize", String(localized: "\(rate.video * 2)"), "-constant_bit_rate", "1",
                         "-vf", lower ? fitted(width: 640, height: 360) : fitted(width: 1280, height: 720),
                         "-c:a", "aac", "-b:a", "64000"]
                target = bytes
            } else {
                switch preset {
                case .instagramStory, .instagramSquare:
                    let h = preset == .instagramStory ? 1920 : 1080
                    args += ["-vf", "scale=1080:\(h):force_original_aspect_ratio=increase,crop=1080:\(h),setsar=1", "-b:v", "5000k"] + aac
                case .smallest:
                    args = video.map { $0 == "h264_videotoolbox" ? "hevc_videotoolbox" : $0 }
                    args += ["-tag:v", "hvc1", "-vf", fitted(width: 854, height: 480), "-b:v", "600k", "-c:a", "aac", "-b:a", "64k"]
                default: args += ["-vf", fit, "-b:v", "8000k"] + aac
                }
            }
        case .convert(let output), .extract(let output):
            format = output
            if output.isAudio {
                guard info.hasAudio else { throw MediaError.engine(String(localized: "This file has no audio track to extract.")) }
                args = ["-map", "0:a:0", "-vn"] + audioArguments(output)
            } else {
                guard info.hasVideo else { throw MediaError.engine(String(localized: "This format needs a video track.")) }
                switch output {
                case .gif:
                    args = ["-filter_complex", "[0:v:0]fps=12,scale=480:-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=sierra2_4a", "-an", "-loop", "0"]
                case .webm:
                    args = ["-map", "0:v:0", "-map", "0:a:0?", "-vf", fit, "-pix_fmt", "yuv420p", "-c:v", "libvpx-vp9", "-b:v", "1500k", "-crf", "32", "-deadline", "good", "-cpu-used", "4", "-row-mt", "1", "-c:a", "libopus", "-b:a", "96k"]
                default: args = video + ["-vf", fit, "-b:v", "4000k"] + aac
                }
            }
        case .mute:
            guard info.hasVideo else { throw MediaError.engine(String(localized: "This file has no video to mute.")) }
            args = ["-map", "0:v:0", "-c:v", "h264_videotoolbox", "-allow_sw", "1", "-pix_fmt", "yuv420p", "-vf", fit, "-b:v", "4000k", "-an"]
        case .compressAudio:
            guard info.hasAudio else { throw MediaError.engine(String(localized: "This file has no audio track.")) }
            format = .m4a; args = ["-map", "0:a:0", "-vn", "-c:a", "aac", "-b:a", "64k"]
        case .trim(let range):
            guard let range, range.start.isFinite, range.end.isFinite, range.start >= 0,
                  range.end > range.start, range.end <= info.duration + 0.001 else { throw MediaError.invalidRange }
            duration = range.duration
            args = ["-ss", "\(range.start)", "-t", "\(duration)"]
            args += info.hasVideo ? video + ["-vf", fit, "-b:v", "4000k"] + aac : ["-map", "0:a:0", "-vn"] + audioArguments(.m4a)
        }
        args += ["-map_metadata", "-1", "-map_chapters", "-1"]
        if format == .mp4 || format == .mov || format == .m4a { args += ["-movflags", "+faststart"] }
        return MediaCommand(arguments: args, format: format, duration: duration, targetBytes: target)
    }
    private static func fitted(width: Int, height: Int) -> String {
        "scale=w='min(\(width),iw)':h='min(\(height),ih)':force_original_aspect_ratio=decrease:force_divisible_by=2,setsar=1"
    }
    private static func audioArguments(_ format: MediaFormat) -> [String] {
        switch format {
        case .mp3: return ["-c:a", "libmp3lame", "-b:a", "192k"]
        case .wav: return ["-c:a", "pcm_s16le"]
        case .flac: return ["-c:a", "flac", "-compression_level", "8"]
        default: return ["-c:a", "aac", "-b:a", "128k"]
        }
    }
}
