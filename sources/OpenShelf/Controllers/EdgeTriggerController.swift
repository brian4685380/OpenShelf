import AppKit

@MainActor
final class EdgeTriggerController {
    private weak var shelfController: FloatingShelfController?
    private var triggerPanels: [NSPanel] = []
    private let canReorderWindows: @MainActor () -> Bool

    private let triggerWidth: CGFloat = 12
    // Generic transparent NSPanel drag destinations stop receiving reliable
    // cross-process drags at .screenSaver on current macOS releases. Keep the
    // edge strip at AppKit's interactive floating level and restore its front
    // ordering after foreground-window changes instead.
    private let triggerWindowLevel = NSWindow.Level.floating

    init(
        shelfController: FloatingShelfController,
        canReorderWindows: @escaping @MainActor () -> Bool = {
            !CGEventSource.buttonState(
                .combinedSessionState,
                button: .left
            )
                && !CGEventSource.buttonState(
                    .combinedSessionState,
                    button: .right
                )
        }
    ) {
        self.shelfController = shelfController
        self.canReorderWindows = canReorderWindows
    }

    func start() {
        stop()

        for screen in NSScreen.screens {
            let leftPanel = makeTriggerPanel(for: screen, edge: .left)
            let rightPanel = makeTriggerPanel(for: screen, edge: .right)

            triggerPanels.append(leftPanel)
            triggerPanels.append(rightPanel)

            leftPanel.orderFrontRegardless()
            rightPanel.orderFrontRegardless()
        }

        print("Left and right edge trigger panels started.")
    }

    func stop() {
        for panel in triggerPanels {
            panel.orderOut(nil)
        }

        triggerPanels.removeAll()
    }

    func refresh() {
        // Reordering a destination while Finder owns a drag can make AppKit
        // cancel or retarget that drag. The maintenance heartbeat will retry
        // immediately after the mouse button is released.
        guard canReorderWindows() else {
            return
        }

        for panel in triggerPanels {
            configureFloatingBehavior(for: panel)
            panel.orderFrontRegardless()
        }
    }

    private func makeTriggerPanel(
        for screen: NSScreen,
        edge: ShelfEdge
    ) -> NSPanel {
        let x: CGFloat

        switch edge {
        case .left:
            x = screen.frame.minX

        case .right:
            x = screen.frame.maxX - triggerWidth
        }

        let frame = NSRect(
            x: x,
            y: screen.frame.minY,
            width: triggerWidth,
            height: screen.frame.height
        )

        let triggerView = EdgeTriggerView(
            shelfController: shelfController,
            screen: screen,
            edge: edge
        )

        triggerView.frame = NSRect(
            x: 0,
            y: 0,
            width: triggerWidth,
            height: screen.frame.height
        )

        triggerView.autoresizingMask = [
            .width,
            .height,
        ]

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [
                .borderless,
                .nonactivatingPanel,
            ],
            backing: .buffered,
            defer: false
        )

        panel.contentView = triggerView

        configureFloatingBehavior(for: panel)
        panel.hasShadow = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = false

        return panel
    }

    private func configureFloatingBehavior(for panel: NSPanel) {
        panel.isFloatingPanel = true
        // NSPanel may reset its level when this flag changes. Set the intended
        // interactive trigger level afterwards, then let refresh() restore its
        // front ordering after foreground-window changes.
        panel.level = triggerWindowLevel
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
    }
}
