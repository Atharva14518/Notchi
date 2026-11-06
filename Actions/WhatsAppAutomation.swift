import AppKit
import ApplicationServices

enum WhatsAppAutomationError: LocalizedError {
    case permission, unavailable, busy, focusChanged, changed, selection, recipients
    var errorDescription: String? {
        switch self {
        case .permission: return String(localized: "Accessibility unconfirmed. Open permission help.")
        case .unavailable: return String(localized: "Unlock WhatsApp and open any chat once, then retry. You’ll choose the actual recipients in the sharing picker.")
        case .busy: return String(localized: "Finish or cancel the existing WhatsApp dialog or attachment draft, then retry.")
        case .focusChanged: return String(localized: "WhatsApp lost focus. Retry.")
        case .changed: return String(localized: "WhatsApp’s controls weren’t available. Cancel any open WhatsApp draft and retry, or use Show files.")
        case .selection: return String(localized: "Couldn’t confirm the attachment selection. No Send button was pressed. Use Show files or retry.")
        case .recipients: return String(localized: "Cancel this draft and retry.")
        }
    }
}

/// There is intentionally no send/forward operation in this interface.
enum WhatsAppControl: String, Sendable {
    case attach = "ChatBar_AttachMediaButton"
    case document = "WAActionSheetController_Document"
    case audience = "WAMultiSendBottomBarView_AudienceSelector_ContactChip"
}
protocol WhatsAppUIDriving: Sendable {
    func validateIdle() async throws
    func press(_ control: WhatsAppControl) async throws
    func chooseFiles(_ urls: [URL]) async throws
    func clearPreselectedRecipients() async throws
}

enum WhatsAppAutomation {
    static var hasAccess: Bool {
        PermissionManager.currentTrust()
    }
    static func prepare(files: [URL], driver: any WhatsAppUIDriving) async throws {
        try Task.checkCancellation()
        try await driver.validateIdle()
        try Task.checkCancellation()
        try await driver.press(.attach)
        try Task.checkCancellation()
        try await driver.press(.document)
        try Task.checkCancellation()
        try await driver.chooseFiles(files)
        try Task.checkCancellation()
        try await driver.press(.audience)
        try Task.checkCancellation()
        try await driver.clearPreselectedRecipients()
        // Stop here. WhatsApp owns searching/selecting contacts and the final
        // Send button. We neither choose a contact nor report delivery.
    }

    @MainActor
    static func openRecipients(app: InstalledSendApp, files: [URL]) async throws {
        guard hasAccess else { throw WhatsAppAutomationError.permission }
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.id).first else {
            throw WhatsAppAutomationError.unavailable
        }
        try await prepare(files: files, driver: WhatsAppAXDriver(pid: running.processIdentifier))
    }
}

