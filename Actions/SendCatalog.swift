import AppKit

struct InstalledSendApp: Identifiable {
    let id: String
    let title: String
    let url: URL
    var isWhatsApp: Bool { id.lowercased().contains("whatsapp") }
    var maximumDocumentBytes: Int64? {
        // WhatsApp documents: https://faq.whatsapp.com/453914586839706/
        isWhatsApp ? 2_000_000_000 : nil
    }
}
struct SendAppHandoff {
    let app: InstalledSendApp
    let files: PreparedSendFiles
}
struct SendTarget: Identifiable {
    enum Kind { case service(NSSharingService), copy, save, more, openApp(InstalledSendApp) }
    let id: String
    let title: String
    let image: NSImage
    let kind: Kind
}

@MainActor
enum SendCatalog {
    static func services(for urls: [URL]) -> [NSSharingService] {
        // Intentional: this public query is deprecated by recent SDKs in favor
        // of a system menu, but is the API that supplies services for our custom
        // in-panel tiles on the macOS 14+ deployment target.
        NSSharingService.sharingServices(forItems: urls.map { $0 as NSURL })
    }
    static func installedFallbacks() -> [InstalledSendApp] {
        let candidates: [(String, [String])] = [
            ("WhatsApp", ["net.whatsapp.WhatsApp", "desktop.WhatsApp"]),
            ("Telegram", ["ru.keepcoder.Telegram", "org.telegram.desktop", "org.telegram.Telegram"])
        ]
        return candidates.compactMap { title, identifiers in
            for id in identifiers {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    return InstalledSendApp(id: id, title: title, url: url)
                }
            }
            return nil
        }
    }
    static func targets(for urls: [URL]) -> [SendTarget] {
        let available = services(for: urls)
        var targets = available.enumerated().map { index, service in
            SendTarget(id: "service-\(index)-\(service.title)", title: service.title, image: service.image, kind: .service(service))
        }
        // WhatsApp and Telegram appear as sharing services ONLY if they register
        // a share extension on this Mac. Installing an app is not registration.
        // Otherwise copy document attachments and launch the app WITHOUT file
        // URLs. Its Open Document handler may accept media but reject PDFs.
        for app in installedFallbacks() where !available.contains(where: {
            $0.title.localizedCaseInsensitiveContains(app.title)
        }) {
            targets.append(SendTarget(id: "app-\(app.id)", title: app.title,
                image: NSWorkspace.shared.icon(forFile: app.url.path), kind: .openApp(app)))
        }
        targets += [
            SendTarget(id: "copy", title: String(localized: "Copy"), image: symbol("doc.on.doc"), kind: .copy),
            SendTarget(id: "save", title: String(localized: "Save to…"), image: symbol("folder.badge.plus"), kind: .save),
            SendTarget(id: "more", title: String(localized: "More…"), image: symbol("ellipsis.circle"), kind: .more)
        ]
        return targets
    }
    private static func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage(size: NSSize(width: 32, height: 32))
    }
}
