import AppKit
import SwiftUI

struct FileDragSource: NSViewRepresentable {
    let item: ShelfItem
    let onDragCompleted: (NSDragOperation) -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> FileDragSourceView {
        let view = FileDragSourceView()
        view.item = item
        view.onDragCompleted = onDragCompleted
        return view
    }

    func updateNSView(
        _ view: FileDragSourceView,
        context: Context
    ) {
        view.item = item
        view.onDragCompleted = onDragCompleted
    }
}

final class FileDragSourceView: NSView, NSDraggingSource {
    var item: ShelfItem?
    var onDragCompleted: ((NSDragOperation) -> Void)?
    var onDoubleClick: (() -> Void)?

    private var mouseDownEvent: NSEvent?
    private var hasStartedDragging = false

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }

        mouseDownEvent = event
        hasStartedDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !hasStartedDragging,
            let item,
            let mouseDownEvent
        else {
            return
        }

        hasStartedDragging = true

        /*
         Use NSURL directly as the pasteboard writer.

         This identifies the drag as an existing filesystem item,
         rather than a promised/generated copy.
        */
        let draggingItem = NSDraggingItem(
            pasteboardWriter: item.url as NSURL
        )

        let icon = NSWorkspace.shared.icon(
            forFile: item.url.path
        )

        let dragSize = NSSize(width: 48, height: 48)

        let locationInView = convert(
            mouseDownEvent.locationInWindow,
            from: nil
        )

        draggingItem.setDraggingFrame(
            NSRect(
                x: locationInView.x - dragSize.width / 2,
                y: locationInView.y - dragSize.height / 2,
                width: dragSize.width,
                height: dragSize.height
            ),
            contents: icon
        )

        let session = beginDraggingSession(
            with: [draggingItem],
            event: mouseDownEvent,
            source: self
        )

        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
        hasStartedDragging = false
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        switch context {
        case .outsideApplication:
            /*
             Allow Finder or another external destination to negotiate
             either copy or move.
            */
            return [.copy, .move]

        case .withinApplication:
            return .copy

        @unknown default:
            return .copy
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        mouseDownEvent = nil
        hasStartedDragging = false

        guard !operation.isEmpty else {
            print("Drag cancelled or rejected.")
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.onDragCompleted?(operation)
        }
    }
}
