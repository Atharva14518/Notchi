import Foundation

/// Bridges blocking Vision work to a dedicated queue. A stalled native request
/// must not hold an actor, the cooperative thread pool, or the UI indefinitely.
final class ScanRequestExecution: @unchecked Sendable {
    private static let queue = DispatchQueue(label: "com.notchi.scan.vision", qos: .userInitiated)
    private let lock = NSLock()
    private let timeout: TimeInterval
    private let operation: @Sendable () throws -> Void
    private let cancelOperation: @Sendable () -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var result: Result<Void, Error>?
    private var watchdog: DispatchWorkItem?

    init(timeout: TimeInterval = 45, operation: @escaping @Sendable () throws -> Void,
         cancel: @escaping @Sendable () -> Void) {
        self.timeout = timeout; self.operation = operation; cancelOperation = cancel
    }

    func run() async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { start($0) }
            try Task.checkCancellation()
        } onCancel: { self.finish(.failure(CancellationError()), cancel: true) }
    }

    private func start(_ continuation: CheckedContinuation<Void, Error>) {
        let timer = DispatchWorkItem { [weak self] in
            self?.finish(.failure(ScanError.recognitionTimedOut), cancel: true)
        }
        lock.lock()
        if let result { lock.unlock(); continuation.resume(with: result); return }
        self.continuation = continuation; watchdog = timer
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timer)
        Self.queue.async { [self] in
            lock.lock(); let finished = result != nil; lock.unlock()
            guard !finished else { return }
            do { try operation(); finish(.success(())) }
            catch { finish(.failure(error)) }
        }
    }

    private func finish(_ outcome: Result<Void, Error>, cancel: Bool = false) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = outcome
        let pending = continuation, timer = watchdog
        continuation = nil; watchdog = nil
        lock.unlock()
        timer?.cancel()
        pending?.resume(with: outcome)
        // VNRequest.cancel() can itself wait for framework internals. Never call
        // it synchronously from a main-actor cancellation handler or timer.
        if cancel { DispatchQueue.global(qos: .utility).async(execute: cancelOperation) }
    }
}
