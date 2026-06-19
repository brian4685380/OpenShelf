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
        view.onDoubleClick = onDoubleClick

        return view
    }

    func updateNSView(
        _ view: FileDragSourceView,
        context: Context
    ) {
        view.item = item
        view.onDragCompleted = onDragCompleted
        view.onDoubleClick = onDoubleClick
    }
}

final class FileDragSourceView: NSView, NSDraggingSource {
    var item: ShelfItem?
    var onDragCompleted: ((NSDragOperation) -> Void)?
    var onDoubleClick: (() -> Void)?

    private var mouseDownEvent: NSEvent?
    private var mouseDownClickCount = 0
    private var hasStartedDragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        mouseDownClickCount = event.clickCount
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
        defer {
            mouseDownEvent = nil
            mouseDownClickCount = 0
            hasStartedDragging = false
        }

        guard !hasStartedDragging else {
            return
        }

        if mouseDownClickCount == 2 {
            DispatchQueue.main.async { [weak self] in
                self?.onDoubleClick?()
            }
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        switch context {
        case .outsideApplication:
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
        mouseDownClickCount = 0
        hasStartedDragging = false

        guard !operation.isEmpty else {
            print("Drag cancelled or returned to shelf.")
            return
        }

        if let window,
            window.frame.contains(screenPoint)
        {
            print("File returned to OpenShelf; keeping shelf item.")
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.onDragCompleted?(operation)
        }
    }
}
