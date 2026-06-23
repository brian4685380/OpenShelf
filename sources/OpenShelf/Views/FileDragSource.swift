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
    private var lastDragWindowLocation: NSPoint?
    private var autoScrollTimer: Timer?
    private var lastReorderTimestamp: TimeInterval = 0
    private var lastReorderTargetID: ShelfItem.ID?
    private let reorderPasteboardType =
        NSPasteboard.PasteboardType(shelfReorderPasteboardTypeIdentifier)
    private let autoScrollEdgeInset: CGFloat = 30
    private let autoScrollMaxStep: CGFloat = 12
    private let autoScrollInterval: TimeInterval = 1.0 / 30.0
    private let reorderCooldown: TimeInterval = 0.12
    private let reorderTargetInset: CGFloat = 8

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
        lastDragWindowLocation = nil
        lastReorderTimestamp = 0
        lastReorderTargetID = nil
        stopAutoScrollTimer()
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
            startAutoScrollTimer()
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
            lastDragWindowLocation = nil
            lastReorderTimestamp = 0
            lastReorderTargetID = nil
            stopAutoScrollTimer()
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
        lastDragWindowLocation = nil
        lastReorderTimestamp = 0
        lastReorderTargetID = nil
        stopAutoScrollTimer()

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
        lastDragWindowLocation = event.locationInWindow
        autoScrollIfNeeded()
        updateDirectReorder(at: event.locationInWindow)
    }

    private func updateDirectReorder(at windowLocation: NSPoint) {
        guard let targetItem = item(atWindowLocation: windowLocation),
            targetItem.id != item?.id
        else {
            return
        }

        guard shouldApplyReorder(to: targetItem) else {
            return
        }

        lastReorderTimestamp = CACurrentMediaTime()
        lastReorderTargetID = targetItem.id
        onReorderDropEntered?(activeDragItems, targetItem)
    }

    private func shouldApplyReorder(to targetItem: ShelfItem) -> Bool {
        let now = CACurrentMediaTime()

        if targetItem.id == lastReorderTargetID {
            return now - lastReorderTimestamp >= reorderCooldown
        }

        return now - lastReorderTimestamp >= reorderCooldown
    }

    private func startAutoScrollTimer() {
        guard autoScrollTimer == nil else {
            return
        }

        let timer = Timer(
            timeInterval: autoScrollInterval,
            repeats: true
        ) { [weak self] _ in
            self?.autoScrollIfNeeded()
        }

        autoScrollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    private func stopAutoScrollTimer() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }

    private func autoScrollIfNeeded() {
        guard isReordering,
            let lastDragWindowLocation,
            let scrollView = shelfScrollView(),
            let documentView = scrollView.documentView
        else {
            return
        }

        let scrollFrameInWindow = scrollView.convert(
            scrollView.bounds,
            to: nil
        )

        guard scrollFrameInWindow.contains(lastDragWindowLocation) else {
            return
        }

        let distanceToTop = scrollFrameInWindow.maxY
            - lastDragWindowLocation.y
        let distanceToBottom = lastDragWindowLocation.y
            - scrollFrameInWindow.minY

        let scrollDirection: CGFloat
        let edgeDistance: CGFloat

        if distanceToTop < autoScrollEdgeInset {
            scrollDirection = documentView.isFlipped ? -1 : 1
            edgeDistance = distanceToTop
        } else if distanceToBottom < autoScrollEdgeInset {
            scrollDirection = documentView.isFlipped ? 1 : -1
            edgeDistance = distanceToBottom
        } else {
            return
        }

        let closeness = max(
            0,
            min(1, 1 - edgeDistance / autoScrollEdgeInset)
        )
        let step = max(3, autoScrollMaxStep * closeness)

        let visibleRect = scrollView.contentView.bounds
        let documentBounds = documentView.bounds
        let maxY = max(
            documentBounds.minY,
            documentBounds.maxY - visibleRect.height
        )

        var newOrigin = visibleRect.origin
        newOrigin.y = min(
            max(newOrigin.y + step * scrollDirection, documentBounds.minY),
            maxY
        )

        guard newOrigin.y != visibleRect.origin.y else {
            return
        }

        scrollView.contentView.scroll(to: newOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        updateDirectReorder(at: lastDragWindowLocation)
    }

    private func shelfScrollView() -> NSScrollView? {
        var currentView: NSView? = self

        while let view = currentView {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }

            currentView = view.superview
        }

        return window?.contentView?.firstScrollViewDescendant()
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
            let activationFrame = frameInWindow.insetBy(
                dx: 0,
                dy: min(reorderTargetInset, frameInWindow.height / 3)
            )

            if activationFrame.contains(location) {
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

    func firstScrollViewDescendant() -> NSScrollView? {
        for subview in subviews {
            if let scrollView = subview as? NSScrollView {
                return scrollView
            }

            if let scrollView = subview.firstScrollViewDescendant() {
                return scrollView
            }
        }

        return nil
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
