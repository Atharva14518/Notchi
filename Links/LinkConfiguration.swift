import Foundation
import Combine
import CryptoKit

@MainActor
final class LinkConfiguration: ObservableObject {
    static let shared = LinkConfiguration()
    @Published private(set) var baseURL: URL?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let text = defaults.string(forKey: "notchi.links.api") { baseURL = Self.validated(text) }
    }
    nonisolated static func validated(_ text: String) -> URL? {
        guard var parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, parts.path.isEmpty || parts.path == "/" else { return nil }
        let isLocal = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
        #if DEBUG
        guard parts.scheme == "https" || (parts.scheme == "http" && isLocal) else { return nil }
        #else
        guard parts.scheme == "https", !isLocal else { return nil }
        #endif
        parts.path = ""
        return parts.url
    }
    func save(_ text: String) throws {
        guard let url = Self.validated(text) else { throw LinkError.configuration }
        baseURL = url; defaults.set(url.absoluteString, forKey: "notchi.links.api")
    }
    var credentialScope: String { Self.scope(baseURL) }
    nonisolated static func scope(_ url: URL?) -> String {
        SHA256.hash(data: Data((url?.absoluteString ?? "unconfigured").utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
