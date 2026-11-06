import XCTest

final class MediaActionsTests: XCTestCase {
    func testTargetBudgetReservesAudioHeadersAndSafetyMargin() throws {
        let rate = try TargetBitrate.calculate(targetBytes: 16_000_000, duration: 60)
        XCTAssertEqual(rate.video, Int(((16_000_000.0 * 0.9 - 65_536) * 8 / 60 - 64_000).rounded(.down)))
        let estimated = Double(rate.video + rate.audio) * 60 / 8 + 65_536
        XCTAssertLessThan(estimated, Double(rate.targetBytes))
        XCTAssertEqual(rate.targetBytes, 16_000_000)
    }
    func testTargetRateRejectsInvalidAndImpossibleBudgets() {
        for duration in [0.0, -1, .nan, .infinity] {
            XCTAssertThrowsError(try TargetBitrate.calculate(targetBytes: 16_000_000, duration: duration))
        }
        XCTAssertThrowsError(try TargetBitrate.calculate(targetBytes: 16_000_000, duration: 3600))
        XCTAssertThrowsError(try TargetBitrate.calculate(targetBytes: 100, duration: 60))
        XCTAssertThrowsError(try TargetBitrate.calculate(targetBytes: 16_000_000, duration: 60, safety: 1.1))
    }
    func testLowerResolutionBudgetCanFitWhere720pCannot() throws {
        XCTAssertThrowsError(try TargetBitrate.calculate(targetBytes: 16_000_000, duration: 900))
        let lower = try TargetBitrate.calculate(targetBytes: 16_000_000, duration: 900, minimumVideo: 40_000)
        XCTAssertGreaterThan(lower.video, 40_000)
        let silent = try TargetBitrate.calculate(targetBytes: 16_000_000, duration: 900, audioBitrate: 0)
        XCTAssertGreaterThan(silent.video, lower.video)
    }
    func testProgressParsesStderrAndChunkedMachineOutput() throws {
        XCTAssertEqual(FFmpegProgressParser.time(in: "frame= 120 fps=30 time=00:01:02.50 bitrate=1000kbits/s"), 62.5)
        XCTAssertEqual(FFmpegProgressParser.duration(in: "Duration: 01:02:03.25, start: 0"), 3723.25)
        var parser = FFmpegProgressParser()
        XCTAssertNil(parser.consume("out_ti", duration: 100))
        XCTAssertNil(parser.consume("me=00:00:25", duration: 100))
        XCTAssertEqual(parser.consume(".00\n", duration: 100), 0.25)
        XCTAssertEqual(parser.consume("out_time_us=50000000\n", duration: 100), 0.5)
        XCTAssertEqual(parser.consume("time=00:00:40.00\r", duration: 100), 0.5) // monotonic
        XCTAssertEqual(parser.consume("out_time=00:02:00.00\nprogress=end\n", duration: 100), 0.995)
    }
    func testProgressRejectsUnavailableInvalidAndHugeInputs() {
        XCTAssertNil(FFmpegProgressParser.time(in: "time=N/A"))
        XCTAssertNil(FFmpegProgressParser.time(in: "time=-00:00:10.00"))
        XCTAssertNil(FFmpegProgressParser.time(in: "time=00:65:00.00"))
        var parser = FFmpegProgressParser()
        XCTAssertNil(parser.consume("time=00:00:12.00\n", duration: .nan))
        XCTAssertNil(parser.consume(String(repeating: "x", count: 100_000), duration: 100))
        XCTAssertEqual(parser.consume("\nout_time=00:00:30.00\n", duration: 100), 0.3)
    }
    func testPlannerUsesOnlyPermittedEncodersAndExactInstagramDimensions() throws {
        let info = MediaInfo(duration: 60, hasVideo: true, hasAudio: true)
        for preset in VideoPreset.allCases {
            let plan = try MediaPlanner.command(operation: .preset(preset), info: info)
            let text = plan.arguments.joined(separator: " ")
            XCTAssertFalse(text.contains("libx264")); XCTAssertFalse(text.contains("libx265"))
            XCTAssertTrue(text.contains("videotoolbox")); XCTAssertTrue(text.contains("aac"))
        }
        let story = try MediaPlanner.command(operation: .preset(.instagramStory), info: info)
        XCTAssertTrue(story.arguments.contains { $0.contains("crop=1080:1920") })
        let square = try MediaPlanner.command(operation: .preset(.instagramSquare), info: info)
        XCTAssertTrue(square.arguments.contains { $0.contains("crop=1080:1080") })
        let gif = try MediaPlanner.command(operation: .convert(.gif), info: info)
        XCTAssertTrue(gif.arguments.contains { $0.contains("palettegen") && $0.contains("paletteuse") })
        let webm = try MediaPlanner.command(operation: .convert(.webm), info: info)
        XCTAssertTrue(webm.arguments.contains("libvpx-vp9")); XCTAssertTrue(webm.arguments.contains("libopus"))
    }
    func testTrimAndAudioTrackValidation() throws {
        let info = MediaInfo(duration: 10, hasVideo: true, hasAudio: false)
        XCTAssertThrowsError(try MediaPlanner.command(operation: .extract(.mp3), info: info))
        XCTAssertThrowsError(try MediaPlanner.command(operation: .trim(MediaRange(start: 5, end: 4)), info: info))
        XCTAssertThrowsError(try MediaPlanner.command(operation: .trim(MediaRange(start: 0, end: 11)), info: info))
        let trim = try MediaPlanner.command(operation: .trim(MediaRange(start: 2, end: 8)), info: info)
        XCTAssertEqual(trim.duration, 6)
        let mute = try MediaPlanner.command(operation: .mute, info: info)
        XCTAssertTrue(mute.arguments.contains("-an"))
    }
}
