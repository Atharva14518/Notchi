import SwiftUI
import AppKit

struct ContinuityCameraButton: NSViewRepresentable {
    @ObservedObject var scanner: ScanCoordinator
    func makeNSView(context: Context) -> CameraButton {
        let button = CameraButton(frame: .zero)
        button.title = String(localized: "iPhone"); button.isBordered = false; button.focusRingType = .none
        button.setAccessibilityLabel(String(localized: "Import from iPhone"))
        button.target = button; button.action = #selector(CameraButton.openMenu)
        return button
    }
    func updateNSView(_ view: CameraButton, context: Context) { view.scanner = scanner; view.isEnabled = !scanner.isBusy }
    final class CameraButton: NSButton, NSServicesMenuRequestor {
        weak var scanner: ScanCoordinator?
        private var hovering = false
        private var hoverArea: NSTrackingArea?
        override var acceptsFirstResponder: Bool { true }
        override func becomeFirstResponder() -> Bool { let result = super.becomeFirstResponder(); needsDisplay = true; return result }
        override func resignFirstResponder() -> Bool { let result = super.resignFirstResponder(); needsDisplay = true; return result }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let hoverArea { removeTrackingArea(hoverArea) }
            let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
            addTrackingArea(area); hoverArea = area
        }
        override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
        override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
        override func draw(_ dirtyRect: NSRect) {
            let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 16, yRadius: 16)
            NSColor(Color.acid).withAlphaComponent(isEnabled ? (hovering ? 0.18 : 0.12) : 0.05).setFill(); shape.fill()
            NSColor(Color.acid).withAlphaComponent(isEnabled ? 0.35 : 0.14).setStroke(); shape.lineWidth = 1; shape.stroke()
            let font = Typography.appKitFont(size: 12, weight: .semibold)
            let label = NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: NSColor(Color.acid).withAlphaComponent(isEnabled ? 1 : 0.4)])
            label.draw(at: NSPoint(x: (bounds.width - label.size().width) / 2, y: (bounds.height - label.size().height) / 2))
            if window?.firstResponder === self { NSColor(Color.acid).setStroke(); shape.lineWidth = 2; shape.stroke() }
        }
        override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
            if let type = returnType, Self.accepts(type) { return self }
            return super.validRequestor(forSendType: sendType, returnType: returnType)
        }
        static func accepts(_ type: NSPasteboard.PasteboardType) -> Bool {
            NSImage.imageTypes.contains(type.rawValue) || [.pdf, .fileURL].contains(type)
        }
        func readSelection(from pasteboard: NSPasteboard) -> Bool {
            var inputs: [ScanInput] = []
            for item in pasteboard.pasteboardItems ?? [] {
                if let data = item.data(forType: .pdf) { inputs.append(.data(data)); continue }
                if let value = item.string(forType: .fileURL), let url = URL(string: value), url.isFileURL { inputs.append(.file(url)); continue }
                if let type = item.availableType(from: [.png, .tiff]), let data = item.data(forType: type) { inputs.append(.data(data)) }
            }
            if inputs.isEmpty, let image = NSImage(pasteboard: pasteboard), let data = image.tiffRepresentation { inputs = [.data(data)] }
            guard !inputs.isEmpty, let scanner else { return false }
            scanner.importInputs(inputs); return true
        }
        override func mouseDown(with event: NSEvent) { if isEnabled { showMenu(event) } }
        @objc func openMenu() {
            guard isEnabled, let window,
                  let event = NSEvent.mouseEvent(with: .leftMouseDown, location: convert(CGPoint(x: bounds.midX, y: bounds.midY), to: nil), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { return }
            showMenu(event)
        }
        private func showMenu(_ event: NSEvent) {
            window?.makeFirstResponder(self)
            let menu = NSMenu(title: String(localized: "Import from iPhone"))
            menu.font = Typography.appKitFont(size: 12)
            menu.allowsContextMenuPlugIns = true
            let help = NSMenuItem(title: String(localized: "Nearby devices"), action: nil, keyEquivalent: "")
            help.isEnabled = false; menu.addItem(help)
            // AppKit inserts its Continuity Camera section for this contextual
            // menu when validRequestor advertises image/PDF reception. No private selectors.
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }
}
