import Foundation

// Stored locally only; public/signed URLs and file contents never enter logs.
enum LinkExpiry: String, Codable, CaseIterable, Identifiable, Sendable {
    case hour = "1h", day = "24h", week = "7d"
    var id: Self { self }
    var title: String { switch self { case .hour: return String(localized: "1 hour"); case .day: return String(localized: "24 hours"); case .week: return String(localized: "7 days") } }
    var seconds: TimeInterval { switch self { case .hour: return 3600; case .day: return 86400; case .week: return 604800 } }
}
struct SharedLink: Codable, Identifiable, Sendable {
    let id: UUID
    let fileId: UUID
    let filename: String
    let size: Int64
    let url: URL
    let expiresAt: Date
    let createdAt: Date
    let passwordProtected: Bool
    let downloadLimit: Int?
    let downloadCount: Int
    let revoked: Bool
    func isActive(at now: Date = Date()) -> Bool { !revoked && expiresAt > now && (downloadLimit == nil || downloadCount < downloadLimit!) }
    func countdown(at now: Date) -> String {
        if revoked { return String(localized: "Revoked") }
        if expiresAt <= now { return String(localized: "Expired") }
        if let downloadLimit, downloadCount >= downloadLimit { return String(localized: "Limit reached") }
        let seconds = max(1, Int(expiresAt.timeIntervalSince(now)))
        if seconds >= 86400 { return String(localized: "\(seconds / 86400)d left") }
        if seconds >= 3600 { return String(localized: "\(seconds / 3600)h left") }
        if seconds >= 60 { return String(localized: "\(seconds / 60)m left") }
        return String(localized: "\(seconds)s left")
    }
}
struct LinkOptions: Sendable { var expiry: LinkExpiry = .day; var password = ""; var downloadLimit: Int? }
struct LinkAccount: Decodable, Sendable { let userId: UUID; let maxBytes: Int64; let maxActiveLinks: Int; let activeLinks: Int }
struct LinkUploadInit: Decodable, Sendable { let fileId: UUID; let uploadURL: URL; let headers: [String:String]; let uploadExpiresAt: Date }
struct LinkTokens: Decodable, Sendable { let accessToken: String; let refreshToken: String; let expiresIn: Double; let userId: UUID }
struct LinkCredential: Codable { let refreshToken: String; let userId: UUID }
struct LinkPKCE: Codable { let state: String; let verifier: String; let createdAt: Date }
struct PendingLinkUpload: Codable, Identifiable, Sendable {
    var id: UUID // Server file UUID; also URLSession taskDescription.
    var owner: UUID
    var apiBaseURL: URL
    var localFile: URL
    var sourceItemID: UUID
    var expiry: LinkExpiry
    var downloadLimit: Int?
    var hasPassword: Bool
    var uploaded: Bool = false
    var createdAt = Date()
}
enum LinkError: LocalizedError {
    case configuration, signIn, network, cancelled, invalidResponse, tooLarge, quota, blocked, uploadExpired, password, keychain, authCallback, busy, server(String)
    var errorDescription: String? {
        switch self {
        case .configuration: return String(localized: "Set your link service URL.")
        case .signIn: return String(localized: "Sign in to get links.")
        case .network: return String(localized: "Connection lost. Try again.")
        case .cancelled: return String(localized: "Upload cancelled")
        case .invalidResponse: return String(localized: "The service couldn’t finish. Retry.")
        case .tooLarge: return String(localized: "File exceeds your size limit.")
        case .quota: return String(localized: "Revoke a link first.")
        case .blocked: return String(localized: "That file type isn’t allowed.")
        case .uploadExpired: return String(localized: "Upload expired. Start again.")
        case .password: return String(localized: "Use 8–128 password characters.")
        case .keychain: return String(localized: "Keychain access failed. Try again.")
        case .authCallback: return String(localized: "Sign-in expired. Try again.")
        case .busy: return String(localized: "Finish the upload first.")
        case .server(let code):
            // Stable server codes only. Do not surface arbitrary errors that may
            // contain signed URLs or access tokens.
            switch code {
            case "too_large": return LinkError.tooLarge.errorDescription
            case "quota_exceeded": return LinkError.quota.errorDescription
            case "invalid_password": return LinkError.password.errorDescription
            case "blocked_type": return LinkError.blocked.errorDescription
            case "sign_in_required": return LinkError.signIn.errorDescription
            case "upload_expired", "expired_upload": return LinkError.uploadExpired.errorDescription
            case "rate_limited": return String(localized: "Too many requests. Try shortly.")
            case "invalid_email": return String(localized: "Check your email address.")
            default: return LinkError.invalidResponse.errorDescription
            }
        }
    }
    static func safe(_ error: Error) -> String { (error as? LinkError)?.localizedDescription ?? String(localized: "Connection failed. Try again.") }
}
enum LinkJSON {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { input in
            let text = try input.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date }
            throw LinkError.invalidResponse
        }
        return decoder
    }
}
