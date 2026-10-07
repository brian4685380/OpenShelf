import AppKit

@MainActor
final class EdgeTriggerController {
    private let shelfProvider: (NSScreen, ShelfEdge, CGFloat?) -> FloatingShelfController?
    private var triggerPanels: [NSPanel] = []
    private let canReorderWindows: @MainActor () -> Bool
    private var needsScreenRebuild = false

    private let triggerWidth: CGFloat = 12

    convenience init(
        shelfController: FloatingShelfController,
        canReorderWindows: @escaping @MainActor () -> Bool = {
            !CGEventSource.buttonState(.combinedSessionState, button: .left)
                && !CGEventSource.buttonState(.combinedSessionState, button: .right)
        }
    ) {
        self.init(shelfProvider: { [weak shelfController] _, _, _ in shelfController },
                  canReorderWindows: canReorderWindows)
    }

    init(
        shelfProvider: @escaping (NSScreen, ShelfEdge, CGFloat?) -> FloatingShelfController?,
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
        self.shelfProvider = shelfProvider
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
        needsScreenRebuild = false
        for panel in triggerPanels {
            panel.orderOut(nil)
        }

        triggerPanels.removeAll()
    }

    func screenParametersDidChange() {
        needsScreenRebuild = true
        refresh()
    }

    func refresh() {
        // Reordering a destination while Finder owns a drag can make AppKit
        // cancel or retarget that drag. The maintenance heartbeat will retry
        // immediately after the mouse button is released.
        guard canReorderWindows() else {
            return
        }

        if needsScreenRebuild {
            start()
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
            shelfProvider: shelfProvider,
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
        ShelfWindowPolicy.apply(to: panel)
    }
}
