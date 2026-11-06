import AppKit
import SwiftUI

/// Horizontal file card. The filename remains a real file URL when dragged out.
struct FileCard: View {
    let file: ShelfItem
    let index: Int
    @ObservedObject var store: ShelfStore
    @ObservedObject var actions: ActionCoordinator
    let onForward: ([ShelfItem]) -> Void
    var compact = false
    @State private var thumbnail: NSImage?
    @State private var appeared = false
    @State private var shake: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @ObservedObject private var keyboard = KeyboardFocus.shared
    private var selected: Bool { store.selectedIDs.contains(file.id) }
    private var removing: Bool { store.removingIDs.contains(file.id) }
    private var lifted: Bool { store.draggingOutID == file.id }
    private var job: ActionJob? { actions.job(for: file.id) }

    var body: some View {
        cardContent
        .foregroundStyle(Color.paper)
        .padding(compact ? 8 : 10).frame(width: compact ? 148 : 118, height: compact ? PanelLayout.chipHeight : 137, alignment: .topLeading)
        .background(job?.phase == .failure ? Color.coral.opacity(0.12) : Color.shelfSurface,
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(
            job?.phase == .failure ? Color.coral : (selected ? .acid : .shelfBorder), lineWidth: selected ? 1.5 : 1))
        .overlay(alignment: .topTrailing) {
            Button { store.animateRemoval(file) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    .frame(width: 12, height: 12).foregroundStyle(Color.acid)
                    
            }
            .buttonStyle(NotchiButtonStyle(.icon)).padding(4).disabled(actions.isBusy)
            .help(String(localized: "Remove from shelf")).accessibilityLabel(String(localized: "Remove \(file.name) from shelf"))
        }
        .overlay(alignment: .topLeading) {
            if !compact { Button { onForward([file]) } label: {
                Image(systemName: "arrowshape.turn.up.right.fill").font(.system(size: 10, weight: .semibold))
                    .frame(width: 23, height: 23).foregroundStyle(Color.acid)
                    .background(Color.ink.opacity(0.8), in: Circle())
            }
            .buttonStyle(NotchiButtonStyle(.icon)).padding(4).disabled(actions.isBusy)
            .help(String(localized: "Send \(file.name)")).accessibilityLabel(String(localized: "Forward \(file.name)")) }
        }
        .overlay(SparkleBurst(trigger: job?.phase == .success ? actions.successToken : 0))
        .overlay(SparkleBurst(trigger: removing ? 1 : 0, poof: true))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { store.select(file, extending: NSEvent.modifierFlags.contains(.command)) }
        .focusable().focused($focused).focusEffectDisabled()
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(focused && keyboard.navigating ? Color.acid : .clear, lineWidth: 2))
        .onKeyPress(.return) { store.select(file, extending: NSEvent.modifierFlags.contains(.command)); return .handled }
        .onKeyPress(.space) { store.select(file, extending: NSEvent.modifierFlags.contains(.command)); return .handled }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "\(file.name), \(file.detail)\(file.isNew ? ", New" : "")"))
        .accessibilityAction(named: String(localized: "Select actions")) { store.select(file) }
        .onHover { hovering in if hovering { store.hoveredID = file.id } else if store.hoveredID == file.id { store.hoveredID = nil } }
        .onDrag { store.draggingOutID = file.id; return NSItemProvider(object: file.url as NSURL) }
        .contextMenu {
            Button(String(localized: "Copy path")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(file.url.path, forType: .string) }
            Button(String(localized: "Reveal in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
            Button(String(localized: "Remove from Shelf")) { store.animateRemoval(file) }.disabled(actions.isBusy)
        }
        .scaleEffect(reduceMotion ? 1 : (removing ? 0.65 : (lifted ? 1.05 : (appeared ? 1 : 0.6))))
        .rotationEffect(.degrees(reduceMotion || appeared ? 0 : (index.isMultiple(of: 2) ? -7 : 7)))
        .opacity(removing || !appeared ? 0 : 1)
        .shadow(color: .black.opacity(lifted ? 0.5 : 0), radius: 9, y: 6)
        .modifier(CardShake(amount: reduceMotion ? 0 : shake))
        .animation(reduceMotion ? nil : Animations.poof, value: removing)
        .animation(reduceMotion ? nil : Animations.snappy, value: lifted)
        .animation(reduceMotion ? nil : Animations.gentle, value: job?.phase == .failure)
        .onChange(of: job?.phase) { _, phase in
            guard phase == .running || phase == .failure else { return }
            withAnimation(reduceMotion ? nil : (phase == .failure ? Animations.gentle : Animations.snappy)) { shake += 1 }
        }
        .task(id: file.id) {
            try? await Task.sleep(for: .seconds(Double(min(index, 8)) * Motion.cardStagger))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : Animations.bouncy) { appeared = true }
            thumbnail = await ThumbnailCache.shared.image(for: file)
        }
    }
    @ViewBuilder private var cardContent: some View {
        if compact {
            HStack(spacing: 6) {
                ZStack {
                    if file.kind == .video {
                        VideoHoverPreview(url: file.url, thumbnail: thumbnail ?? NSWorkspace.shared.icon(forFile: file.url.path), enabled: !actions.isBusy).frame(width: 27, height: 28)
                    } else {
                        Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: file.url.path)).resizable().scaledToFit().frame(width: 27, height: 28)
                    }
                    if let job, job.phase == .running || job.phase == .success {
                        ProgressRing(progress: job.fraction ?? 0.18, isComplete: job.phase == .success,
                                     isIndeterminate: job.phase == .running && job.fraction == nil, size: 30)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name).font(Typography.caption).lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 3) {
                        Text(file.detail).font(Typography.caption).foregroundStyle(Color.secondaryText)
                        if file.isNew { Text(String(localized: "New")).font(Typography.caption).foregroundStyle(Color.mint) }
                    }
                }.padding(.trailing, 20)
            }.frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        } else {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                Group {
                    if file.kind == .video {
                        VideoHoverPreview(url: file.url, thumbnail: thumbnail ?? NSWorkspace.shared.icon(forFile: file.url.path), enabled: !actions.isBusy)
                    } else {
                        Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: file.url.path)).resizable().scaledToFit()
                    }
                }.frame(width: 75, height: 58)
                    .opacity(job?.phase == .success ? 0.15 : 1)
                if let job, job.phase == .running || job.phase == .success {
                    ProgressRing(progress: job.fraction ?? 0.18, isComplete: job.phase == .success,
                                 isIndeterminate: job.phase == .running && job.fraction == nil, size: 65)
                        .scaleEffect(job.phase == .success ? 1.1 : 1)
                        .animation(reduceMotion ? nil : Animations.bouncy, value: job.phase)
                    if file.kind == .video || file.kind == .audio, job.phase == .running, let fraction = job.fraction {
                        Text(String(localized: "\(Int(fraction * 100))%"))
                            .font(Typography.caption).foregroundStyle(Color.acid)
                            .padding(4).background(Color.ink.opacity(0.9), in: Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity).frame(height: 67)
            Text(file.name).font(Typography.body.weight(.medium)).lineLimit(1).truncationMode(.middle)
            HStack(spacing: 4) {
                Text(file.detail).font(Typography.caption).foregroundStyle(Color.acid)
                if file.isNew {
                    Text(String(localized: "New")).font(Typography.eyebrow).foregroundStyle(Color.ink)
                        .padding(.horizontal, 4).padding(.vertical, 2).background(Color.acid, in: Capsule())
                }
            }
            if let savings = file.savings {
                Text(savings.after < savings.before ? String(localized: "\(savings.percent)% smaller") : String(localized: "new size: \(file.detail)"))
                    .font(Typography.caption).foregroundStyle(Color.acid).lineLimit(1)
            }
        }
        }
    }

}
