import SwiftUI
import AVFoundation
import AppKit

struct VideoHoverPreview: View {
    let url: URL
    let thumbnail: NSImage
    var enabled = true
    @StateObject private var preview = VideoPreviewController()
    @State private var hovering = false
    @State private var manualPreview = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Image(nsImage: thumbnail).resizable().scaledToFit()
            PreviewPlayerView(player: preview.player) { inside, fraction in
                hovering = inside
                if !inside { manualPreview = false }
                if inside, enabled, !reduceMotion { preview.scrub(fraction: fraction) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if preview.player == nil {
                Image(systemName: "play.circle.fill").foregroundStyle(Color.paper)
                    .font(.system(size: 18)).shadow(radius: 2).allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .task(id: (hovering || manualPreview) && enabled && !reduceMotion) {
            guard !Task.isCancelled else { return }
            if (hovering || manualPreview) && enabled && !reduceMotion { await preview.start(url: url) }
            else { preview.stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in preview.stop(); hovering = false; manualPreview = false }
        .onDisappear { preview.stop() }
        .accessibilityElement(children: .ignore)
        .accessibilityAction(named: String(localized: "Play or stop muted preview")) { if enabled && !reduceMotion { manualPreview.toggle() } }
        .accessibilityLabel(String(localized: "Video thumbnail. Hover to preview and move horizontally to scrub."))
        .accessibilityValue(reduceMotion ? String(localized: "Static preview, Reduce Motion") : preview.status)
    }
}

@MainActor
private final class VideoPreviewController: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var status = String(localized: "Thumbnail")
    private var duration = 0.0
    private var lastSeek = 0.0
    private var loopObserver: NSObjectProtocol?
    func start(url: URL) async {
        guard !Task.isCancelled else { return }
        stop()
        status = String(localized: "Loading preview")
        let asset = AVURLAsset(url: url)
        guard let playable = try? await asset.load(.isPlayable), playable,
              let time = try? await asset.load(.duration), !Task.isCancelled else {
            if !Task.isCancelled { status = String(localized: "Preview unavailable; thumbnail shown") }
            return
        }
        duration = CMTimeGetSeconds(time)
        guard duration.isFinite, duration > 0 else { status = String(localized: "Preview unavailable; thumbnail shown"); return }
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 1
        let player = AVPlayer(playerItem: item)
        player.isMuted = true; player.volume = 0; player.actionAtItemEnd = .none
        self.player = player
        status = String(localized: "Playing muted")
        loopObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak player] _ in
            player?.seek(to: .zero); player?.play()
        }
        player.play()
    }
    func scrub(fraction: Double) {
        guard duration > 0, ProcessInfo.processInfo.systemUptime - lastSeek > 0.1 else { return }
        lastSeek = ProcessInfo.processInfo.systemUptime
        player?.seek(to: CMTime(seconds: min(duration - 0.01, duration * fraction), preferredTimescale: 600),
                     toleranceBefore: CMTime(seconds: 0.1, preferredTimescale: 600), toleranceAfter: CMTime(seconds: 0.1, preferredTimescale: 600))
    }
    func stop() {
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        loopObserver = nil
        player?.pause(); player?.replaceCurrentItem(with: nil); player = nil
        duration = 0; status = String(localized: "Thumbnail")
    }
    deinit { if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) } }
}
private struct PreviewPlayerView: NSViewRepresentable {
    let player: AVPlayer?
    let onPointer: (Bool, Double) -> Void
    func makeNSView(context: Context) -> PlayerLayerView { PlayerLayerView() }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PlayerLayerView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 75, height: proposal.height ?? 58)
    }
    func updateNSView(_ view: PlayerLayerView, context: Context) {
        view.playerLayer.player = player
        view.playerLayer.isHidden = player == nil
        view.onPointer = onPointer
    }
    final class PlayerLayerView: NSView {
        let playerLayer = AVPlayerLayer()
        var onPointer: ((Bool, Double) -> Void)?
        private var pointerArea: NSTrackingArea?
        private var pointerTimer: Timer?
        private var lastInside = false
        private var lastFraction = -1.0
        override init(frame: NSRect) {
            super.init(frame: frame); wantsLayer = true
            playerLayer.videoGravity = .resizeAspectFill; layer?.addSublayer(playerLayer)
        }
        required init?(coder: NSCoder) { fatalError(String(localized: "init(coder:) has not been implemented")) }
        override func layout() { super.layout(); playerLayer.frame = bounds }
        // Active-always tracking works in a nonactivating NSPanel. Keep the
        // native view transparent and present even before a player is loaded;
        // hiding the entire representable would also suppress pointer entry.
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let pointerArea { removeTrackingArea(pointerArea) }
            let area = NSTrackingArea(rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
            addTrackingArea(area); pointerArea = area
        }
        override func mouseEntered(with event: NSEvent) { moved(event) }
        override func mouseMoved(with event: NSEvent) { moved(event) }
        override func mouseExited(with event: NSEvent) { report(inside: false, fraction: 0) }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            pointerTimer?.invalidate(); pointerTimer = nil
            guard window != nil else { report(inside: false, fraction: 0); return }
            // Pointer warps/accessibility clicks and nested drag loops can omit
            // entered/moved events, just as they do for the notch hot zone.
            let timer = Timer(timeInterval: Motion.previewPointerInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.samplePointer() }
            }
            RunLoop.main.add(timer, forMode: .common); pointerTimer = timer
        }
        private func samplePointer() {
            guard let window, window.isVisible, window.occlusionState.contains(.visible), !isHiddenOrHasHiddenAncestor else {
                report(inside: false, fraction: 0); return
            }
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            report(inside: visibleRect.contains(point), fraction: min(1, max(0, point.x / max(1, bounds.width))))
        }
        private func report(inside: Bool, fraction: Double) {
            guard inside != lastInside || (inside && abs(fraction - lastFraction) > 0.005) else { return }
            lastInside = inside; lastFraction = fraction
            onPointer?(inside, fraction)
        }
        deinit { pointerTimer?.invalidate() }
        private func moved(_ event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            report(inside: visibleRect.contains(point), fraction: min(1, max(0, point.x / max(1, bounds.width))))
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
