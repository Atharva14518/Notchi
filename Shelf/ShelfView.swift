import SwiftUI

struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var actions: ActionCoordinator
    @ObservedObject var sharing: ShareAction
    @ObservedObject var links: LinkCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var allFiles = false
    @State private var celebrating = false
    var body: some View {
        VStack(alignment: .leading, spacing: PanelLayout.shelfGap) {
            if !store.files.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(store.files.suffix(4).enumerated()), id: \.element.id) { index, item in
                            FileCard(file: item, index: index, store: store, actions: actions,
                                     onForward: { sharing.show(items: $0) }, compact: true)
                        }
                        if store.files.count > 4 {
                            Button(String(localized: "+\(store.files.count - 4)")) { allFiles = true }
                                .buttonStyle(NotchiButtonStyle(.secondary)).help(String(localized: "All files"))
                        }
                    }.padding(.horizontal, 2).padding(.vertical, 4)
                }.frame(height: PanelLayout.chipStripHeight)
            }
            if let job = actions.job, job.phase == .running {
                HStack {
                    ProgressRing(progress: actions.progress, isComplete: false, isIndeterminate: actions.isIndeterminate, size: 22)
                    Text(NotchiAttention.short(job.message)).font(Typography.caption)
                    Spacer()
                    Button(String(localized: "Cancel")) { actions.cancel() }.buttonStyle(NotchiButtonStyle(.destructive))
                }.frame(height: PanelLayout.actionRowHeight)
            } else if let job = actions.job, job.phase == .failure {
                HStack {
                    Text(NotchiAttention.short(job.error ?? String(localized: "Try again"))).font(Typography.caption).foregroundStyle(Color.coral).lineLimit(1)
                    Spacer()
                    Button(String(localized: "Retry")) { actions.retry(store: store) }.buttonStyle(NotchiButtonStyle(.secondary))
                }.frame(height: PanelLayout.actionRowHeight)
            } else if celebrating, let comparison = actions.job?.result?.comparison {
                HStack {
                    CountUpSavings(comparison: comparison, compact: true).help(comparison.description)
                    Spacer(minLength: 0)
                    if let url = actions.outputURL {
                        Button(String(localized: "Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            .buttonStyle(NotchiButtonStyle(.secondary))
                    }
                }.frame(height: PanelLayout.actionRowHeight)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        if let item = store.activeItem ?? store.files.last {
                            PillButton(title: String(localized: "Send"), symbol: "paperplane") {
                                sharing.show(items: store.selectedItems.isEmpty ? [item] : store.selectedItems)
                            }
                            ForEach(Array(ActionCatalog.actions(for: item, selected: store.selectedItems).enumerated()), id: \.element.id) { index, action in
                                ActionChip(action: action, index: index) { actions.request(action, item: item, store: store) }
                            }
                            PillButton(title: String(localized: "Get link"), symbol: "link") { links.show(item) }
                        } else {
                            teaser("Compress", icon: "arrow.down.right.and.arrow.up.left")
                            teaser("Convert", icon: "arrow.triangle.2.circlepath")
                            teaser("Send", icon: "paperplane")
                        }
                    }.padding(.vertical, 4).padding(.horizontal, 2)
                }.frame(height: PanelLayout.actionRowHeight)
            }
        }
        .task(id: actions.successToken) {
            guard actions.successToken > 0 else { return }
            celebrating = true
            do { try await Task.sleep(for: .seconds(Motion.linkCelebration)) } catch { return }
            celebrating = false
        }
        .popover(isPresented: $allFiles) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118))], spacing: 12) {
                    ForEach(Array(store.files.enumerated()), id: \.element.id) { index, file in
                        FileCard(file: file, index: index, store: store, actions: actions, onForward: { sharing.show(items: $0); allFiles = false })
                    }
                }.padding(16)
            }.frame(width: 420, height: 320).background(Color.ink).preferredColorScheme(.dark)
        }
        .background(SwipeRemovalMonitor {
            guard !actions.isBusy, let id = store.hoveredID, let item = store.files.first(where: { $0.id == id }) else { return false }
            store.animateRemoval(item); return true
        })
    }
    private func teaser(_ title: String, icon: String) -> some View {
        Label(title.localized, systemImage: icon).font(Typography.button).foregroundStyle(Color.paper)
            .padding(.horizontal, 8).padding(.vertical, 5).background(Color.shelfSurface, in: Capsule())
            .opacity(0.4).accessibilityLabel(String(localized: "Add files to \(title.localized)"))
    }
    private func eta(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite else { return "estimating…" }
        return seconds < 60 ? String(localized: "~\(max(1, Int(seconds.rounded())))s left") : String(localized: "~\(Int(ceil(seconds / 60)))m left")
    }
}

private struct ActionChip: View {
    let action: NativeFileAction
    let index: Int
    let run: () -> Void
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        PillButton(title: action.title, symbol: action.icon, action: run)
            .scaleEffect(reduceMotion || visible ? 1 : 0.7)
            .opacity(visible ? 1 : 0)
            .task {
                try? await Task.sleep(for: .seconds(Double(index) * Motion.cardStagger))
                if !Task.isCancelled { withAnimation(reduceMotion ? nil : Animations.bouncy) { visible = true } }
            }
    }
}
