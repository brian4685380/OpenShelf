import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FileDragSource: NSViewRepresentable {
    let item: ShelfItem
    let dragItems: [ShelfItem]
    let onDragStarted: () -> Void
    let onDragCompleted: (NSDragOperation, [ShelfItem]) -> Void
    let onDragEnded: () -> Void
    let onClick: (NSEvent.ModifierFlags) -> Void
    let onReorderDropEntered: ([ShelfItem], ShelfItem) -> Void
    let onReorderDropEnded: () -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> FileDragSourceView {
        let view = FileDragSourceView()

        view.item = item
        view.dragItems = dragItems
        view.onDragStarted = onDragStarted
        view.onDragCompleted = onDragCompleted
        view.onDragEnded = onDragEnded
        view.onClick = onClick
        view.onReorderDropEntered = onReorderDropEntered
        view.onReorderDropEnded = onReorderDropEnded
        view.onDoubleClick = onDoubleClick

        return view
    }

    func updateNSView(
        _ view: FileDragSourceView,
        context: Context
    ) {
        view.item = item
        view.dragItems = dragItems
        view.onDragStarted = onDragStarted
        view.onDragCompleted = onDragCompleted
        view.onDragEnded = onDragEnded
        view.onClick = onClick
        view.onReorderDropEntered = onReorderDropEntered
        view.onReorderDropEnded = onReorderDropEnded
        view.onDoubleClick = onDoubleClick
    }
}

final class FileDragSourceView: NSView, NSDraggingSource {
    var item: ShelfItem?
    var dragItems: [ShelfItem] = []
    var onDragStarted: (() -> Void)?
    var onDragCompleted: ((NSDragOperation, [ShelfItem]) -> Void)?
    var onDragEnded: (() -> Void)?
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    var onReorderDropEntered: (([ShelfItem], ShelfItem) -> Void)?
    var onReorderDropEnded: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    private var mouseDownEvent: NSEvent?
    private var mouseDownClickCount = 0
    private var hasStartedDragging = false
    private var isReordering = false
    private var activeDragItems: [ShelfItem] = []
    private let reorderPasteboardType =
        NSPasteboard.PasteboardType(shelfReorderPasteboardTypeIdentifier)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([reorderPasteboardType])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([reorderPasteboardType])
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        mouseDownClickCount = event.clickCount
        hasStartedDragging = false
        isReordering = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let item,
            let mouseDownEvent
        else {
            return
        }

        if isReordering {
            updateDirectReorder(with: event)
            return
        }

        guard !hasStartedDragging else {
            return
        }

        let deltaX = event.locationInWindow.x
            - mouseDownEvent.locationInWindow.x
        let deltaY = event.locationInWindow.y
            - mouseDownEvent.locationInWindow.y

        guard hypot(deltaX, deltaY) >= 3 else {
            return
        }

        if abs(deltaY) >= 3 {
            hasStartedDragging = true
            isReordering = true
            activeDragItems = dragItems.isEmpty ? [item] : dragItems
            onDragStarted?()
            updateDirectReorder(with: event)
            return
        }

        hasStartedDragging = true
        onDragStarted?()

        let itemsToDrag = dragItems.isEmpty ? [item] : dragItems
        activeDragItems = itemsToDrag

        let dragSize = NSSize(width: 48, height: 48)

        let locationInView = convert(
            mouseDownEvent.locationInWindow,
            from: nil
        )

        let draggingItems = itemsToDrag.enumerated().map { index, item in
            let draggingItem = NSDraggingItem(
                pasteboardWriter: ShelfDragPasteboardWriter(item: item)
            )

            let icon = NSWorkspace.shared.icon(
                forFile: item.url.path
            )

            let offset = CGFloat(min(index, 5)) * 5

            draggingItem.setDraggingFrame(
                NSRect(
                    x: locationInView.x - dragSize.width / 2 + offset,
                    y: locationInView.y - dragSize.height / 2 - offset,
                    width: dragSize.width,
                    height: dragSize.height
                ),
                contents: icon
            )

            return draggingItem
        }

