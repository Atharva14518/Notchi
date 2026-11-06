import Foundation

/// Choosing a service is not completion. Keep the overlay retained until a
/// service delegate reports completion/cancellation, including picker handoff.
struct SendLifecycle: Equatable {
    enum Phase { case idle, choosing, picker, service, savePanel, exporting, openingApp, celebrating }
    private(set) var phase: Phase = .idle
    var keepsPanelOpen: Bool { phase != .idle }
    var isBusy: Bool { phase != .idle && phase != .choosing }
    mutating func begin() { phase = .choosing }
    mutating func pickMore() { phase = .picker }
    mutating func choseService(_ chosen: Bool) { phase = chosen ? .service : .choosing }
    mutating func save() { phase = .savePanel }
    mutating func export() { phase = .exporting }
    mutating func openApp() { phase = .openingApp }
    mutating func confirmed() { phase = .celebrating }
    mutating func returned() { phase = .choosing }
    @discardableResult mutating func dismiss() -> Bool {
        guard !isBusy else { return false }
        phase = .idle
        return true
    }
    mutating func stop() { phase = .idle }
}

struct SendSession: Identifiable {
    let id = UUID()
    let items: [ShelfItem]
}
struct SendToast: Identifiable {
    let id = UUID()
    let text: String
    var isError = false
}
struct SendFlight: Identifiable {
    let id = UUID()
    let items: [ShelfItem]
    let origins: [UUID: CGRect]
    let target: CGRect
}

struct SendFlightPath {
    var start: CGPoint
    var end: CGPoint
    func point(at progress: CGFloat) -> CGPoint {
        let t = min(1, max(0, progress)), u = 1 - t
        let control = CGPoint(x: (start.x + end.x) / 2,
                              y: min(start.y, end.y) - max(35, abs(end.x - start.x) * 0.2))
        return CGPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                       y: u * u * start.y + 2 * u * t * control.y + t * t * end.y)
    }
}
