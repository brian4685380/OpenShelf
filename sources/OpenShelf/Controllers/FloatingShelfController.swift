import AppKit
import SwiftUI

@MainActor
final class FloatingShelfController {
    private let store = ShelfStore()
    private let dropState = ShelfDropState()

    private var panel: NSPanel?
    private var visibleDropCapturePanel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?
    private var makeKeyWorkItem: DispatchWorkItem?

    private var currentScreen: NSScreen?
    private var currentEdge: ShelfEdge = .right
    private var currentTriggerY: CGFloat?
    private var isCollapsed = false
    private var isShelfPresented = false
    private var isHoveringShelf = false
    private var isExternalDragActive = false
    private var presentationGeneration: UInt = 0
    private var frameTransitionGeneration: UInt = 0

    private let panelSize = NSSize(width: 300, height: 200)
    private let visibleTabWidth: CGFloat = 32
    private let screenPadding: CGFloat = 8
    private let animationDuration: TimeInterval = 0.22
    private let floatingWindowLevel = NSWindow.Level.screenSaver

    func preparePanel() {
        guard panel == nil else {
            return
        }

        let preparedPanel = makePanel()
        preparedPanel.orderOut(nil)
        panel = preparedPanel

        let preparedCapturePanel = makeVisibleDropCapturePanel()
        preparedCapturePanel.orderOut(nil)
        visibleDropCapturePanel = preparedCapturePanel
    }

    func show(
        on screen: NSScreen? = nil,
        edge: ShelfEdge = .right,
        triggerY: CGFloat? = nil
    ) {
        cancelHide()
        presentationGeneration &+= 1
        isShelfPresented = true

        if panel == nil {
            panel = makePanel()
        }
        if visibleDropCapturePanel == nil {
            visibleDropCapturePanel = makeVisibleDropCapturePanel()
        }
        guard let panel else { return }
        currentScreen = screen ?? NSScreen.main
        currentEdge = edge
        if let triggerY {
            currentTriggerY = triggerY
        }
        isCollapsed = false
        let expandedFrame = frameForExpandedState(
            on: currentScreen,
            edge: currentEdge
        )
        panel.level = floatingWindowLevel
        panel.setFrame(expandedFrame, display: true)
        panel.orderFrontRegardless()
        showVisibleDropCapture(below: panel, frame: expandedFrame)
    }

