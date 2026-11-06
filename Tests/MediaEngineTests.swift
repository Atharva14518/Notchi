import XCTest

final class MediaEngineTests: XCTestCase {
    private var folder: URL!
    private var input: URL!
    private var resources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
    }
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("NotchiMediaTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        input = folder.appendingPathComponent("audio.wav")
        func le<T: FixedWidthInteger>(_ value: T) -> Data { var v = value.littleEndian; return withUnsafeBytes(of: &v) { Data($0) } }
        let count = 16000
        var pcm = Data()
        for index in 0..<count { pcm += le(Int16(sin(Double(index) * 2 * .pi * 440 / 16000) * 3000)) }
        var data = Data("RIFF".utf8); data += le(UInt32(pcm.count + 36)); data += Data("WAVEfmt ".utf8)
        data += le(UInt32(16)); data += le(UInt16(1)); data += le(UInt16(1))
        data += le(UInt32(16000)); data += le(UInt32(32000)); data += le(UInt16(2)); data += le(UInt16(16))
        data += Data("data".utf8); data += le(UInt32(pcm.count)); data += pcm
        try data.write(to: input)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }
    func testBundledEngineConvertsAllAudioFormatsAndReportsCompletion() async throws {
        let runner = FFmpegRunner(resourceDirectory: resources)
        let info = try await runner.inspect(input)
        XCTAssertTrue(info.hasAudio); XCTAssertFalse(info.hasVideo)
        XCTAssertEqual(info.duration, 1, accuracy: 0.01)
        for format in [MediaFormat.mp3, .m4a, .wav, .flac] {
            let command = try MediaPlanner.command(operation: .convert(format), info: info)
            let output = folder.appendingPathComponent("converted.\(format.rawValue)")
            let (stream, reporter) = AsyncStream<ActionProgress>.makeStream()
            let consumer = Task { var values: [Double] = []; for await p in stream { if let f = p.fraction { values.append(f) } }; return values }
            _ = try await runner.run(input: input, output: output, command: command, progress: reporter)
            reporter.finish()
            let progress = await consumer.value
            XCTAssertEqual(progress.last, 1)
            XCTAssertTrue(progress.allSatisfy { $0 >= 0 && $0 <= 1 })
            let converted = try await runner.inspect(output)
            XCTAssertTrue(converted.hasAudio)
            XCTAssertGreaterThan(converted.duration, 0.9)
        }
    }
    func testCancellationReapsProcessRemovesPartialOutputAndAllowsAnotherRun() async throws {
        let runner = FFmpegRunner(resourceDirectory: resources)
        let partial = folder.appendingPathComponent("cancelled.flac")
        let command = MediaCommand(arguments: ["-map", "0:a:0", "-af", "aloop=loop=-1:size=16000", "-t", "3600", "-c:a", "flac"], format: .flac, duration: 3600)
        let (_, reporter) = AsyncStream<ActionProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let task = Task { try await runner.run(input: input, output: partial, command: command, progress: reporter) }
        try await Task.sleep(for: .milliseconds(150))
        let start = Date(); task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled operation must throw") } catch is CancellationError { }
        reporter.finish()
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
        let info = try await runner.inspect(input)
        XCTAssertTrue(info.hasAudio)
    }
    @MainActor
    func testCancelInvalidatesOldCoordinatorCallbacksBeforeNextAction() async throws {
        let store = ShelfStore(persistence: MemoryShelfPersistence())
        defer { store.shutdown() }
        store.add([input]); let item = try XCTUnwrap(store.files.first)
        let actions = ActionCoordinator()
        actions.run(NativeFileAction(operation: .media(.compressAudio)), item: item, store: store)
        actions.cancel()
        XCTAssertFalse(actions.isBusy); XCTAssertEqual(actions.job?.phase, .cancelled)
        actions.run(NativeFileAction(operation: .zip), item: item, store: store)
        let limit = Date().addingTimeInterval(5)
        while actions.isBusy && Date() < limit { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(actions.isBusy); XCTAssertEqual(actions.job?.phase, .success)
        XCTAssertEqual(actions.outputURL?.pathExtension, "zip")
        if let output = actions.outputURL { try? FileManager.default.removeItem(at: output.deletingLastPathComponent()) }
    }
    @MainActor
    func testClearingShelfRemovesStaleResultMetricsAndFinderLink() async throws {
        let store = ShelfStore(persistence: MemoryShelfPersistence())
        defer { store.shutdown() }
        store.add([input]); let item = try XCTUnwrap(store.files.first)
        let actions = ActionCoordinator()
        actions.run(NativeFileAction(operation: .zip), item: item, store: store)
        let limit = Date().addingTimeInterval(5)
        while actions.isBusy && Date() < limit { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(actions.isComplete)
        let output = try XCTUnwrap(actions.outputURL)
        store.clear()
        XCTAssertNil(actions.job); XCTAssertNil(actions.outputURL)
        XCTAssertFalse(actions.isComplete)
        try? FileManager.default.removeItem(at: output.deletingLastPathComponent())
    }

}
