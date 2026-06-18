import AppKit
import SwiftUI

@MainActor
final class FloatingShelfController {
    private let store = ShelfStore()

    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    private var currentScreen: NSScreen?
    private var currentEdge: ShelfEdge = .right
    private var currentTriggerY: CGFloat?
    private var isCollapsed = false

    private let panelSize = NSSize(width: 380, height: 280)
    private let visibleTabWidth: CGFloat = 32
    private let screenPadding: CGFloat = 8
    private let animationDuration: TimeInterval = 0.22

    func show(
        on screen: NSScreen? = nil,
        edge: ShelfEdge = .right,
        triggerY: CGFloat? = nil
    ) {
        cancelHide()
        if panel == nil {
            panel = makePanel()
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
        panel.level = .statusBar
        panel.setFrame(expandedFrame, display: true)
        panel.orderFrontRegardless()
    }
    func collapse(after delay: TimeInterval = 0.0) {
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
        guard let panel else { return }
        isCollapsed = false
        let expanded = frameForExpandedState(on: currentScreen, edge: currentEdge)
        panel.level = .statusBar  // raise level on expand as well
        panel.orderFrontRegardless()
        animate(panel: panel, to: expanded)
    }

    func toggleShelf() {
        guard let panel else {
            show()
            return
        }

        if panel.isVisible {
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

    func cancelHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    func closeShelf() {
        cancelHide()

        guard let panel else { return }

        panel.orderOut(nil)
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
            onHoverChanged: { [weak self] isHovering in
                self?.handleHoverChanged(isHovering)
            },
            onClose: { [weak self] in
                self?.closeShelf()
            }
        )

        let hostingView = NSHostingView(rootView: rootView)

        let panel = NSPanel(
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
        panel.contentView = hostingView

        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false

        return panel
    }

    private func handleHoverChanged(_ isHovering: Bool) {
        guard let panel else { return }

        if isHovering {
            cancelHide()

            // Always on top while cursor is on the shelf.
            panel.level = .statusBar
            panel.orderFrontRegardless()

            if isCollapsed {
                expand()
            }

            print("Shelf hover entered: always-on-top enabled.")
        } else {
            // Do NOT immediately lower the level here.
            // Keep it on top during the 3-second delay.
            collapse(after: 3.0)

            print("Shelf hover exited: collapse scheduled.")
        }
    }

    private func collapseNow() {
        guard let panel else { return }

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

        let collapsedFrame = frameForCollapsedState(
            on: targetScreen,
            edge: collapseEdge,
            originY: preservedY
        )

        let shouldCloseAfterCollapse = store.items.isEmpty

        animate(
            panel: panel,
            to: collapsedFrame
        ) { [weak self, weak panel] in
            Task { @MainActor in
                guard let self, let panel else { return }

                if shouldCloseAfterCollapse && self.store.items.isEmpty {
                    panel.orderOut(nil)
                    self.isCollapsed = false

                    print("Empty shelf collapsed and closed.")
                } else {
                    panel.level = .floating

                    print(
                        "Shelf collapsed to",
                        collapseEdge == .left ? "left edge." : "right edge."
                    )
                }
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

}
