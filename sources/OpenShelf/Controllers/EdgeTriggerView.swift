import AppKit

@MainActor
final class EdgeTriggerView: NSView {
    private weak var shelfController: FloatingShelfController?
    private let shelfProvider: (NSScreen, ShelfEdge, CGFloat?) -> FloatingShelfController?
    private let screen: NSScreen
    private let edge: ShelfEdge
    private var originalTriggerWindowFrame: NSRect?
    private var activeShelfDropCaptureFrame: NSRect?
    private var captureEndWorkItem: DispatchWorkItem?
    private var activeDragSequenceNumber: Int?
    private var didAcceptDrop = false
    private let shelfHideDelay: TimeInterval = 3.0
    private let shelfHideAnimationAllowance: TimeInterval = 0.3

    convenience init(
        shelfController: FloatingShelfController?,
        screen: NSScreen,
        edge: ShelfEdge
    ) {
        self.init(shelfProvider: { [weak shelfController] _, _, _ in shelfController },
                  screen: screen, edge: edge)
        self.shelfController = shelfController
    }

    init(
        shelfProvider: @escaping (NSScreen, ShelfEdge, CGFloat?) -> FloatingShelfController?,
        screen: NSScreen,
        edge: ShelfEdge
    ) {
        self.shelfProvider = shelfProvider
        self.screen = screen
        self.edge = edge

        super.init(frame: .zero)

        wantsLayer = true

        // Normal invisible trigger strip.
        layer?.backgroundColor = NSColor.clear.cgColor

        // Debug option:
        // Uncomment this line if you want to see the trigger strips.
        // layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.25).cgColor

        registerForDraggedTypes(ShelfDropSupport.readableDraggedTypes)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard
        guard ShelfDropSupport.canImport(pasteboard) || ShelfDropSupport.sourceShelfID(pasteboard) != nil else {
            return []
        }
        let triggerY = triggerPositionY(from: sender)

        if activeDragSequenceNumber != sender.draggingSequenceNumber {
            // One shelf per drag session, not per entered/exited callback.
            // Capture can expire while the same physical drag is still alive.
            finishDragSession()
            shelfController = shelfProvider(screen, edge, triggerY)
            activeDragSequenceNumber = sender.draggingSequenceNumber
            didAcceptDrop = false
        }
        guard canImport(pasteboard) else { return [] }

        if activeShelfDropCaptureFrame != nil {
            cancelScheduledShelfDropCaptureEnd()
            shelfController?.resumeEdgeDragWithinVisibleShelf()
            return .copy
        }

        switch edge {
        case .left:
            print("Drag entered left edge.")

        case .right:
            print("Drag entered right edge.")
        }

        shelfController?.beginEdgeDrag(
            on: screen,
            edge: edge,
            triggerY: triggerY
        )

        if let shelfFrame = shelfController?.visibleShelfFrame() {
            beginShelfDropCapture(over: shelfFrame)
        }

        return .copy
    }

    override func draggingUpdated(
        _ sender: NSDraggingInfo
    ) -> NSDragOperation {
        return canImport(sender.draggingPasteboard)
            ? .copy
            : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        shelfController?.pauseEdgeDragDuringHideDelay()
        scheduleShelfDropCaptureEnd(
            after: shelfHideDelay + shelfHideAnimationAllowance
        )
    }

    override func prepareForDragOperation(
        _ sender: NSDraggingInfo
    ) -> Bool {
        canImport(sender.draggingPasteboard)
    }

    override func performDragOperation(
        _ sender: NSDraggingInfo
    ) -> Bool {
        let accepted = performDrop(
            from: sender.draggingPasteboard,
            triggerY: triggerPositionY(from: sender)
        )
        endShelfDropCapture()
        return accepted
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        guard sender == nil || activeDragSequenceNumber == sender?.draggingSequenceNumber else { return }
        finishDragSession()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        guard activeDragSequenceNumber == sender.draggingSequenceNumber else { return }
        finishDragSession()
    }

    func performDrop(
        from pasteboard: NSPasteboard,
        triggerY: CGFloat?
    ) -> Bool {
        guard ShelfDropSupport.canImport(pasteboard) || ShelfDropSupport.sourceShelfID(pasteboard) != nil else { return false }
        if activeDragSequenceNumber == nil { shelfController = shelfProvider(screen, edge, triggerY) }
        guard canImport(pasteboard) else {
            shelfController?.endEdgeDrag()
            return false
        }

        let accepted = shelfController?.performEdgeDrop(
            from: pasteboard,
            on: screen,
            edge: edge,
            triggerY: triggerY
        ) ?? false
        didAcceptDrop = accepted
        return accepted
    }

    private func finishDragSession() {
        endShelfDropCapture()
        if activeDragSequenceNumber != nil {
            shelfController?.endEdgeDrag()
            // Do not hide an accepted file promise while it is still loading.
            if !didAcceptDrop { shelfController?.discardEmptyEdgePreview() }
        }
        activeDragSequenceNumber = nil
        didAcceptDrop = false
        shelfController = nil
    }

    func beginShelfDropCapture(over shelfFrame: NSRect) {
        guard let window else {
            return
        }

        if originalTriggerWindowFrame == nil {
            originalTriggerWindowFrame = window.frame
        }

        let captureFrame: NSRect

        switch edge {
        case .left:
            captureFrame = NSRect(
                x: screen.frame.minX,
                y: shelfFrame.minY,
                width: shelfFrame.maxX - screen.frame.minX,
                height: shelfFrame.height
            )

        case .right:
            captureFrame = NSRect(
                x: shelfFrame.minX,
                y: shelfFrame.minY,
                width: screen.frame.maxX - shelfFrame.minX,
                height: shelfFrame.height
            )
        }

        window.setFrame(captureFrame, display: false)
        window.orderFrontRegardless()
        activeShelfDropCaptureFrame = captureFrame
        cancelScheduledShelfDropCaptureEnd()
    }

    func endShelfDropCapture() {
        guard let originalTriggerWindowFrame, let window else {
            return
        }

        cancelScheduledShelfDropCaptureEnd()
        activeShelfDropCaptureFrame = nil
        self.originalTriggerWindowFrame = nil
        window.setFrame(originalTriggerWindowFrame, display: false)
        window.orderFrontRegardless()
    }

    func scheduleShelfDropCaptureEnd(after delay: TimeInterval) {
        cancelScheduledShelfDropCaptureEnd()

        let workItem = DispatchWorkItem { [weak self] in
            self?.endShelfDropCapture()
        }
        captureEndWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay,
            execute: workItem
        )
    }

    func cancelScheduledShelfDropCaptureEnd() {
        captureEndWorkItem?.cancel()
        captureEndWorkItem = nil
    }

    private func canImport(_ pasteboard: NSPasteboard) -> Bool {
        guard let shelfController else { return false }
        return ShelfDropSupport.canImport(pasteboard, destinationShelfID: shelfController.id)
    }

    private func triggerPositionY(
        from sender: NSDraggingInfo
    ) -> CGFloat? {
        guard let window else {
            return nil
        }

        let pointInWindow = sender.draggingLocation
        let pointOnScreen = window.convertPoint(toScreen: pointInWindow)

        return pointOnScreen.y
    }
}
