import AppKit
import SwiftUI
import Combine

@MainActor
final class NotchPanelController {
    let panel = NotchPanel()
    private let store: ShelfStore
    private let actions: ActionCoordinator
    private let sharing = ShareAction()
    private let scanner = ScanCoordinator()
    private let links = LinkCoordinator.shared
    private let hover = HoverDetector()
    private let settings: SettingsStore
    private var lastLayoutSettings: SettingsSnapshot?
    private var presentation: OverlayPresentation?
    private var presentationMetrics: SilhouetteMetrics?
    private var hoverIntent = HoverIntent()
    private var currentScreenID: CGDirectDisplayID?
    private var subscriptions: Set<AnyCancellable> = []
    private var renderGeneration = 0
    private var isSuspended = false
    private var spaceTask: Task<Void, Never>?
    private var spaceIsSettling = false
    var hasActiveSend: Bool { sharing.isBusy }
    var hasActiveScan: Bool { scanner.isBusy }
    var hasActiveWorkspace: Bool { sharing.isPresenting || scanner.isPresenting || links.isPresenting }

    init(store: ShelfStore, actions: ActionCoordinator, settings: SettingsStore) {
        self.store = store
        self.actions = actions
        self.settings = settings
        actions.scanHandler = { [weak scanner] item, mode in scanner?.recognize(item, mode: mode) }
        configureScreen(at: NSEvent.mouseLocation, force: true)
        store.$isExpanded.removeDuplicates().sink { [weak self] expanded in
            guard let self else { return }
            self.presentation?.transition(to: expanded,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            self.updateMousePassThrough()
        }.store(in: &subscriptions)
        store.$files.map { $0.isEmpty }.removeDuplicates().sink { [weak self] empty in
            guard let self else { return }
            self.presentation?.setContentHeight((self.sharing.isPresenting || self.scanner.isPresenting || self.links.isPresenting) ? PanelLayout.workspaceHeight : (empty ? PanelLayout.emptyHeight : PanelLayout.shelfHeight),
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        }.store(in: &subscriptions)
        sharing.$session.map { $0 != nil }.removeDuplicates().sink { [weak self] open in
            guard let self else { return }
            self.presentation?.setContentHeight((open || self.scanner.isPresenting) ? PanelLayout.workspaceHeight : (self.store.files.isEmpty ? PanelLayout.emptyHeight : PanelLayout.shelfHeight),
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            if open { self.store.isExpanded = true }
        }.store(in: &subscriptions)
        sharing.$isExternalHandoffActive.removeDuplicates().sink { [weak self] active in
            guard let self else { return }
            if active {
                self.store.isPinned = false; self.store.isExpanded = false
                self.panel.resignKey(); self.panel.ignoresMouseEvents = true; self.panel.orderOut(nil)
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isSuspended, !self.sharing.isExternalHandoffActive else { return }
                    if self.sharing.toast?.isError == true { self.store.isExpanded = true }
                    self.panel.orderFrontRegardless(); self.updateMousePassThrough()
                }
            }
        }.store(in: &subscriptions)
        scanner.$isPresenting.removeDuplicates().sink { [weak self] open in
            guard let self else { return }
            self.presentation?.setContentHeight((open || self.sharing.isPresenting) ? PanelLayout.workspaceHeight : (self.store.files.isEmpty ? PanelLayout.emptyHeight : PanelLayout.shelfHeight),
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            if open { self.store.isExpanded = true }
        }.store(in: &subscriptions)
        links.$isPresenting.removeDuplicates().sink { [weak self] open in
            guard let self else { return }
            self.presentation?.setContentHeight((open || self.sharing.isPresenting || self.scanner.isPresenting) ? PanelLayout.workspaceHeight : (self.store.files.isEmpty ? PanelLayout.emptyHeight : PanelLayout.shelfHeight),
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            if open { self.store.isExpanded = true }
        }.store(in: &subscriptions)
        scanner.$isCapturing.removeDuplicates().sink { [weak self] capturing in
            guard let self else { return }
            if capturing { self.panel.ignoresMouseEvents = true; self.panel.orderOut(nil) }
            else if !self.isSuspended && !self.sharing.isExternalHandoffActive { self.panel.orderFrontRegardless() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.configureScreen(at: NSEvent.mouseLocation, force: true)
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification, object: panel)
            .sink { [weak self] _ in self?.updateMousePassThrough() }.store(in: &subscriptions)

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in self?.spaceChanged() }.store(in: &subscriptions)
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            workspace.publisher(for: name).sink { [weak self] _ in self?.suspend() }.store(in: &subscriptions)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.publisher(for: name).sink { [weak self] _ in self?.resume() }.store(in: &subscriptions)
        }
        settings.$value.sink { [weak self] value in
            guard let self else { return }
            let previous = self.lastLayoutSettings
            self.lastLayoutSettings = value
            if previous?.hoverSensitivity != value.hoverSensitivity { self.hoverIntent = HoverIntent() }
            if previous?.hoverEnabled != value.hoverEnabled {
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isSuspended else { return }
                    self.hoverIntent = HoverIntent()
                    self.store.systemDragChanged(false)
                    self.startHover()
                    if !self.settings.value.hoverEnabled && !self.holdsOpen { self.store.isExpanded = false }
                }
            }
            if previous?.panelSize != value.panelSize || previous?.displayID != value.displayID {
                // Read settings after @Published has committed. Defer while a native UI owns its anchor.
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.sharing.isPresenting, !self.scanner.isPresenting, !self.links.isPresenting, !self.store.isPresentingDialog, !self.actions.isPresentingDialog else { return }
                    self.configureScreen(at: NSEvent.mouseLocation, force: true)
                }
            }
        }.store(in: &subscriptions)
        startHover()
        panel.orderFrontRegardless()
    }

    private var holdsOpen: Bool {
        store.isPinned || store.isDropTargeted || store.isImporting || store.isSystemDragActive || store.isPresentingDialog || actions.isBusy
            || actions.isPresentingDialog || sharing.isPresenting || scanner.isPresenting || links.isPresenting || links.isBusy
    }

    func showShelf() {
        sharing.cancelExternalHandoff()
        if isSuspended { resume() }
        configureScreen(at: NSEvent.mouseLocation)
        store.isPinned = true
        store.isExpanded = true
        panel.orderFrontRegardless()
    }

    func showLinks() { showShelf(); links.showMyLinks() }

    func showScanner() {
        showShelf()
        scanner.open()
    }

    func stop() {
        spaceTask?.cancel()
        hover.stop()
        presentation?.stop()
        sharing.stop()
        scanner.shutdown()
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
        subscriptions.removeAll()
    }

    private func startHover() {
        // Mouse-only monitors do not require AX trust. Keep hover usable even
        // when WhatsApp automation needs its Accessibility approval repaired.
        hover.start(globalEnabled: settings.value.hoverEnabled) { [weak self] point, dragging, systemDrag in
            self?.handlePointer(point, dragging: dragging, systemDrag: systemDrag)
        }
    }

    private func handlePointer(_ point: CGPoint, dragging: Bool, systemDrag: Bool) {
        guard !isSuspended, !spaceIsSettling, !scanner.isCapturing, !sharing.isExternalHandoffActive else { return }
        let automaticDrag = settings.value.hoverEnabled && systemDrag
        if store.isSystemDragActive != automaticDrag { store.systemDragChanged(automaticDrag) }
        if !dragging { store.draggingOutID = nil; scanner.draggingPageID = nil }
        // Native dialogs and sharing popovers must keep their anchor until they close.
        if !store.isPresentingDialog && !actions.isPresentingDialog && !sharing.isPresenting && !scanner.isPresenting && !links.isPresenting {
            configureScreen(at: point)
        }
        guard let presentation else { return }
        updateMousePassThrough()
        // A collapsed silhouette can be entirely behind the physical camera.
        // It must still accept global hover intent even when WindowServer calls
        // that transparent canvas occluded. Transient ordering hides it in Exposé.
        guard !store.isExpanded || panel.occlusionState.contains(.visible) else {
            hoverIntent = HoverIntent()
            return
        }
        let geometry = presentation.geometry
        let frame = geometry.frame(expanded: true)
        let gaze = CGPoint(x: min(1, max(-1, (point.x - frame.midX) / 180)),
                           y: min(1, max(-1, (frame.midY - point.y) / 120)))
        if presentation.gaze != gaze { presentation.gaze = gaze }
        let inside = (settings.value.hoverEnabled && geometry.hotZone.insetBy(dx: -settings.value.hoverSensitivity.padding, dy: -settings.value.hoverSensitivity.padding).contains(point))
            || (store.isExpanded && frame.insetBy(dx: -6, dy: -6).contains(point))
        if let expanded = hoverIntent.update(inside: inside, expanded: store.isExpanded,
                                            heldOpen: holdsOpen || dragging, now: ProcessInfo.processInfo.systemUptime, debounce: settings.value.hoverSensitivity.delay) {
            store.isExpanded = expanded
        }
    }

    private func configureScreen(at point: CGPoint, force: Bool = false) {
        guard !isSuspended else { return }
        let screens = NSScreen.screens
        let index = NotchGeometry.screenIndex(containing: point, frames: screens.map(\.frame))
        let preferred = settings.value.displayID.flatMap { id in
            id == 0 ? NSScreen.screens.first : screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
        }
        guard let screen = preferred ?? (settings.value.displayID == nil ? index.map({ screens[$0] }) : nil) ?? screens.first else {
            panel.ignoresMouseEvents = true
            panel.orderOut(nil)
            return
        }
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        guard force || id != currentScreenID || presentation?.geometry.preferredWidth != settings.value.panelSize.width else { return }
        currentScreenID = id
        hoverIntent = HoverIntent()
        renderGeneration += 1
        let generation = renderGeneration
        var geometry = NotchGeometry(screen: screen)
        geometry.preferredWidth = settings.value.panelSize.width
        geometry.contentHeight = (sharing.isPresenting || scanner.isPresenting || links.isPresenting) ? PanelLayout.workspaceHeight : (store.files.isEmpty ? PanelLayout.emptyHeight : PanelLayout.shelfHeight)
        let expanded = store.isExpanded && holdsOpen
        store.isExpanded = expanded
        if let presentation { presentation.reset(geometry: geometry, expanded: expanded) }
        else { presentation = OverlayPresentation(geometry: geometry) }
        guard let presentation else { return }
        presentationMetrics = expanded ? geometry.expandedMetrics : geometry.collapsedMetrics
        let host = DropHostingView(rootView: NotchOverlayView(
            presentation: presentation, store: store, actions: actions, sharing: sharing, scanner: scanner, links: links,
            onPresentation: { [weak self] metrics in
                // Report interpolated bounds without publishing them back into SwiftUI.
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.renderGeneration == generation else { return }
                    self.presentationMetrics = metrics
                    self.updateMousePassThrough()
                }
            }).preferredColorScheme(.dark), store: store)
        sharing.sourceView = host
        host.blocksShelfDrop = { [weak scanner] in scanner?.isPresenting == true }
        host.scanPageDrag = { [weak self] point, finished, pasteboard in
            guard let self, let source = self.scanner.draggingPageID,
                  pasteboard.string(forType: .string) == source.uuidString else { return false }
            return self.scanner.nativePageDrag(at: CGPoint(x: point.x, y: self.panel.frame.height - point.y), finished: finished)
        }
        host.acceptsPoint = { [weak self] point in
            guard let self, let metrics = self.presentationMetrics else { return false }
            let local = CGPoint(x: point.x, y: self.panel.frame.height - point.y)
            return NotchSilhouette(metrics: metrics).path(in: CGRect(origin: .zero, size: self.panel.frame.size)).contains(local)
        }
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrame(geometry.canvasFrame, display: true)
        updateMousePassThrough()
        // Do not orderFront on every mouse movement or Space notification: the OS
        // must be free to hide the transient panel during Mission Control.
        if force && !sharing.isExternalHandoffActive { panel.orderFrontRegardless() }
    }

