import AppKit
import AuthenticationServices
import Combine
import CryptoKit
import Security

struct LinkAuthFlow {
    static func make(now: Date = Date()) throws -> LinkPKCE {
        func random(_ count: Int) throws -> String {
            var bytes = [UInt8](repeating: 0, count: count)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw LinkError.authCallback }
            return Data(bytes).base64URL
        }
        return LinkPKCE(state: try random(32), verifier: try random(64), createdAt: now)
    }
    static func challenge(_ verifier: String) -> String { Data(SHA256.hash(data: Data(verifier.utf8))).base64URL }
    static func code(_ url: URL, pending: LinkPKCE, now: Date = Date()) throws -> String {
        guard url.scheme == "notchi", url.host == "auth", url.path == "/callback", url.fragment == nil,
              now.timeIntervalSince(pending.createdAt) >= 0, now.timeIntervalSince(pending.createdAt) < 900,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.filter({ $0.name == "state" }).count == 1,
              items.filter({ $0.name == "code" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == pending.state,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty, code.count <= 512 else { throw LinkError.authCallback }
        return code
    }
}
private extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

@MainActor
final class LinkAuthStore: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = LinkAuthStore()
    @Published private(set) var userID: UUID?
    @Published private(set) var isWorking = false
    @Published var message: String?
    var onSignOut: (() -> Void)?
    private let config: LinkConfiguration
    private let secrets: any LinkSecretStore
    private let api: LinkAPI
    private var accessToken: String?
    private var expiresAt = Date.distantPast
    private var refresh: Task<LinkTokens, Error>?
    private var webSession: ASWebAuthenticationSession?
    private var exchanging = false
    private var generation = UUID()
    init(config: LinkConfiguration? = nil, secrets: any LinkSecretStore = LinkKeychain(), api: LinkAPI = .shared) {
        self.config = config ?? .shared; self.secrets = secrets; self.api = api
        super.init()
        if let data = try? secrets.read(credentialKey), let saved = try? JSONDecoder().decode(LinkCredential.self, from: data) { userID = saved.userId }
    }
    private var credentialKey: String { "session.\(config.credentialScope)" }
    private var pendingKey: String { "pkce.\(config.credentialScope)" }
    var isSignedIn: Bool { userID != nil }
    var cleanupToken: String? { expiresAt > Date() ? accessToken : nil }
    func token() async throws -> String {
        guard config.baseURL != nil else { throw LinkError.configuration }
        let nonce = generation, scope = config.credentialScope
        if let accessToken, expiresAt.timeIntervalSinceNow > 45 { return accessToken }
        if let refresh {
            let tokens = try await refresh.value
            guard generation == nonce, config.credentialScope == scope else { throw LinkError.signIn }
            try accept(tokens); return tokens.accessToken
        }
        guard let saved = try secrets.read(credentialKey).flatMap({ try? JSONDecoder().decode(LinkCredential.self, from: $0) }) else { throw LinkError.signIn }
        let base = config.baseURL
        let task = Task { try await api.call("/v1/auth/refresh", base: base, method: "POST", body: LinkAPI.body(["refreshToken": saved.refreshToken])) as LinkTokens }
        refresh = task
        defer { if generation == nonce { refresh = nil } }
        do {
            let tokens = try await task.value
            guard generation == nonce, config.credentialScope == scope else { throw LinkError.signIn }
            guard tokens.userId == saved.userId else { throw LinkError.signIn }
            try accept(tokens); return tokens.accessToken
        } catch let error as LinkError {
            if case .server("sign_in_failed") = error { clearLocal() }
            throw error
        } catch { throw LinkError.network }
    }
    private func accept(_ value: LinkTokens) throws {
        guard value.expiresIn > 0, !value.refreshToken.isEmpty, !value.accessToken.isEmpty else { throw LinkError.invalidResponse }
        // Persist rotated refresh credentials before exposing the session.
        try secrets.save(JSONEncoder().encode(LinkCredential(refreshToken: value.refreshToken, userId: value.userId)), account: credentialKey)
        accessToken = value.accessToken; expiresAt = Date().addingTimeInterval(value.expiresIn); userID = value.userId
    }
    func email(_ email: String) async {
        guard !isWorking else { return }
        isWorking = true; message = nil
        defer { isWorking = false }
        do {
            let flow = try begin()
            let _: LinkOK = try await api.call("/v1/auth/email", base: config.baseURL, method: "POST", body: LinkAPI.body([
                "email": email.trimmingCharacters(in: .whitespacesAndNewlines), "state": flow.state, "challenge": LinkAuthFlow.challenge(flow.verifier)]))
            message = String(localized: "Check your email")
        } catch { message = LinkError.safe(error) }
    }
    func apple() async {
        guard !isWorking else { return }
        isWorking = true; message = nil
        do {
            let flow = try begin()
            let reply: LinkAppleReply = try await api.call("/v1/auth/apple", base: config.baseURL, method: "POST", body: LinkAPI.body(["state": flow.state, "challenge": LinkAuthFlow.challenge(flow.verifier)]))
            let browserURL = reply.authorizationURL
            guard browserURL.user == nil, browserURL.password == nil, browserURL.host != nil else { throw LinkError.invalidResponse }
            #if DEBUG
            let local = browserURL.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(browserURL.host ?? "")
            guard browserURL.scheme == "https" || local else { throw LinkError.invalidResponse }
            #else
            guard browserURL.scheme == "https" else { throw LinkError.invalidResponse }
            #endif
            let session = ASWebAuthenticationSession(url: reply.authorizationURL, callbackURLScheme: "notchi") { [weak self] url, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.isWorking = false; self.webSession = nil
                    if let url { await self.handle(url) }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            webSession = session
            guard session.start() else { throw LinkError.authCallback }
        } catch { isWorking = false; message = LinkError.safe(error) }
    }
    private func begin() throws -> LinkPKCE {
        guard config.baseURL != nil else { throw LinkError.configuration }
        generation = UUID()
        let flow = try LinkAuthFlow.make()
        try secrets.save(JSONEncoder().encode(flow), account: pendingKey)
        return flow
    }
    func handle(_ url: URL) async {
        guard !exchanging else { return }
        exchanging = true; isWorking = true
        let nonce = generation, scope = config.credentialScope
        defer { exchanging = false; isWorking = false }
        do {
            guard let data = try secrets.read(pendingKey) else { throw LinkError.authCallback }
            let flow = try JSONDecoder().decode(LinkPKCE.self, from: data)
            let code = try LinkAuthFlow.code(url, pending: flow)
            let tokens: LinkTokens = try await api.call("/v1/auth/exchange", base: config.baseURL, method: "POST", body: LinkAPI.body(["code": code, "verifier": flow.verifier]))
            guard generation == nonce, config.credentialScope == scope else { throw LinkError.signIn }
            try accept(tokens); secrets.remove(pendingKey)
            message = String(localized: "Signed in")
        } catch { message = LinkError.safe(error) }
    }
    func signOut() async {
        let base = config.baseURL
        let token = try? await self.token()
        clearLocal()
        if let token { let _: LinkOK? = try? await api.call("/v1/auth/logout", base: base, method: "POST", token: token) }
    }
    func clearLocal() {
        generation = UUID()
        onSignOut?(); refresh?.cancel(); refresh = nil
        secrets.remove(credentialKey); secrets.remove(pendingKey)
        accessToken = nil; expiresAt = .distantPast; userID = nil; message = nil
        webSession?.cancel(); webSession = nil; isWorking = false
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) ?? NSWindow()
    }
}