    func collapse(after delay: TimeInterval = 0.0) {
        guard isShelfPresented else { return }

        hideWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.collapseNow()
            }
        }

        hideWorkItem = workItem

        if delay <= 0 {
            DispatchQueue.main.async(execute: workItem)
        } else {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + delay,
                execute: workItem
            )
        }
    }

    func expand() {
        cancelHide()
        guard isShelfPresented, let panel else { return }
        isCollapsed = false
        let expanded = frameForExpandedState(on: currentScreen, edge: currentEdge)
        panel.level = floatingWindowLevel
        showVisibleDropCapture(below: panel, frame: expanded)
        animate(panel: panel, to: expanded)
    }

    func toggleShelf() {
        guard let panel else {
            show()
            return
        }

        if isShelfPresented && panel.isVisible {
            if isCollapsed {
                expand()
            } else {
                collapse()
            }
        } else {
            show()
        }
    }

    func clearShelf() {
        store.clear()
    }

    func refreshAlwaysOnTop() {
        guard isShelfPresented, let panel, panel.isVisible else {
            return
        }

        // App activation and Space-change notifications schedule several
        // delayed refreshes. Finder activates when a file drag begins, so one
        // of those refreshes can otherwise reorder this destination window in
        // the middle of the drag and hand the eventual drop to the app below.
        guard !isExternalDragActive, !isPrimaryMouseButtonPressed else {
            return
        }

        configureFloatingBehavior(for: panel)
        panel.orderFrontRegardless()
        showVisibleDropCapture(below: panel, frame: panel.frame)
    }

    func addAndShow(urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }

        for url in urls {
            store.add(url: url)
        }

        show()
    }

    func beginEdgeDrag(
        on screen: NSScreen,
        edge: ShelfEdge,
        triggerY: CGFloat?
    ) {
        show(on: screen, edge: edge, triggerY: triggerY)
        handleDropTargetChanged(true)
    }

    func endEdgeDrag() {
        handleDropTargetChanged(false)
    }

    func pauseEdgeDragDuringHideDelay() {
        handleDropTargetChanged(false)
        collapse(after: 3.0)
    }

    func resumeEdgeDragWithinVisibleShelf() {
        cancelHide()
        handleDropTargetChanged(true)
    }

    func beginVisibleShelfDrag() {
        handleDropTargetChanged(true)
    }

    func endVisibleShelfDrag() {
        handleDropTargetChanged(false)
    }

    @discardableResult
    func performVisibleShelfDrop(from pasteboard: NSPasteboard) -> Bool {
        let accepted = importExternalDrop(from: pasteboard)
        endVisibleShelfDrag()
        return accepted
    }

    func visibleShelfFrame() -> NSRect? {
        guard isShelfPresented, let panel, panel.isVisible else {
            return nil
        }

        return panel.frame
    }

    @discardableResult
    func performEdgeDrop(
        from pasteboard: NSPasteboard,
        on screen: NSScreen,
        edge: ShelfEdge,
        triggerY: CGFloat?
    ) -> Bool {
        show(on: screen, edge: edge, triggerY: triggerY)
        let accepted = importExternalDrop(from: pasteboard)

        endEdgeDrag()
        return accepted
    }

    func cancelHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        frameTransitionGeneration &+= 1
    }

    func closeShelf() {
        cancelHide()
        cancelPendingKeyFocus()

        guard let panel else { return }

        presentationGeneration &+= 1
        isShelfPresented = false
        isHoveringShelf = false
        isExternalDragActive = false
        dropState.setTargeted(false)
        panel.orderOut(nil)
        visibleDropCapturePanel?.orderOut(nil)
        isCollapsed = false

        print("Shelf closed.")
    }

    private func shelfOriginY(in screenFrame: NSRect) -> CGFloat {
        let preferredCenterY = currentTriggerY ?? screenFrame.midY

        let minimumCenterY =
            screenFrame.minY + panelSize.height / 2

        let maximumCenterY =
            screenFrame.maxY - panelSize.height / 2

        let clampedCenterY = min(
            max(preferredCenterY, minimumCenterY),
            maximumCenterY
        )

        return clampedCenterY - panelSize.height / 2
    }

    private func clampedOriginY(
        _ proposedY: CGFloat,
        in screenFrame: NSRect
    ) -> CGFloat {
        let minimumY = screenFrame.minY
        let maximumY = screenFrame.maxY - panelSize.height

        return min(
            max(proposedY, minimumY),
            maximumY
        )
    }

    private func makePanel() -> NSPanel {
        let rootView = ContentView(
            store: store,
            dropState: dropState,
            onHoverChanged: { [weak self] isHovering in
                self?.handleHoverChanged(isHovering)
            },
            onClose: { [weak self] in
                self?.closeShelf()
            },
            onEmpty: { [weak self] in
                self?.closeShelf()
            },
            onDragOutCompleted: { [weak self] in
                self?.handleDragOutCompleted()
            }
        )

        let dropContainer = ShelfDropContainerView(rootView: rootView)
        dropContainer.wantsLayer = true
        dropContainer.layer?.backgroundColor = NSColor.clear.cgColor
        dropContainer.layer?.isOpaque = false
        dropContainer.hostingView.wantsLayer = true
        dropContainer.hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        dropContainer.hostingView.layer?.isOpaque = false
        dropContainer.onDropTargetChanged = { [weak self] isTargeted in
            self?.handleDropTargetChanged(isTargeted)
        }
        dropContainer.onPerformDrop = { [weak self] pasteboard in
            self?.performShelfDrop(from: pasteboard) ?? false
        }

        let panel = ShelfPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: panelSize.width,
                height: panelSize.height
            ),
            styleMask: [
                .borderless,
                .nonactivatingPanel,
            ],
            backing: .buffered,
            defer: false
        )

        panel.title = "OpenShelf"
        panel.contentView = dropContainer
        panel.registerForShelfDraggedTypes()
        panel.onPaste = { [weak self] in
            self?.pasteFromClipboard() ?? false
        }
        panel.onDropTargetChanged = { [weak self] isTargeted in
            self?.handleDropTargetChanged(isTargeted)
        }
        panel.onPerformDrop = { [weak self] pasteboard in
            self?.performShelfDrop(from: pasteboard) ?? false
        }

        configureFloatingBehavior(for: panel)
        panel.becomesKeyOnlyIfNeeded = false
        panel.acceptsMouseMovedEvents = true
        panel.isMovableByWindowBackground = false

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false

        return panel
    }

    private func makeVisibleDropCapturePanel() -> NSPanel {
        let captureView = VisibleShelfDropCaptureView(
            shelfController: self
        )
        captureView.frame = NSRect(
            origin: .zero,
            size: panelSize
        )
        captureView.autoresizingMask = [.width, .height]

        let capturePanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        capturePanel.title = "OpenShelf Drop Capture"
        capturePanel.contentView = captureView
        configureFloatingBehavior(for: capturePanel)
        capturePanel.hasShadow = false
        capturePanel.isOpaque = false
        capturePanel.backgroundColor = .clear
        capturePanel.ignoresMouseEvents = false

        return capturePanel
    }

    private func showVisibleDropCapture(
        below panel: NSPanel,
        frame: NSRect
    ) {
        guard isShelfPresented, !isCollapsed,
            let capturePanel = visibleDropCapturePanel
        else {
            visibleDropCapturePanel?.orderOut(nil)
            return
        }

        panel.level = floatingWindowLevel
        configureFloatingBehavior(for: capturePanel)
        capturePanel.setFrame(frame, display: false)
        capturePanel.order(.below, relativeTo: panel.windowNumber)
    }

    private func configureFloatingBehavior(for panel: NSPanel) {
        panel.isFloatingPanel = true
        // Setting isFloatingPanel can reset a generic NSPanel to .floating.
        // Assign the intended overlay level afterwards so it remains above
        // newly activated windows and Stage Manager window sets.
        panel.level = floatingWindowLevel
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
    }

    private func handleHoverChanged(_ isHovering: Bool) {
        guard isShelfPresented, let panel else { return }
        isHoveringShelf = isHovering

        if isHovering {
            cancelHide()

            // The panel is already at the floating level. Reordering a drag
            // destination window here makes AppKit emit a synthetic drag exit
            // and re-entry while the cursor has not moved.
            panel.level = floatingWindowLevel

            // Wait briefly before taking key focus for Command-V. The hosting
            // view gets draggingEntered during this interval and cancels the
            // focus request, so entering with a drag from another app never
            // causes AppKit to cancel that drag session.
            scheduleKeyFocusIfSafe()

            if isCollapsed {
                expand()
            }

            print("Shelf hover entered: always-on-top enabled.")
        } else {
            cancelPendingKeyFocus()

            if panel.isKeyWindow {
                panel.resignKey()
            }

            // Do NOT immediately lower the level here.
            // Keep it on top during the 3-second delay.
            collapse(after: 3.0)

            print("Shelf hover exited: collapse scheduled.")
        }
    }

    private func handleDropTargetChanged(_ isTargeted: Bool) {
        guard isShelfPresented, let panel else { return }
        isExternalDragActive = isTargeted
        dropState.setTargeted(isTargeted)

        if isTargeted {
            // A file drag entered the collapsed tab.
            // Do not wait for the normal mouse-hover event.
            cancelHide()
            cancelPendingKeyFocus()

            if panel.isKeyWindow {
                panel.resignKey()
            }

            if isCollapsed {
                expandImmediately()
            }

            print("Drag entered shelf drop region.")
        } else {
            scheduleKeyFocusIfSafe()
            print("Drag left shelf drop region.")
        }
    }

    private func performShelfDrop(
        from pasteboard: NSPasteboard
    ) -> Bool {
        importExternalDrop(from: pasteboard)
    }

    private func importExternalDrop(
        from pasteboard: NSPasteboard
    ) -> Bool {
        let accepted = store.importDroppedPasteboard(pasteboard) {
            [weak self] outcome in
            guard let self else { return }

            self.dropState.report(outcome)

            if outcome.addedCount > 0 {
                self.cancelHide()
            }
        }

        if !accepted {
            dropState.report(
                ShelfImportOutcome(addedCount: 0, skippedCount: 0)
            )
        }

        return accepted
    }

    private func scheduleKeyFocusIfSafe() {
        cancelPendingKeyFocus()

        guard isShelfPresented,
            isHoveringShelf,
            !isExternalDragActive
        else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self,
                    self.isShelfPresented,
                    self.isHoveringShelf,
                    !self.isExternalDragActive,
                    !self.isPrimaryMouseButtonPressed,
                    let panel = self.panel
                else {
                    return
                }

                panel.makeKeyAndOrderFront(nil)
            }
        }

        makeKeyWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.12,
            execute: workItem
        )
    }

    private var isPrimaryMouseButtonPressed: Bool {
        if NSEvent.pressedMouseButtons & 1 != 0 {
            return true
        }

        // During a drag owned by Finder or another application, AppKit's
        // process-local pressedMouseButtons value can be stale. Query the
        // combined macOS session so hovering the shelf cannot steal key focus
        // and cancel the external drag before SwiftUI receives it.
        return CGEventSource.buttonState(
            .combinedSessionState,
            button: .left
        )
    }

    private func cancelPendingKeyFocus() {
        makeKeyWorkItem?.cancel()
        makeKeyWorkItem = nil
    }

    private func handleDragOutCompleted() {
        // Hover updates are not reliable while AppKit owns a drag session.
        // Collapse explicitly after a successful drop outside the shelf.
        collapse()
    }

    private func expandImmediately() {
        cancelHide()

        guard let panel else { return }

        isCollapsed = false

        let expandedFrame = frameForExpandedState(
            on: currentScreen,
            edge: currentEdge
        )

        panel.level = floatingWindowLevel
        showVisibleDropCapture(below: panel, frame: expandedFrame)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(
                name: .easeOut
            )

            panel.animator().setFrame(
                expandedFrame,
                display: true
            )
        }
    }

    private func collapseNow() {
        hideWorkItem = nil

        guard isShelfPresented, let panel, panel.isVisible else { return }

        // A delayed collapse can fire after the pointer has returned or after
        // a Finder drag has begun. Starting the frame animation in either case
        // moves the panel's real hit-test frame away from what is still being
        // drawn on screen, allowing the app below to receive the drop.
        guard !isHoveringShelf else {
            return
        }

        guard !isExternalDragActive, !isPrimaryMouseButtonPressed else {
            collapse(after: 0.25)
            return
        }

        let targetScreen = screenContaining(panel) ?? currentScreen ?? NSScreen.main

        guard let targetScreen else { return }

        let screenFrame = targetScreen.visibleFrame
        let panelFrame = panel.frame

        /*
         Decide which edge is closer to the shelf's current horizontal position.
        */
        let distanceToLeft = abs(panelFrame.minX - screenFrame.minX)
        let distanceToRight = abs(screenFrame.maxX - panelFrame.maxX)

        let collapseEdge: ShelfEdge =
            distanceToLeft <= distanceToRight ? .left : .right

        /*
         Preserve the shelf's current vertical position.
         Clamp it so the panel stays within the screen vertically.
        */
        let preservedY = clampedOriginY(
            panelFrame.origin.y,
            in: screenFrame
        )

        currentScreen = targetScreen
        currentEdge = collapseEdge
        currentTriggerY = preservedY + panelSize.height / 2
        isCollapsed = true
        visibleDropCapturePanel?.orderOut(nil)
        frameTransitionGeneration &+= 1

        let collapsedFrame = frameForCollapsedState(
            on: targetScreen,
            edge: collapseEdge,
            originY: preservedY
        )

        let collapseGeneration = presentationGeneration
        let collapseTransitionGeneration = frameTransitionGeneration

        animate(
            panel: panel,
            to: collapsedFrame
        ) { [weak self, weak panel] in
            Task { @MainActor in
                guard let self, let panel else { return }
                guard
                    self.isShelfPresented,
                    self.presentationGeneration == collapseGeneration,
                    self.frameTransitionGeneration
                        == collapseTransitionGeneration
                else {
                    return
                }

                panel.level = self.floatingWindowLevel
                panel.orderFrontRegardless()

                print(
                    "Shelf collapsed to",
                    collapseEdge == .left ? "left edge." : "right edge."
                )
            }
        }
    }

    private func frameForExpandedState(
        on screen: NSScreen?,
        edge: ShelfEdge
    ) -> NSRect {
        let targetScreen = screen ?? NSScreen.main

        guard let targetScreen else {
            return NSRect(
                x: 0,
                y: 0,
                width: panelSize.width,
                height: panelSize.height
            )
        }

        let screenFrame = targetScreen.visibleFrame

        let x: CGFloat

        switch edge {
        case .left:
            x = screenFrame.minX + screenPadding

        case .right:
            x = screenFrame.maxX - panelSize.width - screenPadding
        }

        let y = shelfOriginY(in: screenFrame)

        return NSRect(
            x: x,
            y: y,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    private func screenContaining(_ panel: NSPanel) -> NSScreen? {
        if let screen = panel.screen {
            return screen
        }

        let panelCenter = NSPoint(
            x: panel.frame.midX,
            y: panel.frame.midY
        )

        return NSScreen.screens.first { screen in
            screen.frame.contains(panelCenter)
        }
    }

    private func frameForCollapsedState(
        on screen: NSScreen?,
        edge: ShelfEdge,
        originY: CGFloat? = nil
    ) -> NSRect {
        let targetScreen = screen ?? NSScreen.main

        guard let targetScreen else {
            return NSRect(
                x: 0,
                y: 0,
                width: panelSize.width,
                height: panelSize.height
            )
        }

        let screenFrame = targetScreen.visibleFrame

        let x: CGFloat

        switch edge {
        case .left:
            x = screenFrame.minX - panelSize.width + visibleTabWidth

        case .right:
            x = screenFrame.maxX - visibleTabWidth
        }

        let y: CGFloat

        if let originY {
            y = clampedOriginY(originY, in: screenFrame)
        } else {
            y = shelfOriginY(in: screenFrame)
        }

        return NSRect(
            x: x,
            y: y,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    private func animate(
        panel: NSPanel,
        to frame: NSRect,
        completion: (() -> Void)? = nil
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(
                name: .easeInEaseOut
            )

            panel.animator().setFrame(frame, display: true)
        } completionHandler: {
            completion?()
        }
    }

    private func pasteFromClipboard() -> Bool {
        guard store.importPasteboard() else {
            return false
        }

        cancelHide()

        if isCollapsed {
            expandImmediately()
        } else {
            refreshAlwaysOnTop()
        }

        return true
    }

}

final class ShelfPanel: NSPanel {
    private let shelfDropDestination = ShelfPanelDropDestination()

    var onPaste: (() -> Bool)?
    var onDropTargetChanged: ((Bool) -> Void)? {
        didSet {
            shelfDropDestination.onDropTargetChanged = onDropTargetChanged
        }
    }
    var onPerformDrop: ((NSPasteboard) -> Bool)? {
        didSet {
            shelfDropDestination.onPerformDrop = onPerformDrop
        }
    }

    private(set) var registeredShelfDraggedTypes: [
        NSPasteboard.PasteboardType
    ] = []

    func registerForShelfDraggedTypes() {
        registeredShelfDraggedTypes = ShelfDropSupport.readableDraggedTypes
        delegate = shelfDropDestination
        registerForDraggedTypes(registeredShelfDraggedTypes)
    }

    func updateDropTarget(
        for pasteboard: NSPasteboard
    ) -> NSDragOperation {
        shelfDropDestination.updateDropTarget(for: pasteboard)
    }

    func performDrop(from pasteboard: NSPasteboard) -> Bool {
        shelfDropDestination.performDrop(from: pasteboard)
    }

    func clearDropTarget() {
        shelfDropDestination.clearDropTarget()
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func sendEvent(_ event: NSEvent) {
        if handlePasteShortcut(event) {
            return
        }

        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handlePasteShortcut(event) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    private func handlePasteShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])

        if event.type == .keyDown,
            modifiers == .command,
            event.charactersIgnoringModifiers?.lowercased() == "v",
            onPaste?() == true
        {
            return true
        }

        return false
    }
}

final class ShelfPanelDropDestination: NSObject, NSWindowDelegate,
    NSDraggingDestination
{
    var onDropTargetChanged: ((Bool) -> Void)?
    var onPerformDrop: ((NSPasteboard) -> Bool)?

    private var isDropTargeted = false

    func draggingEntered(
        _ sender: NSDraggingInfo
    ) -> NSDragOperation {
        print(
            "Visible shelf window received drag:",
            sender.draggingPasteboard.types?.map(\.rawValue) ?? []
        )

        let operation = updateDropTarget(
            for: sender.draggingPasteboard
        )

        if !operation.isEmpty {
            sender.numberOfValidItemsForDrop = max(
                1,
                sender.draggingPasteboard.pasteboardItems?.count ?? 1
            )
        }

        return operation
    }

    func draggingUpdated(
        _ sender: NSDraggingInfo
    ) -> NSDragOperation {
        updateDropTarget(for: sender.draggingPasteboard)
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        clearDropTarget()
    }

    func draggingEnded(_ sender: NSDraggingInfo) {
        clearDropTarget()
    }

    func prepareForDragOperation(
        _ sender: NSDraggingInfo
    ) -> Bool {
        ShelfDropSupport.canImport(sender.draggingPasteboard)
    }

    func performDragOperation(
        _ sender: NSDraggingInfo
    ) -> Bool {
        performDrop(from: sender.draggingPasteboard)
    }

    func concludeDragOperation(_ sender: NSDraggingInfo?) {
        clearDropTarget()
    }

    func wantsPeriodicDraggingUpdates() -> Bool {
        false
    }

    func updateDropTarget(
        for pasteboard: NSPasteboard
    ) -> NSDragOperation {
        guard ShelfDropSupport.canImport(pasteboard) else {
            clearDropTarget()
            return []
        }

        setDropTargeted(true)
        return .copy
    }

    func performDrop(from pasteboard: NSPasteboard) -> Bool {
        guard ShelfDropSupport.canImport(pasteboard) else {
            clearDropTarget()
            return false
        }

        let accepted = onPerformDrop?(pasteboard) ?? false
        clearDropTarget()
        return accepted
    }

    func clearDropTarget() {
        setDropTargeted(false)
    }

    private func setDropTargeted(_ isTargeted: Bool) {
        guard isDropTargeted != isTargeted else {
            return
        }

        isDropTargeted = isTargeted
        onDropTargetChanged?(isTargeted)
    }
}