    private func updateMousePassThrough() {
        guard !isSuspended, !spaceIsSettling, !sharing.isExternalHandoffActive, panel.occlusionState.contains(.visible),
              let presentation else {
            panel.ignoresMouseEvents = true
            return
        }
        let metrics = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? presentation.metrics : (presentationMetrics ?? presentation.metrics)
        let r = presentation.geometry.globalFrame(for: metrics)
        // Flip to the shape's top-left coordinate system before testing rounded corners.
        let point = NSEvent.mouseLocation
        let local = CGPoint(x: point.x - r.minX, y: r.maxY - point.y)
        let shape = NotchSilhouette.outline(in: CGRect(origin: .zero, size: r.size),
                                           topRadius: metrics.topRadius, bottomRadius: metrics.bottomRadius)
        panel.ignoresMouseEvents = !shape.contains(local)
    }

    private func spaceChanged() {
        spaceTask?.cancel()
        spaceIsSettling = true
        panel.ignoresMouseEvents = true
        hoverIntent = HoverIntent()
        if !holdsOpen { store.isExpanded = false }
        spaceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(Motion.spaceSettle))
                try Task.checkCancellation()
                guard let self else { return }
                spaceIsSettling = false
                // Geometry is picked up by the next sample without forcing an orderFront.
                updateMousePassThrough()
            } catch { }
        }
    }

    private func suspend() {
        sharing.cancelExternalHandoff()
        isSuspended = true
        hover.stop()
        spaceTask?.cancel()
        spaceIsSettling = false
        presentation?.stop()
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
    }

    private func resume() {
        guard isSuspended else { return }
        isSuspended = false
        hoverIntent = HoverIntent()
        configureScreen(at: NSEvent.mouseLocation, force: true)
        startHover()
    }
}
