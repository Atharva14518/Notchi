import AppKit
import SwiftUI

/// Native fallback beneath SwiftUI's onDrop. Both use the store's session claim.
final class DropHostingView<Content: View>: NSHostingView<Content> {
    weak var store: ShelfStore?
    var scanPageDrag: ((NSPoint, Bool, NSPasteboard) -> Bool)?
    var blocksShelfDrop: (() -> Bool)?
    var acceptsPoint: ((NSPoint) -> Bool)?
    required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes(PasteboardDrop.registeredTypes)
    }
    convenience init(rootView: Content, store: ShelfStore) {
        self.init(rootView: rootView)
        self.store = store
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError(String(localized: "init(coder:) is not supported")) }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { store?.setDropTargeted(false) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { update(sender) != [] }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if blocksShelfDrop?() == true { return scanPageDrag?(sender.draggingLocation, true, sender.draggingPasteboard) ?? false }
        guard acceptsPoint?(sender.draggingLocation) ?? true else { return false }
        return store?.acceptPasteboard(sender.draggingPasteboard) ?? false
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { store?.setDropTargeted(false) }
    override func draggingEnded(_ sender: NSDraggingInfo) { store?.setDropTargeted(false) }
    private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        if blocksShelfDrop?() == true {
            return scanPageDrag?(sender.draggingLocation, false, sender.draggingPasteboard) == true ? .move : []
        }
        let accepted = (acceptsPoint?(sender.draggingLocation) ?? true)
            && sender.draggingSourceOperationMask.contains(.copy)
            && sender.draggingPasteboard.availableType(from: PasteboardDrop.registeredTypes) != nil
        store?.setDropTargeted(accepted)
        return accepted ? .copy : []
    }
}
