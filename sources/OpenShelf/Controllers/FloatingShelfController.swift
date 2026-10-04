import AppKit
import SwiftUI

@MainActor
final class FloatingShelfController {
    private let store = ShelfStore()
    private let dropState = ShelfDropState()
    private let selection = ShelfSelectionModel()
    private let presentation = ShelfPresentationState()
    private let makePanelKey: @MainActor (NSPanel) -> Void
    private let primaryMouseButtonPressed: @MainActor () -> Bool

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
    private var needsFloatingRefresh = false
    private var needsScreenReposition = false
    private var presentationGeneration: UInt = 0
    private var frameTransitionGeneration: UInt = 0

    private let panelSize = NSSize(width: 300, height: 200)
    private let visibleTabWidth: CGFloat = 32
    private let screenPadding: CGFloat = 8
    private let animationDuration: TimeInterval = 0.22
    // Finder does not reliably route cross-process drag destinations to
    // windows at .screenSaver. The edge trigger already uses .floating for
    // this reason; keep the visible shelf at the same interactive level so a
    // file can be dropped anywhere on an already-expanded shelf without first
    // visiting the screen edge.
    private let interactiveWindowLevel = ShelfWindowPolicy.level

    init(
        makePanelKey: @escaping @MainActor (NSPanel) -> Void = {
            $0.makeKeyAndOrderFront(nil)
        },
        primaryMouseButtonPressed: @escaping @MainActor () -> Bool = {
            if NSEvent.pressedMouseButtons & 1 != 0 {
                return true
            }

            return CGEventSource.buttonState(
                .combinedSessionState,
                button: .left
            )
        }
    ) {
        self.makePanelKey = makePanelKey
        self.primaryMouseButtonPressed = primaryMouseButtonPressed
    }

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
        panel.level = interactiveWindowLevel
        panel.setFrame(expandedFrame, display: true)
        panel.orderFrontRegardless()
        showVisibleDropCapture(below: panel, frame: expandedFrame)
    }

    func collapse(after delay: TimeInterval = 0.0) {
        guard isShelfPresented, !presentation.isPinned else { return }

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
        panel.level = interactiveWindowLevel
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
                closeShelf()
            }
        } else {
            show()
        }
    }

    func clearShelf() {
        store.clear()
    }

    func prepareForTermination() {
        store.cleanUpSession()
    }

    func refreshAlwaysOnTop() {
        guard isShelfPresented, let panel else {
            return
        }

        needsFloatingRefresh = true

        // App activation and Space-change notifications schedule several
        // delayed refreshes. Finder activates when a file drag begins, so one
        // of those refreshes can otherwise reorder this destination window in
        // the middle of the drag and hand the eventual drop to the app below.
        guard !isExternalDragActive, !isPrimaryMouseButtonPressed else {
            return
        }

        if needsScreenReposition {
            repositionOnAvailableScreen()
        }
        configureFloatingBehavior(for: panel)
        panel.orderFrontRegardless()
        showVisibleDropCapture(below: panel, frame: panel.frame)
        needsFloatingRefresh = false
    }

    func maintainAlwaysOnTop() {
        store.reconcilePendingMonitors()
        guard isShelfPresented, let panel else { return }
        guard !isPrimaryMouseButtonPressed else { return }

        // A Space transition can interrupt the destination's draggingExited/
        // draggingEnded callbacks. A released physical mouse button is the
        // authoritative end of that gesture; don't stay blocked forever.
        if isExternalDragActive {
            handleDropTargetChanged(false)
        }

        // Retry work skipped during a drag, or recover a panel displaced by
        // WindowServer. Do not reorder a healthy shelf on every timer tick.
        if needsFloatingRefresh || !panel.isVisible || !panel.isOnActiveSpace {
            refreshAlwaysOnTop()
        }
    }

    func screenParametersDidChange() {
        needsScreenReposition = true
        refreshAlwaysOnTop()
    }

    private func repositionOnAvailableScreen() {
        guard let panel else { return }
        let screens = NSScreen.screens
        let previousID = currentScreen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let target = screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber) == previousID
        } ?? screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? screens.first
        guard let target else { return }

        currentScreen = target
        let frame = isCollapsed
            ? frameForCollapsedState(on: target, edge: currentEdge)
            : frameForExpandedState(on: target, edge: currentEdge)
        frameTransitionGeneration &+= 1
        panel.setFrame(frame, display: true)
        needsScreenReposition = false
    }

    @discardableResult
    func addAndShow(urls: [URL]) -> ShelfImportOutcome {
        guard !urls.isEmpty else {
            return ShelfImportOutcome(addedCount: 0, skippedCount: 0)
        }

        var addedCount = 0
        for url in urls {
            if store.add(url: url) { addedCount += 1 }
        }

        let outcome = ShelfImportOutcome(addedCount: addedCount, skippedCount: urls.count - addedCount)
        if isShelfPresented { expand() } else { show() }
        dropState.report(outcome)
        return outcome
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
        needsFloatingRefresh = false
        needsScreenReposition = false
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
            selection: selection,
            presentation: presentation,
            onTogglePin: { [weak self] in self?.togglePin() },
            onPaste: { [weak self] in _ = self?.pasteFromClipboard() },
            onHoverChanged: { [weak self] isHovering in
                self?.handleHoverChanged(isHovering)
            },
            onClose: { [weak self] in
                self?.closeShelf()
            },
            onEmpty: { [weak self] in
                if self?.presentation.isPinned == false { self?.closeShelf() }
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
        panel.onCommand = { [weak self] command in
            self?.handleKeyboardCommand(command) ?? false
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
        panel.hasShadow = true

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

        panel.level = interactiveWindowLevel
        configureFloatingBehavior(for: capturePanel)
        capturePanel.setFrame(frame, display: false)
        capturePanel.order(.below, relativeTo: panel.windowNumber)
    }

    private func configureFloatingBehavior(for panel: NSPanel) {
        ShelfWindowPolicy.apply(to: panel)
    }

    private func handleHoverChanged(_ isHovering: Bool) {
        guard isShelfPresented, let panel else { return }
        isHoveringShelf = isHovering

        if isHovering {
            cancelHide()

            // The panel is already at the floating level. Reordering a drag
            // destination window here makes AppKit emit a synthetic drag exit
            // and re-entry while the cursor has not moved.
            panel.level = interactiveWindowLevel

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

                self.makePanelKey(panel)
            }
        }

        makeKeyWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.12,
            execute: workItem
        )
    }

    private var isPrimaryMouseButtonPressed: Bool {
        // During a drag owned by Finder or another application, AppKit's
        // process-local pressedMouseButtons value can be stale. Query the
        // combined macOS session so hovering the shelf cannot steal key focus
        // and cancel the external drag before SwiftUI receives it.
        primaryMouseButtonPressed()
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

        panel.level = interactiveWindowLevel
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

        guard isShelfPresented, !presentation.isPinned, let panel, panel.isVisible else { return }

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

                panel.level = self.interactiveWindowLevel
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

    func togglePin() {
        presentation.isPinned.toggle()
        if presentation.isPinned {
            cancelHide()
            if isCollapsed { expand() }
        } else if !isHoveringShelf {
            collapse(after: 3)
        }
    }

    @discardableResult
    func handleKeyboardCommand(_ command: ShelfKeyboardCommand) -> Bool {
        // Never mutate the source selection or rows while AppKit owns a drag.
        guard !isPrimaryMouseButtonPressed, !isExternalDragActive else { return false }
        let selected = store.items.filter { selection.itemIDs.contains($0.id) }
        switch command {
        case .selectAll: selection.selectAll(in: store.items)
        case .navigate(let direction, let extending):
            selection.navigate(in: store.items, direction: direction, extending: extending)
        case .copy: _ = store.copy(selected)
        case .copyPaths:
            if !selected.isEmpty { store.copyPath(selected) }
        case .paste: _ = pasteFromClipboard()
        case .remove:
            store.remove(selected)
            selection.subtract(selected.map(\.id))
        case .open: store.open(selected)
        case .preview: store.quickLook(selected)
        case .togglePin: togglePin()
        case .escape:
            if selection.itemIDs.isEmpty { closeShelf() } else { selection.clear() }
        }
        return true
    }

    private func pasteFromClipboard() -> Bool {
        let countBefore = store.items.count
        guard store.importPasteboard() else {
            return false
        }
        dropState.report(ShelfImportOutcome(addedCount: store.items.count - countBefore, skippedCount: 0))

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
    var onCommand: ((ShelfKeyboardCommand) -> Bool)?
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
        if handleShortcut(event) {
            return
        }

        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleShortcut(event) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    private func handleShortcut(_ event: NSEvent) -> Bool {
        guard let command = ShelfKeyboardCommand(event: event) else { return false }
        if let onCommand { return onCommand(command) }
        return command == .paste && onPaste?() == true
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