        let session = beginDraggingSession(
            with: draggingItems,
            event: mouseDownEvent,
            source: self
        )

        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        let wasReordering = isReordering

        defer {
            mouseDownEvent = nil
            mouseDownClickCount = 0
            hasStartedDragging = false
            isReordering = false
        }

        if wasReordering {
            DispatchQueue.main.async { [weak self] in
                self?.onDragEnded?()
            }
            return
        }

        guard !hasStartedDragging else {
            return
        }

        if mouseDownClickCount == 2 {
            DispatchQueue.main.async { [weak self] in
                self?.onDoubleClick?()
            }
        } else if mouseDownClickCount == 1 {
            DispatchQueue.main.async { [weak self] in
                self?.onClick?(event.modifierFlags)
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
            return [.copy, .move]

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
        isReordering = false

        let completedItems = activeDragItems
        activeDragItems = []

        let didDropOutsideShelf = window.map {
            !$0.frame.contains(screenPoint)
        } ?? true
        let shouldCompleteDragOut = !operation.isEmpty
            && didDropOutsideShelf

        if operation.isEmpty {
            print("Drag cancelled or returned to shelf.")
        } else if !didDropOutsideShelf {
            print("File drag stayed inside OpenShelf.")
        }

        DispatchQueue.main.async { [weak self] in
            if shouldCompleteDragOut {
                self?.onDragCompleted?(operation, completedItems)
            }

            self?.onDragEnded?()
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateReorderTarget(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateReorderTarget(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isReorderDrag(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard isReorderDrag(sender) else {
            return false
        }

        _ = updateReorderTarget(sender)
        onReorderDropEnded?()
        return true
    }

    private func updateReorderTarget(
        _ sender: NSDraggingInfo
    ) -> NSDragOperation {
        guard isReorderDrag(sender),
            let item
        else {
            return []
        }

        onReorderDropEntered?([], item)
        return .move
    }

    private func isReorderDrag(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.types?.contains(
            reorderPasteboardType
        ) == true
    }

    private func updateDirectReorder(with event: NSEvent) {
        guard let targetItem = item(atWindowLocation: event.locationInWindow),
            targetItem.id != item?.id
        else {
            return
        }

        onReorderDropEntered?(activeDragItems, targetItem)
    }

    private func item(atWindowLocation location: NSPoint) -> ShelfItem? {
        guard let contentView = window?.contentView else {
            return nil
        }

        for view in contentView.fileDragSourceDescendants() {
            guard view !== self else {
                continue
            }

            let frameInWindow = view.convert(view.bounds, to: nil)

            if frameInWindow.contains(location) {
                return view.item
            }
        }

        return nil
    }
}

private extension NSView {
    func fileDragSourceDescendants() -> [FileDragSourceView] {
        var matches: [FileDragSourceView] = []

        for subview in subviews {
            if let dragSourceView = subview as? FileDragSourceView {
                matches.append(dragSourceView)
            }

            matches.append(contentsOf: subview.fileDragSourceDescendants())
        }

        return matches
    }
}

private final class ShelfDragPasteboardWriter: NSObject, NSPasteboardWriting {
    private let item: ShelfItem
    private let fileURLPasteboardType =
        NSPasteboard.PasteboardType(UTType.fileURL.identifier)
    private let reorderPasteboardType =
        NSPasteboard.PasteboardType(shelfReorderPasteboardTypeIdentifier)

    init(item: ShelfItem) {
        self.item = item
    }

    func writableTypes(
        for pasteboard: NSPasteboard
    ) -> [NSPasteboard.PasteboardType] {
        [
            fileURLPasteboardType,
            reorderPasteboardType,
        ]
    }

    func pasteboardPropertyList(
        forType type: NSPasteboard.PasteboardType
    ) -> Any? {
        switch type {
        case fileURLPasteboardType:
            return item.url.absoluteString

        case reorderPasteboardType:
            return item.id.uuidString

        default:
            return nil
        }
    }
}