/// Blocking AX IPC stays off MainActor and has a short per-message timeout.
/// Only identifiers/roles are inspected in the chat UI, never message contents
/// or contact names. Chat and sidebar histories are pruned during traversal.
actor WhatsAppAXDriver: WhatsAppUIDriving {
    private let pid: pid_t
    private let app: AXUIElement
    private static let pruned = Set(["ChatMessagesTableView", "ChatListView_TableView"])
    init(pid: pid_t) {
        self.pid = pid; app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
    }

    func validateIdle() async throws {
        try await foreground()
        let nodes = tree(app)
        guard !nodes.contains(where: { ["MultiSend_BackButton", "open-panel", "GoToWindow", "PickerView_SearchBar", "ForwardPicker_SearchTextField"].contains(id($0)) }) else {
            throw WhatsAppAutomationError.busy
        }
        guard nodes.contains(where: { id($0) == WhatsAppControl.attach.rawValue }) else { throw WhatsAppAutomationError.unavailable }
    }
    func press(_ control: WhatsAppControl) async throws {
        let node = try await wait { self.find(control.rawValue) }
        try await foreground()
        try click(node)
    }
    func chooseFiles(_ urls: [URL]) async throws {
        guard let parent = urls.first?.deletingLastPathComponent(), !urls.isEmpty,
              urls.allSatisfy({ $0.isFileURL && $0.deletingLastPathComponent() == parent && FileManager.default.isReadableFile(atPath: $0.path) }) else {
            throw WhatsAppAutomationError.selection
        }
        let panel = try await wait { self.find("open-panel") }
        try await foreground()
        _ = AXUIElementPerformAction(panel, kAXRaiseAction as CFString)
        try await key(5, flags: [.maskCommand, .maskShift]) // Go to Folder, inside the verified file picker only.
        let path = try await wait { self.find("PathTextField") }
        try await foreground()
        _ = AXUIElementSetAttributeValue(path, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        guard AXUIElementSetAttributeValue(path, kAXValueAttribute as CFString, parent.path as CFString) == .success else {
            throw WhatsAppAutomationError.selection
        }
        guard string(path, kAXValueAttribute) == parent.path else { throw WhatsAppAutomationError.selection }
        try await key(36) // Return in the verified Go to Folder field, never the composer.
        _ = try await wait { self.find("PathTextField") == nil ? self.find("open-panel") : nil }
        if find("ListView") == nil { try await key(19, flags: .maskCommand) } // List view, if needed.
        let list = try await wait { self.find("ListView") }
        let expected = Set(urls.map(Self.canonical))
        let rows = children(list).filter { string($0, kAXRoleAttribute) == kAXRowRole }
        let selected = rows.filter { row in tree(row, limit: 30).contains { node in
            fileURL(node).map { expected.contains(Self.canonical($0)) } ?? false
        } }
        guard selected.count == expected.count,
              AXUIElementSetAttributeValue(list, kAXSelectedRowsAttribute as CFString, selected as CFArray) == .success else {
            throw WhatsAppAutomationError.selection
        }
        let actualRows = attribute(list, kAXSelectedRowsAttribute) as? [AXUIElement] ?? []
        let actual = Set(actualRows.flatMap { tree($0, limit: 30).compactMap(fileURL).map(Self.canonical) })
        guard actual == expected else { throw WhatsAppAutomationError.selection }
        try await foreground()
        guard find("PathTextField") == nil, find("open-panel") != nil,
              let open = find("OKButton") else { throw WhatsAppAutomationError.selection }
        try click(open)
        // Opening a file produces an attachment preview, not a message. The
        // audience selector must appear before the next step can continue.
        _ = try await wait { self.find(WhatsAppControl.audience.rawValue) }
    }
    func clearPreselectedRecipients() async throws {
        _ = try await wait { self.find("ForwardPicker_SearchTextField") }
        for _ in 0..<20 {
            try await foreground()
            let nodes = tree(app)
            let checked = nodes.first { node in
                string(node, kAXRoleAttribute) == kAXCheckBoxRole
                    && (attribute(node, kAXValueAttribute) as? NSNumber)?.boolValue == true
                    && hasRecipientAncestor(node)
            }
            if let checked {
                try await foreground()
                try click(checked)
                try await Task.sleep(for: .milliseconds(100))
            } else {
                // WhatsApp hides Send when no recipient is selected; some
                // builds disable it instead. Never activate this control.
                guard find("ForwardPicker_SearchTextField") != nil else { throw WhatsAppAutomationError.recipients }
                if let send = find("ForwardPickerView_ForwardButton"),
                   (attribute(send, kAXEnabledAttribute) as? NSNumber)?.boolValue != false {
                    throw WhatsAppAutomationError.recipients
                }
                return
            }
        }
        throw WhatsAppAutomationError.recipients
    }

    private func foreground() async throws {
        try Task.checkCancellation()
        guard WhatsAppAutomation.hasAccess else { throw WhatsAppAutomationError.permission }
        let active = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        guard active == pid else { throw WhatsAppAutomationError.focusChanged }
    }
    private func wait(_ probe: () -> AXUIElement?) async throws -> AXUIElement {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            try await foreground()
            if let node = probe() { return node }
            try await Task.sleep(for: .milliseconds(120))
        }
        throw WhatsAppAutomationError.changed
    }
    private func click(_ node: AXUIElement) throws {
        try Task.checkCancellation()
        guard (attribute(node, kAXEnabledAttribute) as? NSNumber)?.boolValue != false,
              AXUIElementPerformAction(node, kAXPressAction as CFString) == .success else { throw WhatsAppAutomationError.changed }
    }
    private func find(_ identifier: String) -> AXUIElement? { tree(app).first { id($0) == identifier } }
    private func id(_ node: AXUIElement) -> String { string(node, kAXIdentifierAttribute) }
    private func tree(_ root: AXUIElement, limit: Int = 700) -> [AXUIElement] {
        var result: [AXUIElement] = [], stack = [(root, 0)]
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while let (node, depth) = stack.popLast(), result.count < limit, ContinuousClock.now < deadline {
            result.append(node)
            if depth < 24 && !Self.pruned.contains(id(node)) { stack += children(node).reversed().map { ($0, depth + 1) } }
        }
        return result
    }
    private func hasRecipientAncestor(_ node: AXUIElement) -> Bool {
        var current: AXUIElement? = node
        for _ in 0..<5 {
            guard let element = current else { return false }
            if id(element).hasPrefix("ForwardPicker_") { return true }
            current = attribute(element, kAXParentAttribute).map { $0 as! AXUIElement }
        }
        return false
    }
    private func attribute(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(node, 0.5)
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success ? value : nil
    }
    private func string(_ node: AXUIElement, _ name: String) -> String { attribute(node, name) as? String ?? "" }
    private func children(_ node: AXUIElement) -> [AXUIElement] { attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    private func fileURL(_ node: AXUIElement) -> URL? {
        if let url = attribute(node, kAXURLAttribute) as? URL, url.isFileURL { return url }
        return nil
    }
    private static func canonical(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }
    private func key(_ code: CGKeyCode, flags: CGEventFlags = []) async throws {
        try await foreground()
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            event?.flags = flags; event?.post(tap: .cghidEventTap)
        }
    }
}
