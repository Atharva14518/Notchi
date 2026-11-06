import Foundation

/// A drag must have pointer movement and a newly written drag pasteboard.
struct SystemDragTracker {
    private var baseline: Int
    private var moved = false
    private(set) var active = false
    init(changeCount: Int) { baseline = changeCount }
    mutating func update(changeCount: Int, buttonDown: Bool, mouseDown: Bool = false,
                         mouseDragged: Bool = false, hasPayload: Bool) -> Bool {
        if mouseDown || !buttonDown {
            baseline = changeCount
            moved = false
            active = false
            return false
        }
        if mouseDragged { moved = true }
        if moved && changeCount != baseline && hasPayload { active = true }
        return active
    }
}
