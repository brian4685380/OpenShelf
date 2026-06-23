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
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

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
    var rowFrames: [ShelfItem.ID: CGRect] = [:] {
        didSet {
            guard rowFrames != oldValue else {
                return
            }

            updateKnownRowContentFrames()
        }
    }
    var rowOrder: [ShelfItem.ID] = [] {
        didSet {
            guard rowOrder != oldValue else {
                return
            }

            knownRowContentFrames = [:]
            updateKnownRowContentFrames()
        }
    }
    var selectedItemIDs: Set<ShelfItem.ID> = []
    var onClearSelection: (() -> Void)?
    var onSelectionChanged: ((Set<ShelfItem.ID>, ShelfItem.ID?) -> Void)?

    private var mouseDownPoint: CGPoint?
    private var mouseDownContentPoint: CGPoint?
    private var selectionRect: CGRect?
    private var selectionBaseIDs: Set<ShelfItem.ID> = []
    private var knownRowContentFrames: [ShelfItem.ID: CGRect] = [:]
    private var selectionAddsToExisting = false
    private var isDraggingSelection = false
    private var lastDragWindowLocation: NSPoint?
    private var autoScrollTimer: Timer?
    private let autoScrollEdgeInset: CGFloat = 30
    private let autoScrollMaxStep: CGFloat = 12
    private let autoScrollInterval: TimeInterval = 1.0 / 30.0

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !rowFrames.isEmpty else {
            return nil
        }

        guard !isPointInScrollBarRegion(point) else {
            return nil
        }

        return isPointInFileRow(point)
            || isPointInActualFileRow(point)
            ? nil
            : self
    }

    override func scrollWheel(with event: NSEvent) {
        guard let scrollView = window?.contentView?.firstScrollViewDescendant() else {
            super.scrollWheel(with: event)
            return
        }

        scrollView.scrollWheel(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let mouseDownPoint = convert(
            event.locationInWindow,
            from: nil
        )
        updateKnownRowContentFrames()
        self.mouseDownPoint = mouseDownPoint
        mouseDownContentPoint = contentPoint(for: mouseDownPoint)
        selectionAddsToExisting = event.modifierFlags.contains(.command)
        selectionBaseIDs = selectionAddsToExisting
            ? selectedItemIDs
            : []
        isDraggingSelection = false
        selectionRect = nil
        lastDragWindowLocation = nil
        stopAutoScrollTimer()
        needsDisplay = true
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
        lastDragWindowLocation = event.locationInWindow
        startAutoScrollTimer()

        updateSelection(to: currentPoint)
        autoScrollIfNeeded()
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownPoint = nil
            mouseDownContentPoint = nil
            selectionRect = nil
            selectionBaseIDs = []
            selectionAddsToExisting = false
            isDraggingSelection = false
            lastDragWindowLocation = nil
            stopAutoScrollTimer()
            needsDisplay = true
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

    private func isPointInActualFileRow(_ point: CGPoint) -> Bool {
        guard let contentView = window?.contentView else {
            return false
        }

        let windowPoint = convert(point, to: nil)

        for view in contentView.fileDragSourceDescendants() {
            let frameInWindow = view.convert(view.bounds, to: nil)

            if frameInWindow.contains(windowPoint) {
                return true
            }
        }

        return false
    }

    private func isPointInScrollBarRegion(_ point: CGPoint) -> Bool {
        guard let scrollView = window?.contentView?.firstScrollViewDescendant() else {
            return false
        }

        let windowPoint = convert(point, to: nil)
        let scrollFrameInWindow = scrollView.convert(
            scrollView.bounds,
            to: nil
        )

        guard scrollFrameInWindow.contains(windowPoint) else {
            return false
        }

        if scrollView.hasVerticalScroller,
            isPoint(
                windowPoint,
                inScroller: scrollView.verticalScroller
            )
        {
            return true
        }

        if scrollView.hasHorizontalScroller,
            isPoint(
                windowPoint,
                inScroller: scrollView.horizontalScroller
            )
        {
            return true
        }

        if scrollView.hasVerticalScroller {
            let scrollerWidth = NSScroller.scrollerWidth(
                for: .regular,
                scrollerStyle: scrollView.scrollerStyle
            )
            let fallbackWidth = max(
                scrollView.verticalScroller?.bounds.width ?? 0,
                scrollerWidth
            ) + 6
            let fallbackFrame = CGRect(
                x: scrollFrameInWindow.maxX - fallbackWidth,
                y: scrollFrameInWindow.minY,
                width: fallbackWidth,
                height: scrollFrameInWindow.height
            )

            if fallbackFrame.contains(windowPoint) {
                return true
            }
        }

        if scrollView.hasHorizontalScroller {
            let scrollerHeight = NSScroller.scrollerWidth(
                for: .regular,
                scrollerStyle: scrollView.scrollerStyle
            )
            let fallbackHeight = max(
                scrollView.horizontalScroller?.bounds.height ?? 0,
                scrollerHeight
            ) + 6
            let fallbackFrame = CGRect(
                x: scrollFrameInWindow.minX,
                y: scrollFrameInWindow.minY,
                width: scrollFrameInWindow.width,
                height: fallbackHeight
            )

            if fallbackFrame.contains(windowPoint) {
                return true
            }
        }

        return false
    }

    private func isPoint(
        _ windowPoint: CGPoint,
        inScroller scroller: NSScroller?
    ) -> Bool {
        guard let scroller,
            !scroller.isHidden,
            scroller.window != nil
        else {
            return false
        }

        return scroller.convert(scroller.bounds, to: nil)
            .insetBy(dx: -4, dy: -4)
            .contains(windowPoint)
    }

    private func updateSelection(to currentPoint: CGPoint) {
        guard let mouseDownPoint else {
            return
        }

        selectionRect = normalizedRect(
            from: mouseDownPoint,
            to: currentPoint
        )
        needsDisplay = true

        let selectedIDs = updatedSelectionIDs(
            between: mouseDownPoint,
            and: currentPoint,
            addingToExistingSelection: selectionAddsToExisting
        )

        let lastSelectedItemID = rowOrder.last {
            selectedIDs.contains($0)
        }

        onSelectionChanged?(selectedIDs, lastSelectedItemID)
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
        guard isDraggingSelection,
            let window = self.window,
            let scrollView = window.contentView?.firstScrollViewDescendant(),
            let documentView = scrollView.documentView
        else {
            return
        }

        guard NSEvent.pressedMouseButtons & 1 == 1 else {
            stopAutoScrollTimer()
            return
        }

        let currentWindowLocation = window.mouseLocationOutsideOfEventStream
        lastDragWindowLocation = currentWindowLocation

        let scrollFrameInWindow = scrollView.convert(
            scrollView.bounds,
            to: nil
        )

        guard scrollFrameInWindow.contains(currentWindowLocation) else {
            return
        }

        let distanceToTop = scrollFrameInWindow.maxY
            - currentWindowLocation.y
        let distanceToBottom = currentWindowLocation.y
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

        let currentPoint = convert(currentWindowLocation, from: nil)
        updateSelection(to: currentPoint)
    }

    private func updatedSelectionIDs(
        between startPoint: CGPoint,
        and currentPoint: CGPoint,
        addingToExistingSelection: Bool
    ) -> Set<ShelfItem.ID> {
        let startContentPoint = mouseDownContentPoint
            ?? contentPoint(for: startPoint)
        let currentContentPoint = contentPoint(for: currentPoint)
        let minY = min(startContentPoint.y, currentContentPoint.y)
        let maxY = max(startContentPoint.y, currentContentPoint.y)

        let rangeIDs = Set(
            rowOrder.filter { itemID in
                guard let frame = knownRowContentFrames[itemID] else {
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

    private func updateKnownRowContentFrames() {
        let validItemIDs = Set(rowOrder)
        knownRowContentFrames = knownRowContentFrames.filter {
            validItemIDs.contains($0.key)
        }

        let offset = currentScrollOffset()

        for (itemID, frame) in rowFrames {
            knownRowContentFrames[itemID] = frame.offsetBy(
                dx: offset.x,
                dy: offset.y
            )
        }
    }

    private func contentPoint(for point: CGPoint) -> CGPoint {
        let offset = currentScrollOffset()

        return CGPoint(
            x: point.x + offset.x,
            y: point.y + offset.y
        )
    }

    private func currentScrollOffset() -> CGPoint {
        window?.contentView?
            .firstScrollViewDescendant()?
            .contentView
            .bounds
            .origin ?? .zero
    }

    private func normalizedRect(
        from startPoint: CGPoint,
        to currentPoint: CGPoint
    ) -> CGRect {
        CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
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
