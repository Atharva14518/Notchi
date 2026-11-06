import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var files: [ShelfItem] = []
    @Published var selectedIDs: Set<UUID> = []
    @Published var activeID: UUID?
    @Published var hoveredID: UUID?
    @Published var draggingOutID: UUID?
    @Published private(set) var removingIDs: Set<UUID> = []
    @Published var isExpanded = false
    @Published var isPinned = false
    @Published var isDropTargeted = false
    @Published var isSystemDragActive = false
    @Published private(set) var isImporting = false
    @Published private(set) var gulpToken = 0
    @Published var message: String?
    @Published var hasError = false
    @Published var isPresentingDialog = false
    private var restoreFailed = false
    private var settings: SettingsStore?
    private var settingsSubscription: AnyCancellable?
    private var expirationTimer: Timer?
    private let persistence: any ShelfPersistence
    private var scopedURLs: Set<URL> = []
    private var records: [UUID: ShelfBookmark] = [:]
    private var unavailableRecords: [ShelfBookmark] = []
    private var dropSession: UUID?
    private var claimedSessions: Set<UUID> = []
    private var importCount = 0
    let importer: DropImporter

    init(persistence: any ShelfPersistence = BookmarkShelfPersistence(), importer: DropImporter = DropImporter(), settings: SettingsStore? = nil) {
        self.persistence = persistence
        self.importer = importer
        self.settings = settings
        if settings?.value.keepShelf != false { restore() }
        else { save() }
        if let settings {
            settingsSubscription = settings.$value.map { ($0.keepShelf, $0.autoClearDays) }
                .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
                .dropFirst() // Initial restore already applied retention; never overwrite an unreadable index.
                .sink { [weak self] value in
                    // @Published emits before assignment; use the incoming value.
                    self?.expire(olderThanDays: value.1)
                    if self?.restoreFailed != true || !value.0 { self?.save(keep: value.0) }
                }
            let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.isImporting else { return }
                    self.expire(olderThanDays: self.settings?.value.autoClearDays ?? 0)
                }
            }
            RunLoop.main.add(timer, forMode: .common); expirationTimer = timer
        }
    }
    deinit { expirationTimer?.invalidate() }
    var activeItem: ShelfItem? { files.first { $0.id == activeID } }
    var selectedItems: [ShelfItem] { files.filter { selectedIDs.contains($0.id) } }

    func select(_ item: ShelfItem, extending: Bool = false) {
        activeID = item.id
        if extending {
            if !selectedIDs.insert(item.id).inserted { selectedIDs.remove(item.id) }
        } else { selectedIDs = [item.id] }
    }

    func add(_ urls: [URL], isNew: Bool = false, originalSize: Int64? = nil, beside source: UUID? = nil, expand: Bool = true) {
        var additions: [ShelfItem] = []
        for url in urls where url.isFileURL {
            let normalized = url.standardizedFileURL
            guard !files.contains(where: { $0.url.path == normalized.path }), !additions.contains(where: { $0.url.path == normalized.path }) else { continue }
            let scoped = normalized.startAccessingSecurityScopedResource()
            guard FileManager.default.fileExists(atPath: normalized.path) else {
                if scoped { normalized.stopAccessingSecurityScopedResource() }
                report(String(localized: "One file is no longer available. You can drop it again."))
                continue
            }
            if scoped { scopedURLs.insert(normalized) }
            let item = ShelfItem(url: normalized, isNew: isNew, originalSize: originalSize)
            additions.append(item)
            makeBookmark(for: item)
        }
        if let source, let index = files.firstIndex(where: { $0.id == source }) {
            files.insert(contentsOf: additions, at: index + 1)
        } else { files.append(contentsOf: additions) }
        save()
        if expand { isExpanded = true }
    }

    func addActionResult(_ result: ActionResult, source: ShelfItem, policy: OriginalPolicy, expand: Bool = true) {
        guard !result.outputs.isEmpty else { return }
        add(result.outputs, isNew: true,
            originalSize: result.outputs.count == 1 ? result.comparison?.before : nil, beside: source.id, expand: expand)
        // Only replace the shelf card after every output was accepted.
        if policy == .replace, result.outputs.allSatisfy({ output in files.contains { $0.url == output.standardizedFileURL } }),
           !result.outputs.contains(source.url), let original = files.first(where: { $0.id == source.id }) { remove(original) }
    }

    func remove(_ file: ShelfItem) {
        files.removeAll { $0.id == file.id }
        records[file.id] = nil
        selectedIDs.remove(file.id)
        if activeID == file.id { activeID = nil }
        removingIDs.remove(file.id)
        if scopedURLs.remove(file.url) != nil { file.url.stopAccessingSecurityScopedResource() }
        save()
    }

    func animateRemoval(_ file: ShelfItem) {
        guard !removingIDs.contains(file.id) else { return }
        removingIDs.insert(file.id)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Motion.poofDuration))
            self?.remove(file)
        }
    }

    func clear() {
        releaseScopes()
        files.removeAll()
        selectedIDs.removeAll()
        activeID = nil
        records.removeAll()
        unavailableRecords.removeAll()
        message = nil
        hasError = false
        save()
    }

    func shutdown() {
        expirationTimer?.invalidate(); expirationTimer = nil
        settingsSubscription = nil
        releaseScopes()
    }
    private func releaseScopes() {
        for url in scopedURLs { url.stopAccessingSecurityScopedResource() }
        scopedURLs.removeAll()
    }

    func chooseFiles() {
        isPresentingDialog = true
        defer { isPresentingDialog = false }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = String(localized: "Add to shelf")
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func systemDragChanged(_ active: Bool) {
        if active && !isSystemDragActive { dropSession = UUID() }
        isSystemDragActive = active
        if !active { draggingOutID = nil }
        if active { isExpanded = true }
    }

    func setDropTargeted(_ targeted: Bool) {
        if targeted && !isDropTargeted && !isSystemDragActive { dropSession = UUID() }
        isDropTargeted = targeted
        if targeted { isExpanded = true }
    }

    func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        let supported = providers.filter(DropImporter.supports)
        guard !supported.isEmpty, claimDrop() else { return !supported.isEmpty }
        beginImport()
        let boxes = supported.map(ProviderBox.init)
        Task { [weak self, importer] in
            let result = await importer.resolve(providers: boxes)
            await self?.finishImport(result)
        }
        return true
    }

    func acceptPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        let payloads = PasteboardDrop.read(pasteboard)
        guard !payloads.isEmpty, claimDrop() else { return !payloads.isEmpty }
        beginImport()
        Task { [weak self, importer] in
            let result = await importer.resolve(payloads: payloads)
            await self?.finishImport(result)
        }
        return true
    }

    private func claimDrop() -> Bool {
        let session = dropSession ?? UUID()
        if claimedSessions.contains(session) { return false }
        claimedSessions.insert(session)
        if claimedSessions.count > 64 { claimedSessions = [session] }
        return true
    }
    private func beginImport() {
        importCount += 1
        isImporting = true
        isExpanded = true
        hasError = false
        message = String(localized: "bringing that in…")
    }
    private func finishImport(_ result: DropImportResult) async {
        if !result.urls.isEmpty {
            gulpToken += 1
            try? await Task.sleep(for: .seconds(Motion.gulpBeat * 2))
            add(result.urls)
        }
        importCount -= 1
        isImporting = importCount > 0
        isDropTargeted = false
        if !result.errors.isEmpty { report(result.errors.joined(separator: " ")) }
        else { message = nil }
    }

    func report(_ message: String) { self.message = message; hasError = true }

    private func restore() {
        do {
            for record in try persistence.read() {
                if let days = settings?.value.autoClearDays, days > 0,
                   record.addedAt <= Date().addingTimeInterval(-Double(days) * 86400) { continue }
                do {
                    var stale = false
                    let url = try URL(resolvingBookmarkData: record.bookmark,
                                      options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale)
                    if files.contains(where: { $0.url.path == url.path }) { continue }
                    let scoped = url.startAccessingSecurityScopedResource()
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        if scoped { url.stopAccessingSecurityScopedResource() }
                        unavailableRecords.append(record)
                        continue
                    }
                    if scoped { scopedURLs.insert(url) }
                    let item = ShelfItem(url: url, id: record.id, addedAt: record.addedAt,
                                         isNew: record.isNew, originalSize: record.originalSize)
                    files.append(item)
                    records[item.id] = record
                    if stale { makeBookmark(for: item) }
                } catch { unavailableRecords.append(record) }
            }
            if !unavailableRecords.isEmpty { message = String(localized: "Some saved files are offline. They’ll be tried next launch.") }
            save()
        } catch { restoreFailed = true; report(String(localized: "Couldn’t restore your shelf. The saved index has been kept.")) }
    }
    private func makeBookmark(for item: ShelfItem) {
        do {
            let bookmark = try item.url.bookmarkData(options: .withSecurityScope,
                includingResourceValuesForKeys: [.contentTypeKey, .fileSizeKey], relativeTo: nil)
            records[item.id] = ShelfBookmark(id: item.id, bookmark: bookmark, addedAt: item.addedAt,
                                             isNew: item.isNew, originalSize: item.originalSize)
        } catch { report(String(localized: "That file is usable now, but macOS couldn’t save its access for next launch.")) }
    }
    func expire(olderThanDays days: Int, now: Date = Date()) {
        guard days > 0, !restoreFailed else { return }
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)
        for file in files where file.addedAt <= cutoff { remove(file) }
        unavailableRecords.removeAll { $0.addedAt <= cutoff }
        save()
    }
    private func save(keep: Bool? = nil) {
        do { try persistence.write((keep ?? settings?.value.keepShelf ?? true) ? files.compactMap { records[$0.id] } + unavailableRecords : []) }
        catch { report(String(localized: "Couldn’t save the shelf index. Your original files are safe.")) }
    }
}
