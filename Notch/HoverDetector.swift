import AppKit

/// Pure timing logic, shared by event monitors and the drag/warp watchdog.
struct HoverIntent {
    private var enteredAt: TimeInterval?
    private var exitedAt: TimeInterval?

    mutating func update(inside: Bool, expanded: Bool, heldOpen: Bool, now: TimeInterval, debounce: TimeInterval = Motion.hoverDebounce) -> Bool? {
        if inside {
            exitedAt = nil
            if enteredAt == nil { enteredAt = now }
            if !expanded, now - (enteredAt ?? now) + 0.000001 >= debounce { return true }
        } else {
            enteredAt = nil
            if heldOpen { exitedAt = nil; return nil }
            if exitedAt == nil { exitedAt = now }
            if expanded, now - (exitedAt ?? now) + 0.000001 >= Motion.collapseDelay { return false }
        }
        return nil
    }
}

@MainActor
final class HoverDetector {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var watchdog: Timer?
    private var dragged = false
    private var onSample: ((CGPoint, Bool, Bool) -> Void)?
    private var dragTracker = SystemDragTracker(changeCount: NSPasteboard(name: .drag).changeCount)

    func start(globalEnabled: Bool = true, onSample: @escaping (CGPoint, Bool, Bool) -> Void) {
        stop()
        self.onSample = onSample
        dragTracker = SystemDragTracker(changeCount: NSPasteboard(name: .drag).changeCount)
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .rightMouseDragged,
                                          .otherMouseDragged, .leftMouseUp, .rightMouseUp, .otherMouseUp]
        if globalEnabled { globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.sample(event) }
        }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.sample(event) }
            return event // Never swallow another view's event.
        }
        // Finder drag loops and cursor warps can omit monitor callbacks. This also
        // evaluates pending debounce deadlines when the pointer stops moving.
        let timer = Timer(timeInterval: Motion.hoverWatchdog, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample(nil) }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
        sample(nil)
    }

    private func sample(_ event: NSEvent?) {
        if let type = event?.type, [.leftMouseDragged, .rightMouseDragged, .otherMouseDragged].contains(type) {
            dragged = true
        }
        if NSEvent.pressedMouseButtons == 0 { dragged = false }
        // A held button also protects drags whose nested event loop swallowed
        // the initial mouseDragged callback.
        let pasteboard = NSPasteboard(name: .drag)
        let systemDrag = dragTracker.update(changeCount: pasteboard.changeCount,
            buttonDown: NSEvent.pressedMouseButtons & 1 != 0,
            mouseDown: event?.type == .leftMouseDown, mouseDragged: event?.type == .leftMouseDragged,
            hasPayload: !(pasteboard.types ?? []).isEmpty)
        onSample?(NSEvent.mouseLocation, dragged || NSEvent.pressedMouseButtons != 0, systemDrag)
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        watchdog?.invalidate()
        watchdog = nil
        dragged = false
        onSample = nil
    }
}
