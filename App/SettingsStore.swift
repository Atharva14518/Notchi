import AppKit
import Combine

struct GlobalShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    static let standard = GlobalShortcut(keyCode: 45, modifiers: 4096 | 2048) // ⌃⌥N, Carbon flags
    var label: String {
        let prefix = [(UInt32(4096), "⌃"), (UInt32(2048), "⌥"), (UInt32(512), "⇧"), (UInt32(256), "⌘")]
            .filter { modifiers & $0.0 != 0 }.map(\.1).joined()
        return prefix + Self.keyNames[keyCode, default: String(localized: "Key \(keyCode)")]
    }
    static let keyNames: [UInt32: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"−",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",49:"Space",50:"`",123:"←",124:"→",125:"↓",126:"↑"]
    static func from(_ event: NSEvent) -> GlobalShortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Arrow events carry the Function flag on macOS even without holding Fn.
        let navigationKey = (123...126).contains(Int(event.keyCode))
        guard (!flags.contains(.function) || navigationKey),
              flags.contains(.command) || flags.contains(.control) || flags.contains(.option),
              keyNames[UInt32(event.keyCode)] != nil else { return nil }
        var bits: UInt32 = 0
        if flags.contains(.command) { bits |= 256 }
        if flags.contains(.shift) { bits |= 512 }
        if flags.contains(.option) { bits |= 2048 }
        if flags.contains(.control) { bits |= 4096 }
        return GlobalShortcut(keyCode: UInt32(event.keyCode), modifiers: bits)
    }
}

enum HoverSensitivity: String, CaseIterable, Codable {
    case precise, balanced, relaxed
    var delay: TimeInterval { switch self { case .precise: return 0.18; case .balanced: return Motion.hoverDebounce; case .relaxed: return 0.04 } }
    var padding: CGFloat { switch self { case .precise: return 0; case .balanced: return 6; case .relaxed: return 16 } }
}
enum PanelSize: String, CaseIterable, Codable {
    case compact, standard, roomy
    var width: CGFloat { switch self { case .compact: return 400; case .standard: return 420; case .roomy: return 500 } }
}
enum OriginalPolicy: String, CaseIterable, Codable {
    case keep, replace
    var title: String { self == .keep ? String(localized: "Keep both cards") : String(localized: "Replace source card") }
}

/// A single Codable snapshot avoids mismatched defaults across onboarding, Settings and workers.
/// Replacement is a shelf policy: original files on disk are never overwritten.
struct SettingsSnapshot: Codable, Equatable {
    var onboardingComplete = false
    var hoverEnabled = true
    var suggestRecentActions = true
    var hoverSensitivity: HoverSensitivity = .balanced
    var panelSize: PanelSize = .standard
    var displayID: UInt32? = nil // nil follows cursor; 0 means primary
    var keepShelf = true
    var autoClearDays = 0 // zero disables expiration
    var saveLocationBookmark: Data? = nil
    var compression = QualityPreset.balanced.rawValue
    var outputFormat = ImageFormat.png.rawValue
    var originals: OriginalPolicy = .keep
    var shortcut: GlobalShortcut? = .standard

    init() {}
    enum CodingKeys: String, CodingKey {
        case onboardingComplete, hoverEnabled, suggestRecentActions, hoverSensitivity, panelSize, displayID, keepShelf, autoClearDays
        case saveLocationBookmark, compression, outputFormat, originals, shortcut
    }
    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ type: T.Type, _ key: CodingKeys, fallback: T) -> T {
            (try? values.decodeIfPresent(type, forKey: key)) ?? fallback
        }
        onboardingComplete = read(Bool.self, .onboardingComplete, fallback: onboardingComplete)
        hoverEnabled = read(Bool.self, .hoverEnabled, fallback: hoverEnabled)
        suggestRecentActions = read(Bool.self, .suggestRecentActions, fallback: suggestRecentActions)
        hoverSensitivity = read(HoverSensitivity.self, .hoverSensitivity, fallback: hoverSensitivity)
        panelSize = read(PanelSize.self, .panelSize, fallback: panelSize)
        displayID = try? values.decodeIfPresent(UInt32.self, forKey: .displayID)
        keepShelf = read(Bool.self, .keepShelf, fallback: keepShelf)
        autoClearDays = min(3650, max(0, read(Int.self, .autoClearDays, fallback: autoClearDays)))
        saveLocationBookmark = try? values.decodeIfPresent(Data.self, forKey: .saveLocationBookmark)
        let savedCompression = read(String.self, .compression, fallback: compression)
        compression = QualityPreset(rawValue: savedCompression)?.rawValue ?? compression
        let savedFormat = read(String.self, .outputFormat, fallback: outputFormat)
        outputFormat = ImageFormat(rawValue: savedFormat)?.rawValue ?? outputFormat
        originals = read(OriginalPolicy.self, .originals, fallback: originals)
        // Missing means an older schema; explicit null means the user cleared it.
        if values.contains(.shortcut) { shortcut = try? values.decodeIfPresent(GlobalShortcut.self, forKey: .shortcut) }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    @Published var value: SettingsSnapshot { didSet { persist() } }
    @Published private(set) var error: String?
    private let defaults: UserDefaults
    private var scopedSaveLocation: URL?
    private var hasScopedSaveLocation = false
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        value = BrandMigration.settingsData(in: defaults).flatMap { try? JSONDecoder().decode(SettingsSnapshot.self, from: $0) } ?? SettingsSnapshot()
        resolveSaveLocation()
    }
    var compressionPreset: QualityPreset { QualityPreset(rawValue: value.compression) ?? .balanced }
    var imageFormat: ImageFormat {
        let format = ImageFormat(rawValue: value.outputFormat) ?? .png
        return ImageFormat.supported.contains(format) ? format : .png
    }
    var saveLocation: URL? { scopedSaveLocation }
    func setSaveLocation(_ url: URL?) {
        do {
            let data = try url?.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            releaseSaveLocation()
            value.saveLocationBookmark = data
            error = nil
            resolveSaveLocation()
        } catch { self.error = String(localized: "Couldn’t remember that folder. Please choose it again.") }
    }
    func chooseSaveLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.prompt = String(localized: "Use folder")
        panel.directoryURL = saveLocation
        if panel.runModal() == .OK { setSaveLocation(panel.url) }
    }
    private func resolveSaveLocation() {
        guard let data = value.saveLocationBookmark else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale)
            let scoped = url.startAccessingSecurityScopedResource()
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else {
                if scoped { url.stopAccessingSecurityScopedResource() }
                error = String(localized: "Your save folder is unavailable. Choose another folder in Shelf settings.")
                return
            }
            scopedSaveLocation = url
            hasScopedSaveLocation = scoped
            if stale { value.saveLocationBookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) }
        } catch { self.error = String(localized: "Your save folder is unavailable. Choose another folder in Shelf settings.") }
    }
    private func persist() {
        do { defaults.set(try JSONEncoder().encode(value), forKey: "notchi.settings.v1") }
        catch { self.error = String(localized: "Couldn’t save settings.") }
    }
    func setAutoClearDays(_ days: Int) { value.autoClearDays = min(3650, max(0, days)) }
    func resetGeneral() {
        value.hoverEnabled = true; value.hoverSensitivity = .balanced
        value.panelSize = .standard; value.displayID = nil
        LoginItemManager.shared.setEnabled(false)
    }
    private func releaseSaveLocation() {
        if hasScopedSaveLocation { scopedSaveLocation?.stopAccessingSecurityScopedResource() }
        scopedSaveLocation = nil; hasScopedSaveLocation = false
    }
    func stop() { releaseSaveLocation() }
}
