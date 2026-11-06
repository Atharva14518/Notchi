import Foundation

protocol LinkUploading: AnyObject, Sendable {
    func upload(_ job: PendingLinkUpload, reply: LinkUploadInit) throws
    func cancel(_ id: UUID)
    func reconcile(_ callback: @escaping @Sendable (Set<UUID>) -> Void)
}

/// A single stable session identifier lets macOS continue file-backed uploads
/// outside the app process. No taskDescription contains a signed URL or token.
final class BackgroundLinkUploader: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate, LinkUploading, @unchecked Sendable {
    static let identifier = "com.notchi.links.background.v1"
    private var session: URLSession!
    private let progress: (@Sendable (UUID, Double) -> Void)?
    private let completion: (@Sendable (UUID, Bool) -> Void)?
    init(progress: @escaping @Sendable (UUID, Double) -> Void, completion: @escaping @Sendable (UUID, Bool) -> Void) {
        self.progress = progress; self.completion = completion
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        config.sessionSendsLaunchEvents = true; config.isDiscretionary = false
        config.timeoutIntervalForResource = 3600
        config.urlCache = nil
        session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
    }
    func upload(_ job: PendingLinkUpload, reply: LinkUploadInit) throws {
        guard Self.allowed(reply.uploadURL, api: job.apiBaseURL), reply.uploadExpiresAt > Date() else { throw LinkError.uploadExpired }
        var request = URLRequest(url: reply.uploadURL)
        request.httpMethod = "PUT"
        for (name, value) in reply.headers {
            guard ["content-type", "content-length"].contains(name.lowercased()) else { throw LinkError.invalidResponse }
            request.setValue(value, forHTTPHeaderField: name)
        }
        let task = session.uploadTask(with: request, fromFile: job.localFile)
        task.taskDescription = job.id.uuidString
        task.resume()
    }
    static func allowed(_ url: URL, api: URL) -> Bool {
        guard url.user == nil, url.password == nil, let host = url.host else { return false }
        if url.scheme == "https", host.hasSuffix(".r2.cloudflarestorage.com") { return true }
        #if DEBUG
        return url.scheme == api.scheme && url.host == api.host && url.port == api.port && ["127.0.0.1", "localhost", "::1"].contains(host)
        #else
        return false
        #endif
    }
    func cancel(_ id: UUID) {
        session.getAllTasks { tasks in tasks.filter { $0.taskDescription == id.uuidString }.forEach { $0.cancel() } }
    }
    func reconcile(_ callback: @escaping @Sendable (Set<UUID>) -> Void) {
        session.getAllTasks { callback(Set($0.compactMap { $0.taskDescription.flatMap(UUID.init(uuidString:)) })) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let id = task.taskDescription.flatMap(UUID.init(uuidString:)), totalBytesExpectedToSend > 0 else { return }
        progress?(id, min(1, max(0, Double(totalBytesSent) / Double(totalBytesExpectedToSend))))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        completion?(id, error == nil && (200..<300).contains(status))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    // Response bodies and NSError userInfo can contain URLs. Neither is logged.
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) { }
}
