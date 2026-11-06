import XCTest
import AppKit
import Foundation

private final class LinkTestSecrets: LinkSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String:Data] = [:]
    func read(_ account: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[account] }
    func save(_ data: Data, account: String) throws { lock.lock(); defer { lock.unlock() }; values[account] = data }
    func remove(_ account: String) { lock.lock(); defer { lock.unlock() }; values[account] = nil }
}
private final class LinkTestProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status,data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
private final class LinkTestUploader: LinkUploading, @unchecked Sendable {
    var progress: (@Sendable (UUID,Double)->Void)?
    var completion: (@Sendable (UUID,Bool)->Void)?
    var job: PendingLinkUpload?
    var uploadCount = 0
    var cancelled: [UUID] = []
    func upload(_ job: PendingLinkUpload, reply: LinkUploadInit) throws { self.job = job; uploadCount += 1 }
    func cancel(_ id: UUID) { cancelled.append(id) }
    func reconcile(_ callback: @escaping @Sendable (Set<UUID>)->Void) { callback([]) }
}

final class LinkFeatureTests: XCTestCase {
    private var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("NotchiLinksTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { LinkTestProtocol.handler = nil; try FileManager.default.removeItem(at: folder) }
    func testExpiryBoundaryCountdownAndDownloadLimit() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let link = SharedLink(id: UUID(), fileId: UUID(), filename: "test.pdf", size: 4, url: URL(string:"https://links.test/s/abc")!, expiresAt: now.addingTimeInterval(3600), createdAt: now, passwordProtected: false, downloadLimit: 2, downloadCount: 1, revoked: false)
        XCTAssertTrue(link.isActive(at: now)); XCTAssertFalse(link.isActive(at: link.expiresAt))
        XCTAssertTrue(link.countdown(at: now).contains("1h")); XCTAssertEqual(link.countdown(at: link.expiresAt), "Expired")
        XCTAssertEqual(LinkExpiry.hour.seconds, 3600); XCTAssertEqual(LinkExpiry.day.seconds, 86400); XCTAssertEqual(LinkExpiry.week.seconds, 604800)
    }
    func testPKCEChallengeUsesRFC7636VectorAndRejectsReplayWrongStateAndDuplicateCode() throws {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(LinkAuthFlow.challenge(verifier), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let now = Date(), flow = try LinkAuthFlow.make(now: now)
        let url = URL(string:"notchi://auth/callback?state=\(flow.state)&code=test-code")!
        XCTAssertEqual(try LinkAuthFlow.code(url, pending: flow, now: now), "test-code")
        XCTAssertThrowsError(try LinkAuthFlow.code(url, pending: flow, now: now.addingTimeInterval(900)))
        XCTAssertThrowsError(try LinkAuthFlow.code(URL(string:"notchi://auth/callback?state=wrong&code=x")!, pending: flow))
        XCTAssertThrowsError(try LinkAuthFlow.code(URL(string:url.absoluteString + "&code=second")!, pending: flow))
        XCTAssertThrowsError(try LinkAuthFlow.code(URL(string:"https://auth/callback?state=\(flow.state)&code=x")!, pending: flow))
    }
    func testConfigurationAndUploadDestinationRejectCredentialAndRedirectTargets() {
        XCTAssertNil(LinkConfiguration.validated("https://user:pass@links.test"))
        XCTAssertNil(LinkConfiguration.validated("https://links.test/path"))
        XCTAssertNil(LinkConfiguration.validated("http://external.test"))
        XCTAssertNotNil(LinkConfiguration.validated("https://links.test/"))
        let base = URL(string:"https://links.test")!
        XCTAssertTrue(BackgroundLinkUploader.allowed(URL(string:"https://account.r2.cloudflarestorage.com/bucket/file?sig=test")!, api: base))
        XCTAssertFalse(BackgroundLinkUploader.allowed(URL(string:"https://account.r2.cloudflarestorage.com.evil.test/file")!, api: base))
        XCTAssertFalse(BackgroundLinkUploader.allowed(URL(string:"http://account.r2.cloudflarestorage.com/file")!, api: base))
    }
    func testManifestContainsNoPasswordRefreshTokenOrPresignedURL() async throws {
        let file = folder.appendingPathComponent("source.txt"); try Data("keep bytes".utf8).write(to: file)
        let store = LinkUploadStore(root: folder.appendingPathComponent("owned"))
        let staged = try await store.stage(file)
        let job = PendingLinkUpload(id: UUID(), owner: UUID(), apiBaseURL: URL(string:"https://links.test")!, localFile: staged, sourceItemID: UUID(), expiry: .week, downloadLimit: 1, hasPassword: true)
        try await store.save([job]); let restored = try await store.read()
        XCTAssertEqual(restored.first?.id, job.id)
        let json = try String(contentsOf: folder.appendingPathComponent("owned/jobs.json"), encoding: .utf8)
        for secret in ["\"password\":", "refreshToken", "uploadURL", "signature="] { XCTAssertFalse(json.contains(secret)) }
        try FileManager.default.removeItem(at: file)
        XCTAssertEqual(try Data(contentsOf: staged), Data("keep bytes".utf8))
        await store.discard(staged); XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
    }
    func testAPIErrorCannotExposeNSErrorURL() {
        let error = NSError(domain: NSURLErrorDomain, code: -1001, userInfo: [NSLocalizedDescriptionKey:"https://private.test/file?secret=value"])
        XCTAssertFalse(LinkError.safe(error).contains("https"))
        XCTAssertFalse(LinkError.server("https://private.test?token=secret").localizedDescription.contains("https"))
    }
    @MainActor
    private func fixture() throws -> (LinkCoordinator, LinkTestUploader, NSPasteboard, LinkUploadStore, LinkTestSecrets, LinkAuthStore, LinkConfiguration) {
        let defaults = UserDefaults(suiteName: "NotchiLinkFeatureTests.\(UUID().uuidString)")!
        let config = LinkConfiguration(defaults: defaults); try config.save("https://links.test")
        let secrets = LinkTestSecrets(), owner = UUID(uuidString:"11111111-1111-4111-8111-111111111111")!
        try secrets.save(JSONEncoder().encode(LinkCredential(refreshToken: "old-refresh", userId: owner)), account: "session.\(config.credentialScope)")
        let sessionConfig = URLSessionConfiguration.ephemeral; sessionConfig.protocolClasses = [LinkTestProtocol.self]
        let api = LinkAPI(session: URLSession(configuration: sessionConfig)), auth = LinkAuthStore(config: config, secrets: secrets, api: api)
        let uploadStore = LinkUploadStore(root: folder.appendingPathComponent("jobs")), fake = LinkTestUploader(), board = NSPasteboard.withUniqueName()
        let coordinator = LinkCoordinator(auth: auth, config: config, api: api, uploadStore: uploadStore, secrets: secrets, clipboard: board, uploaderFactory: { progress, completion in fake.progress = progress; fake.completion = completion; return fake })
        return (coordinator,fake,board,uploadStore,secrets,auth,config)
    }
    private func stub() {
        LinkTestProtocol.handler = { request in
            let id = "33333333-3333-4333-8333-333333333333", owner = "11111111-1111-4111-8111-111111111111"
            let data: [String:Any]
            switch request.url!.path {
            case "/v1/auth/refresh": data = ["accessToken":"fresh-access","refreshToken":"rotated-refresh","expiresIn":900,"userId":owner]
            case "/v1/me": data = ["userId":owner,"maxBytes":100000000,"maxActiveLinks":5,"activeLinks":0]
            case "/v1/uploads/init": data = ["fileId":id,"uploadURL":"https://account.r2.cloudflarestorage.com/file?sig=test","headers":["Content-Type":"application/octet-stream"],"uploadExpiresAt":ISO8601DateFormatter().string(from: Date().addingTimeInterval(900))]
            case "/v1/uploads/complete": data = ["id":id,"fileId":id,"filename":"source.txt","size":10,"url":"https://links.test/s/aaaaaaaaaaaaaaaaaaaaaaaa","expiresAt":ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600)),"createdAt":ISO8601DateFormatter().string(from: Date()),"passwordProtected":false,"downloadCount":0,"revoked":false]
            default: data = ["ok":true]
            }
            return (200,try JSONSerialization.data(withJSONObject: data))
        }
    }
    @MainActor private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(15)) }
        XCTAssertTrue(condition())
    }
    @MainActor
    func testRefreshRotatesOnlyKeychainCredentialAndReturnsAccessToken() async throws {
        stub(); let (_,_,board,_,secrets,auth,config) = try fixture(); defer { board.releaseGlobally() }
        let token = try await auth.token(); XCTAssertEqual(token, "fresh-access")
        let data = try XCTUnwrap(secrets.read("session.\(config.credentialScope)"))
        let credential = try JSONDecoder().decode(LinkCredential.self, from: data)
        XCTAssertEqual(credential.refreshToken, "rotated-refresh")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("fresh-access"))
    }
    @MainActor
    func testUploadProgressSuccessPersistsThenCopiesAndKeepsOriginal() async throws {
        stub(); let (links,fake,board,store,_,_,_) = try fixture(); defer { board.releaseGlobally() }
        let source = folder.appendingPathComponent("source.txt"); try Data("keep bytes".utf8).write(to: source)
        links.show(ShelfItem(url: source)); try await wait { !links.isRestoring }
        links.begin(options: LinkOptions()); try await wait { links.phase == .uploading }
        let job = try XCTUnwrap(fake.job); fake.progress?(job.id,0.42)
        try await wait { links.fraction == 0.42 }
        fake.completion?(job.id,true); try await wait { links.phase == .landed }
        XCTAssertEqual(links.successToken,1)
        XCTAssertEqual(board.string(forType:.string),"https://links.test/s/aaaaaaaaaaaaaaaaaaaaaaaa")
        let manifest = try await store.read(); XCTAssertTrue(manifest.isEmpty)
        XCTAssertEqual(try Data(contentsOf: source),Data("keep bytes".utf8))
    }
    @MainActor
    func testCancellationInvalidatesLateUploadCallbackAndCleansManifest() async throws {
        stub(); let (links,fake,board,store,_,_,_) = try fixture(); defer { board.releaseGlobally() }
        let source = folder.appendingPathComponent("source.txt"); try Data("original".utf8).write(to: source)
        links.show(ShelfItem(url: source)); try await wait { !links.isRestoring }
        links.begin(options: LinkOptions()); try await wait { links.phase == .uploading }
        let job = try XCTUnwrap(fake.job); links.cancel(); fake.completion?(job.id,true)
        try await Task.sleep(for:.milliseconds(100))
        XCTAssertEqual(links.phase,.idle); XCTAssertFalse(links.isBusy); XCTAssertEqual(links.successToken,0)
        XCTAssertTrue(fake.cancelled.contains(job.id)); let jobs = try await store.read(); XCTAssertTrue(jobs.isEmpty)
        XCTAssertEqual(try Data(contentsOf: source),Data("original".utf8))
    }

    @MainActor
    func testCancellingRetryCannotRestartTransferOrRestoreFailureState() async throws {
        stub(); let (links,fake,board,_,_,_,_) = try fixture(); defer { board.releaseGlobally() }
        let source = folder.appendingPathComponent("source.txt"); try Data("original".utf8).write(to: source)
        links.show(ShelfItem(url: source)); try await wait { !links.isRestoring }
        links.begin(options: LinkOptions()); try await wait { links.phase == .uploading }
        let job = try XCTUnwrap(fake.job); fake.completion?(job.id,false)
        try await wait { links.phase == .failed }
        links.retry(); links.cancel()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(links.phase,.idle); XCTAssertFalse(links.isBusy)
        XCTAssertEqual(fake.uploadCount,1); XCTAssertNil(board.string(forType:.string))
    }

    @MainActor
    func testRelaunchFinalizesUploadedJournalOnceWithoutUploadingAgain() async throws {
        stub(); let (links,fake,board,store,_,_,_) = try fixture(); defer { board.releaseGlobally() }
        let source = folder.appendingPathComponent("source.txt"); try Data("original".utf8).write(to: source)
        let staged = try await store.stage(source)
        let job = PendingLinkUpload(id: UUID(uuidString:"33333333-3333-4333-8333-333333333333")!, owner: UUID(uuidString:"11111111-1111-4111-8111-111111111111")!, apiBaseURL: URL(string:"https://links.test")!, localFile: staged, sourceItemID: UUID(), expiry: .day, downloadLimit: nil, hasPassword: false, uploaded: true)
        try await store.save([job]); links.start()
        try await wait { links.phase == .landed }
        XCTAssertNil(fake.job); XCTAssertEqual(links.successToken,1)
        XCTAssertEqual(board.string(forType:.string),"https://links.test/s/aaaaaaaaaaaaaaaaaaaaaaaa")
        let pending = try await store.read(); XCTAssertTrue(pending.isEmpty)
    }

    @MainActor
    func testClearingSessionRemovesRefreshCredentialAndRequiresNewSignIn() async throws {
        stub(); let (_,_,board,_,secrets,auth,config) = try fixture(); defer { board.releaseGlobally() }
        _ = try await auth.token(); auth.clearLocal()
        XCTAssertFalse(auth.isSignedIn)
        XCTAssertNil(try secrets.read("session.\(config.credentialScope)"))
        do { _ = try await auth.token(); XCTFail("A cleared session must not refresh") }
        catch { XCTAssertFalse(auth.isSignedIn) }
    }
}
