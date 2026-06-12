import AppKit

final class EdgeTriggerController {
    private weak var shelfController: FloatingShelfController?
    private var triggerPanels: [NSPanel] = []

    private let triggerWidth: CGFloat = 12

    init(shelfController: FloatingShelfController) {
        self.shelfController = shelfController
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

        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = false

        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]

        return panel
    }
}
