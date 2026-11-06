import Foundation

private final class LinkNoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
actor LinkAPI {
    static let shared = LinkAPI()
    private let session: URLSession
    init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.urlCache = nil
        self.session = session ?? URLSession(configuration: config, delegate: LinkNoRedirects(), delegateQueue: nil)
    }
    func call<T: Decodable & Sendable>(_ path: String, base: URL?, method: String = "GET", token: String? = nil, body: Data? = nil) async throws -> T {
        guard let base, LinkConfiguration.validated(base.absoluteString) != nil, path.hasPrefix("/v1/") else { throw LinkError.configuration }
        let url = base.appendingPathComponent(String(path.dropFirst()))
        var request = URLRequest(url: url)
        request.httpMethod = method; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, reply) = try await session.data(for: request)
            guard let http = reply as? HTTPURLResponse else { throw LinkError.invalidResponse }
            guard data.count <= 2_000_000 else { throw LinkError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                let code = (try? JSONDecoder().decode(LinkAPIError.self, from: data))?.error ?? "service_unavailable"
                throw LinkError.server(code)
            }
            return try LinkJSON.decoder().decode(T.self, from: data)
        } catch let error as LinkError { throw error }
        catch is CancellationError { throw LinkError.cancelled }
        catch { throw LinkError.network } // Never expose NSError's failing URL.
    }
    nonisolated static func body(_ value: [String:Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
}
struct LinkAPIError: Decodable { let error: String }
struct LinkOK: Decodable, Sendable { let ok: Bool }
struct LinkListReply: Decodable, Sendable { let links: [SharedLink] }
struct LinkAppleReply: Decodable, Sendable { let authorizationURL: URL }
