import AppKit
import SwiftUI

struct ShelfSelectionOverlay: NSViewRepresentable {
    let rowFrames: [ShelfItem.ID: CGRect]
    let rowOrder: [ShelfItem.ID]
    let selectedItemIDs: Set<ShelfItem.ID>
    let onClearSelection: () -> Void
    let onSelectionChanged: (Set<ShelfItem.ID>, ShelfItem.ID?) -> Void

    func makeNSView(context: Context) -> ShelfSelectionOverlayView {
        let view = ShelfSelectionOverlayView()

        view.rowFrames = rowFrames
        view.rowOrder = rowOrder
        view.selectedItemIDs = selectedItemIDs
        view.onClearSelection = onClearSelection
        view.onSelectionChanged = onSelectionChanged

        return view
    }

    func updateNSView(
        _ view: ShelfSelectionOverlayView,
        context: Context
    ) {
        view.rowFrames = rowFrames
        view.rowOrder = rowOrder
        view.selectedItemIDs = selectedItemIDs
        view.onClearSelection = onClearSelection
        view.onSelectionChanged = onSelectionChanged
    }
}

final class ShelfSelectionOverlayView: NSView {
    var rowFrames: [ShelfItem.ID: CGRect] = [:]
    var rowOrder: [ShelfItem.ID] = []
    var selectedItemIDs: Set<ShelfItem.ID> = []
    var onClearSelection: (() -> Void)?
    var onSelectionChanged: ((Set<ShelfItem.ID>, ShelfItem.ID?) -> Void)?

    private var mouseDownPoint: CGPoint?
    private var selectionBaseIDs: Set<ShelfItem.ID> = []
    private var isDraggingSelection = false

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !rowFrames.isEmpty else {
            return nil
        }

        return isPointInFileRow(point) ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(
            event.locationInWindow,
            from: nil
        )
        selectionBaseIDs = event.modifierFlags.contains(.command)
            ? selectedItemIDs
            : []
        isDraggingSelection = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownPoint else {
            return
        }

        let currentPoint = convert(
            event.locationInWindow,
            from: nil
        )
        let deltaX = currentPoint.x - mouseDownPoint.x
        let deltaY = currentPoint.y - mouseDownPoint.y

        guard isDraggingSelection || hypot(deltaX, deltaY) >= 3 else {
            return
        }

        isDraggingSelection = true

        let selectedIDs = selectedItemIDs(
            between: mouseDownPoint,
            and: currentPoint,
            addingToExistingSelection: event.modifierFlags.contains(.command)
        )

        let lastSelectedItemID = rowOrder.last {
            selectedIDs.contains($0)
        }

        onSelectionChanged?(selectedIDs, lastSelectedItemID)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownPoint = nil
            selectionBaseIDs = []
            isDraggingSelection = false
        }

        guard isDraggingSelection else {
            onClearSelection?()
            return
        }
    }

    private func isPointInFileRow(_ point: CGPoint) -> Bool {
        rowFrames.values.contains { frame in
            frame.contains(point)
        }
    }

    private func selectedItemIDs(
        between startPoint: CGPoint,
        and currentPoint: CGPoint,
        addingToExistingSelection: Bool
    ) -> Set<ShelfItem.ID> {
        let minY = min(startPoint.y, currentPoint.y)
        let maxY = max(startPoint.y, currentPoint.y)

        let rangeIDs = Set(
            rowOrder.filter { itemID in
                guard let frame = rowFrames[itemID] else {
                    return false
                }

                return frame.maxY >= minY && frame.minY <= maxY
            }
        )

        if addingToExistingSelection {
            return selectionBaseIDs.union(rangeIDs)
        }

        return rangeIDs
    }
}
