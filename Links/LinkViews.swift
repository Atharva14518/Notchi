import AppKit
import SwiftUI

struct LinkWorkspaceView: View {
    @ObservedObject var links: LinkCoordinator
    @ObservedObject private var auth = LinkAuthStore.shared
    @ObservedObject var store: ShelfStore
    @ObservedObject var actions: ActionCoordinator
    @State private var expiry: LinkExpiry = .day
    @State private var password = ""
    @State private var usePassword = false
    @State private var useLimit = false
    @State private var limit = 10
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button { links.close() } label: { Image(systemName: "chevron.left") }.buttonStyle(NotchiButtonStyle(.icon)).help(String(localized: "Back"))
                    Text(links.screen == .myLinks ? String(localized: "My links") : String(localized: "Get a link")).font(Typography.heading)
                    Spacer()
                    Button { links.screen = links.screen == .compose ? .myLinks : .compose; Task { await links.refreshLinks() } } label: { Image(systemName: "link") }
                        .buttonStyle(NotchiButtonStyle(.icon)).help(String(localized: "My links"))
                }
                if !auth.isSignedIn { LinkAccountView() }
                else if links.screen == .myLinks { MyLinksView(links: links) }
                else if links.phase == .landed, let result = links.result {
                    HStack {
                        BlobMascot(gaze: .zero, isActive: true, isTargeted: false, happyToken: links.successToken, thumbToken: links.successToken)
                            .scaleEffect(0.7).frame(width: 58, height: 52)
                        LinkResultChip(link: result) { links.copy(result) }
                    }.transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.75)))
                    Button(String(localized: "My links")) { links.showMyLinks() }.buttonStyle(NotchiButtonStyle(.secondary))
                } else {
                    if let item = links.item {
                        HStack(spacing: 16) {
                            FileCard(file: item, index: 0, store: store, actions: actions, onForward: { _ in })
                                .allowsHitTesting(false).scaleEffect(0.8).frame(width: 100, height: 110)
                                .opacity(links.phase == .flying ? 0 : 1)
                            if links.isBusy {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        ProgressRing(progress: links.fraction, isComplete: false,
                                                     isIndeterminate: links.phase != .uploading, size: 42)
                                        BlobMascot(gaze: .zero, isActive: true, isTargeted: false, isWorking: true)
                                            .scaleEffect(0.5).frame(width: 40, height: 36)
                                    }
                                    Text(links.phase == .uploading ? String(localized: "\(Int(links.fraction * 100))% uploaded") : (links.phase == .preparing ? String(localized: "Preparing…") : String(localized: "Finishing…")))
                                        .font(Typography.mono).foregroundStyle(Color.acid)
                                    Button(String(localized: "Cancel")) { links.cancel() }.buttonStyle(NotchiButtonStyle(.destructive))
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !links.isBusy {
                        NotchiSegmented(String(localized: "Expiry"), selection: $expiry, options: LinkExpiry.allCases.map { NotchiOption($0, $0.title) })
                        NotchiToggle(String(localized: "Password"), isOn: $usePassword)
                        if usePassword { SecureField(String(localized: "8–128 characters"), text: $password).textFieldStyle(NotchiTextFieldStyle()) }
                        HStack {
                            NotchiToggle(String(localized: "Download limit"), isOn: $useLimit)
                            if useLimit {
                                TextField(String(localized: "Downloads"), value: $limit, format: .number)
                                    .textFieldStyle(NotchiTextFieldStyle()).frame(width: 65)
                            }
                        }
                        if links.hasPendingUpload {
                            HStack {
                                Button(String(localized: "Retry")) { links.retry() }.buttonStyle(NotchiButtonStyle(.primary))
                                Button(String(localized: "Cancel")) { links.cancel() }.buttonStyle(NotchiButtonStyle(.secondary))
                            }
                        } else {
                            Button { links.begin(options: LinkOptions(expiry: expiry, password: usePassword ? password : "", downloadLimit: useLimit ? min(10_000, max(1, limit)) : nil)) } label: {
                                Label(String(localized: "Get link"), systemImage: "paperplane.fill").frame(maxWidth: .infinity)
                            }.buttonStyle(NotchiButtonStyle(.primary)).disabled(links.item == nil)
                        }
                    }
                }
                if let message = links.message {
                    if links.isError {
                        NotchiState(title: message, error: true, actionTitle: links.hasPendingUpload ? String(localized: "Retry") : String(localized: "Back")) {
                            if links.hasPendingUpload { links.retry() } else { links.close() }
                        }
                    } else { NotchiAttention(message: message) }
                }
            }.padding(.vertical, 3).padding(.horizontal, 2)
        }.scrollIndicators(.hidden)
            .animation(reduceMotion ? Animations.fade : (links.phase == .landed ? Animations.bouncy : Animations.snappy), value: links.phase)
            .onChange(of: auth.userID) { _, _ in links.resumeAfterSignIn() }
    }
}
struct LinkAccountView: View {
    @ObservedObject private var auth = LinkAuthStore.shared
    @ObservedObject private var config = LinkConfiguration.shared
    @ObservedObject private var links = LinkCoordinator.shared
    @State private var service = ""
    @State private var email = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField(String(localized: "Service URL"), text: $service).textFieldStyle(NotchiTextFieldStyle())
                Button(String(localized: "Save")) {
                    do {
                        guard !links.isBusy else { throw LinkError.busy }
                        guard let valid = LinkConfiguration.validated(service) else { throw LinkError.configuration }
                        if valid != config.baseURL { auth.clearLocal() }
                        try config.save(service); error = nil
                    } catch { self.error = LinkError.safe(error) }
                }.buttonStyle(NotchiButtonStyle(.secondary)).disabled(links.isBusy || auth.isWorking)
                NotchiInfo(text: String(localized: "Your deployed HTTPS link service. Local HTTP works in Debug."))
            }
            if config.baseURL != nil {
                if auth.isSignedIn {
                    Label(String(localized: "Signed in"), systemImage: "checkmark.shield.fill").foregroundStyle(Color.mint).font(Typography.settingsLabel)
                    HStack {
                        Button(String(localized: "My links")) { NotificationCenter.default.post(name: .notchiShowLinks, object: nil) }.buttonStyle(NotchiButtonStyle(.primary))
                        Button(String(localized: "Sign out")) { Task { await auth.signOut() } }.buttonStyle(NotchiButtonStyle(.secondary)).disabled(links.isBusy)
                    }
                } else {
                    Button { Task { await auth.apple() } } label: { Label(String(localized: "Sign in with Apple"), systemImage: "apple.logo") }
                        .buttonStyle(NotchiButtonStyle(.primary)).disabled(auth.isWorking)
                    HStack {
                        TextField(String(localized: "Email"), text: $email).textFieldStyle(NotchiTextFieldStyle())
                        Button(String(localized: "Email link")) { Task { await auth.email(email) } }.buttonStyle(NotchiButtonStyle(.secondary)).disabled(auth.isWorking || email.isEmpty)
                    }
                }
                if auth.isWorking { BouncingDots() }
                if let message = auth.message { NotchiAttention(message: message) }
            }
            if let error { NotchiAttention(message: error, isError: true) }
        }.onAppear { service = config.baseURL?.absoluteString ?? "" }
    }
}
struct MyLinksView: View {
    @ObservedObject var links: LinkCoordinator
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { time in
            VStack(spacing: 10) {
                if links.links.isEmpty {
                    NotchiState(title: links.isRefreshing ? String(localized: "Loading…") : String(localized: "No links yet"), working: links.isRefreshing,
                                actionTitle: String(localized: "Refresh")) { Task { await links.refreshLinks() } }
                }
                ForEach(links.links) { link in
                    HStack(spacing: 8) {
                        Image(systemName: link.passwordProtected ? "lock.fill" : "link").foregroundStyle(Color.acid)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(link.filename).font(Typography.button).lineLimit(1).truncationMode(.middle)
                            Text(link.countdown(at: time.date)).font(Typography.caption).foregroundStyle(link.isActive(at: time.date) ? Color.secondaryText : .coral)
                        }
                        Spacer(minLength: 0)
                        Button { links.copy(link) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(NotchiButtonStyle(.icon)).help(String(localized: "Copy link")).disabled(!link.isActive(at: time.date))
                        Button { Task { await links.revoke(link) } } label: { Image(systemName: "xmark") }.buttonStyle(NotchiButtonStyle(.icon)).foregroundStyle(Color.coral).help(String(localized: "Revoke link")).disabled(link.revoked)
                    }.padding(12).background(Color.shelfSurface, in: RoundedRectangle(cornerRadius: 15))
                }
                if !links.links.isEmpty {
                    Button { Task { await links.refreshLinks() } } label: { Label(String(localized: "Refresh"), systemImage: "arrow.clockwise") }.buttonStyle(NotchiButtonStyle(.secondary)).disabled(links.isRefreshing)
                }
            }
        }.task { await links.refreshLinks() }
    }
}
struct LinkResultChip: View {
    let link: SharedLink
    let copy: () -> Void
    var body: some View {
        Button(action: copy) {
            Label(String(localized: "Link ready"), systemImage: "link")
                .font(Typography.heading).padding(.vertical, 14).frame(maxWidth: .infinity)
        }.buttonStyle(NotchiButtonStyle(.primary)).help(String(localized: "Copy link"))
    }
}
extension Notification.Name { static let notchiShowLinks = Notification.Name("Notchi.showLinks") }
