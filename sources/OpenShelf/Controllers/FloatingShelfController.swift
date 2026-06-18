import AppKit
import SwiftUI

final class FloatingShelfController {
    private let store = ShelfStore()

    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    private var currentScreen: NSScreen?
    private var currentEdge: ShelfEdge = .right
    private var isCollapsed = false

    private let panelSize = NSSize(width: 380, height: 280)
    private let visibleTabWidth: CGFloat = 32
    private let screenPadding: CGFloat = 8
    private let animationDuration: TimeInterval = 0.22

    func show(on screen: NSScreen? = nil, edge: ShelfEdge = .right) {
        cancelHide()
        if panel == nil {
            panel = makePanel()
        }
        guard let panel else { return }
        currentScreen = screen ?? NSScreen.main
        currentEdge = edge
        isCollapsed = false
        let expanded = frameForExpandedState(on: currentScreen, edge: currentEdge)
        panel.level = .statusBar  // ensure it floats above other windows
        panel.setFrame(expanded, display: true)
        panel.orderFrontRegardless()
    }

    func collapse(after delay: TimeInterval = 0.0) {
        hideWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.collapseNow()
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

    private func makePanel() -> NSPanel {
        let rootView = ContentView(
            store: store,
            onHoverChanged: { [weak self] isHovering in
                self?.handleHoverChanged(isHovering)
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
        panel.isMovableByWindowBackground = true

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
            collapse(after: 2.0)

            print("Shelf hover exited: collapse scheduled.")
        }
    }

    private func collapseNow() {
        guard let panel else { return }

        isCollapsed = true

        let collapsedFrame = frameForCollapsedState(
            on: currentScreen,
            edge: currentEdge
        )

        animate(panel: panel, to: collapsedFrame)
        panel.level = .floating

        print("Shelf collapsed to edge; always-on-top disabled.")

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

        let y = screenFrame.midY - panelSize.height / 2

        return NSRect(
            x: x,
            y: y,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    private func frameForCollapsedState(
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
            x = screenFrame.minX - panelSize.width + visibleTabWidth

        case .right:
            x = screenFrame.maxX - visibleTabWidth
        }

        let y = screenFrame.midY - panelSize.height / 2

        return NSRect(
            x: x,
            y: y,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    private func animate(panel: NSPanel, to frame: NSRect) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            panel.animator().setFrame(frame, display: true)
        }
    }
}
