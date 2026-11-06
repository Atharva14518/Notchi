import SwiftUI

/// Live SwiftUI components with isolated in-memory data. No real conversion or
/// share is performed and the demo never touches the user's shelf.
struct OnboardingDemo: View {
    @StateObject private var model = TourDemoModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = 0
    @State private var progress = 0.0
    private let convert = NativeFileAction(operation: .convert(.jpeg))
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if let item = model.item {
                    FileCard(file: item, index: 0, store: model.store, actions: model.actions, onForward: { _ in })
                        .overlay(alignment: .center) {
                            if stage == 1 || stage == 2 {
                                ProgressRing(progress: progress, isComplete: stage == 2, size: 64)
                                    .padding(4).background(Color.ink, in: Circle())
                                    .frame(maxHeight: .infinity, alignment: .top).padding(.top, 5)
                            }
                        }
                        .scaleEffect(reduceMotion ? 1 : (stage == 0 ? 0.85 : (stage == 3 ? 0.7 : 1)))
                        .offset(x: stage == 3 && !reduceMotion ? 45 : 0)
                        .opacity(stage == 3 && !reduceMotion ? 0.25 : 1)
                        .rotationEffect(.degrees(reduceMotion || stage != 0 ? 0 : -5))
                }
                VStack(spacing: 12) {
                    IconBadge(symbol: "arrow.right", tint: .acid)
                    PillButton(title: convert.title, symbol: convert.icon, tint: .acid, action: {})
                    BlobMascot(gaze: .zero, isActive: true, isTargeted: stage == 0, gulpToken: stage == 0 ? 1 : 0,
                               isWorking: stage == 1, happyToken: stage == 2 ? 1 : 0, waveToken: stage == 3 ? 1 : 0)
                        .scaleEffect(0.65).frame(height: 45)
                }
                SendAppTile(target: SendTarget(id: "demo-send", title: String(localized: "Send"), image: NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: nil) ?? NSImage(size: .zero), kind: .copy), index: 0, select: {})
                    .frame(width: 110).opacity(reduceMotion || stage >= 2 ? 1 : 0.35)
            }
            .allowsHitTesting(false).accessibilityHidden(true)
            HStack {
                ForEach(Array([String(localized: "1 · Drop"), String(localized: "2 · Convert"), String(localized: "3 · Share")].enumerated()), id: \.offset) { index, label in
                    Text(label).font(Typography.button).foregroundStyle(reduceMotion || (index == min(stage, 2)) ? Color.acid : .secondaryText)
                    if index < 2 { Spacer() }
                }
            }.padding(.horizontal, 15)
        }
        .padding(15).background(Color.shelfSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
        .task(id: reduceMotion) {
            guard !reduceMotion else { stage = 3; return }
            do {
                while !Task.isCancelled {
                    for next in 0...3 {
                        try Task.checkCancellation()
                        withAnimation(Animations.bouncy) { stage = next; progress = next == 1 ? 0.8 : (next > 1 ? 1 : 0) }
                        try await Task.sleep(for: .seconds(Motion.tourBeat))
                    }
                }
            } catch { }
        }
    }
}

@MainActor
private final class TourDemoModel: ObservableObject {
    let store = ShelfStore(persistence: MemoryShelfPersistence())
    let actions = ActionCoordinator()
    let item: ShelfItem?
    private let folder: URL
    init() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("NotchiTour-\(UUID().uuidString)")
        let url = folder.appendingPathComponent("moodboard.png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let image = NSImage(size: NSSize(width: 120, height: 100), flipped: false) { rect in
                NSColor(calibratedRed: 0.49, green: 0.36, blue: 1, alpha: 1).setFill(); rect.fill()
                NSColor(calibratedRed: 0.8, green: 1, blue: 0.45, alpha: 1).setFill()
                NSBezierPath(ovalIn: NSRect(x: 25, y: 15, width: 70, height: 70)).fill()
                return true
            }
            guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else { item = nil; return }
            try png.write(to: url)
            item = ShelfItem(url: url)
        } catch { item = nil }
    }
    deinit { try? FileManager.default.removeItem(at: folder) }
}
