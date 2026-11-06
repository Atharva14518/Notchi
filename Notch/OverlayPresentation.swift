import SwiftUI

@MainActor
final class OverlayPresentation: ObservableObject {
    enum Phase { case collapsed, anticipating, expanding, expanded, collapsing }
    @Published private(set) var geometry: NotchGeometry
    @Published private(set) var metrics: SilhouetteMetrics
    @Published private(set) var phase: Phase = .collapsed
    @Published private(set) var contentStage = 0
    @Published private(set) var wantsExpanded = false
    @Published var gaze = CGPoint.zero
    private var transitionTask: Task<Void, Never>?

    init(geometry: NotchGeometry) {
        self.geometry = geometry
        metrics = geometry.collapsedMetrics
    }

    func reset(geometry: NotchGeometry, expanded: Bool = false) {
        transitionTask?.cancel()
        self.geometry = geometry
        wantsExpanded = expanded
        phase = expanded ? .expanded : .collapsed
        contentStage = expanded ? 3 : 0
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { metrics = expanded ? geometry.expandedMetrics : geometry.collapsedMetrics }
    }

    func transition(to expanded: Bool, reduceMotion: Bool) {
        guard expanded != wantsExpanded else { return }
        transitionTask?.cancel()
        wantsExpanded = expanded
        if reduceMotion {
            reset(geometry: geometry, expanded: expanded)
            return
        }
        if expanded {
            // Anticipate only from rest; reversing a collapse goes straight to its new spring target.
            let anticipate = phase == .collapsed
            phase = anticipate ? .anticipating : .expanding
            transitionTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try Task.checkCancellation()
                    if anticipate {
                        withAnimation(Animations.anticipation) {
                            self.metrics.size.width *= Motion.anticipationScale
                            self.metrics.size.height *= Motion.anticipationScale
                        }
                        try await Task.sleep(for: .seconds(Motion.anticipationDuration))
                    }
                    try Task.checkCancellation()
                    phase = .expanding
                    withAnimation(Animations.bouncy) { self.metrics = self.geometry.expandedMetrics }
                    try await Task.sleep(for: .seconds(Motion.contentLead))
                    for stage in 1...3 {
                        try Task.checkCancellation()
                        withAnimation(Animations.snappy) { self.contentStage = stage }
                        try await Task.sleep(for: .seconds(Motion.contentStagger))
                    }
                    phase = .expanded
                } catch { /* The next transition owns all presentation state. */ }
            }
        } else {
            phase = .collapsing
            withAnimation(Animations.snappy) {
                contentStage = 0
                metrics = geometry.collapsedMetrics
            }
            transitionTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(Motion.collapseResponse))
                    try Task.checkCancellation()
                    self?.phase = .collapsed
                } catch { }
            }
        }
    }

    func stop() { transitionTask?.cancel() }

    func setContentHeight(_ height: CGFloat, reduceMotion: Bool) {
        guard geometry.contentHeight != height else { return }
        geometry.contentHeight = height
        if wantsExpanded {
            withAnimation(reduceMotion ? nil : Animations.bouncy) { metrics = geometry.expandedMetrics }
        }
    }
}
