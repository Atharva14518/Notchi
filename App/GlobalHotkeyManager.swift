import AppKit
import Carbon
import Combine

@MainActor
final class GlobalHotkeyManager: ObservableObject {
    static let shared = GlobalHotkeyManager()
    @Published private(set) var error: String?
    @Published private(set) var isRecording = false
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var monitor: Any?
    private var sequence: UInt32 = 0
    private var activeID: UInt32 = 0
    private var settings: SettingsStore?
    private var subscription: AnyCancellable?
    private var action: (() -> Void)?
    private var configured: GlobalShortcut?
    private var configuredOnce = false

    func start(settings: SettingsStore, action: @escaping () -> Void) {
        stop()
        self.settings = settings; self.action = action
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr else { return result }
            let identifier = id.id
            let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                if !manager.isRecording && identifier == manager.activeID { manager.action?() }
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { error = String(localized: "Couldn’t install the shortcut handler (\(status))."); return }
        subscription = settings.$value.map(\.shortcut).removeDuplicates().sink { [weak self] shortcut in
            self?.apply(shortcut)
        }
    }
    private func apply(_ shortcut: GlobalShortcut?) {
        guard !isRecording else { return }
        guard !configuredOnce || shortcut != configured else { return }
        guard let shortcut else {
            if let hotkey { UnregisterEventHotKey(hotkey) }
            hotkey = nil; configured = nil; configuredOnce = true; error = nil; return
        }
        sequence &+= 1
        let id = EventHotKeyID(signature: 0x4E54434C, id: sequence) // NTCL
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &replacement)
        guard status == noErr else {
            let message = String(localized: "That shortcut is unavailable (\(status)). Choose another combination.")
            error = message
            // Restore the old preference and, after recording, its registration.
            let previous = configured
            if hotkey == nil { configuredOnce = false }
            Task { @MainActor [weak self] in
                self?.settings?.value.shortcut = previous
                self?.error = message
            }
            return
        }
        if let hotkey { UnregisterEventHotKey(hotkey) }
        hotkey = replacement; activeID = sequence; configured = shortcut; configuredOnce = true; error = nil
    }
    func beginRecording() {
        cancelRecording(resume: false); error = nil; isRecording = true
        // Release our own combination so recording it again reaches the local monitor.
        if let hotkey { UnregisterEventHotKey(hotkey) }
        hotkey = nil
        // This monitor only sees this app's events while the recorder is focused.
        // Carbon handles the registered global shortcut without Accessibility.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, self.isRecording else { return false }
                if event.keyCode == 53 { self.cancelRecording(); return true }
                if event.keyCode == 51 || event.keyCode == 117 {
                    self.settings?.value.shortcut = nil; self.cancelRecording(); return true
                }
                guard let shortcut = GlobalShortcut.from(event) else {
                    self.error = String(localized: "Use ⌘, ⌃ or ⌥ with a letter, number, arrow or Space."); return true
                }
                self.settings?.value.shortcut = shortcut
                self.cancelRecording()
                return true
            }
            return consumed ? nil : event
        }
    }
    func cancelRecording(resume: Bool = true) {
        let wasRecording = isRecording
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; isRecording = false
        if wasRecording && resume, let settings {
            configuredOnce = false
            apply(settings.value.shortcut)
        }
    }
    func stop() {
        cancelRecording(resume: false); subscription = nil
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let handler { RemoveEventHandler(handler) }
        hotkey = nil; handler = nil; action = nil; settings = nil
        configuredOnce = false; configured = nil
    }
}
