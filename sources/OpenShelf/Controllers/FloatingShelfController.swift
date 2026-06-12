import AppKit
import SwiftUI

final class FloatingShelfController {
    private let store = ShelfStore()

    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    func show(on screen: NSScreen? = nil, edge: ShelfEdge = .right) {

        hideWorkItem?.cancel()

        hideWorkItem = nil

        if panel == nil {

            panel = makePanel()

        }

        guard let panel else { return }

        positionPanel(panel, on: screen, edge: edge)

        panel.orderFrontRegardless()

    }

    func hide(after delay: TimeInterval = 0.0) {

        hideWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in

            self?.panel?.orderOut(nil)

        }

        hideWorkItem = workItem

        if delay <= 0 {

            DispatchQueue.main.async(execute: workItem)

        } else {

            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)

        }

    }

    func clearShelf() {
        store.clear()
    }

    func toggleShelf() {
        guard let panel else {
            show()
            return
        }

        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    private func makePanel() -> NSPanel {
        let rootView = ContentView(
            store: store,
            onHoverChanged: { [weak self] isHovering in
                self?.setAlwaysOnTop(isHovering)
            }
        )

        let hostingView = NSHostingView(rootView: rootView)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [
                .titled,
                .closable,
                .resizable,
                .utilityWindow,
                .nonactivatingPanel,
            ],
            backing: .buffered,
            defer: false
        )

        panel.title = "OpenShelf"
        panel.contentView = hostingView

        // Default level when not hovering.
        panel.level = .floating

        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true

        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
        ]

        return panel
    }

    func cancelHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    private func setAlwaysOnTop(_ enabled: Bool) {
        guard let panel else { return }

        if enabled {
            cancelHide()

            panel.level = .statusBar
            panel.orderFrontRegardless()

            print("Shelf hover: always-on-top enabled; hide cancelled.")
        } else {
            panel.level = .floating

            hide(after: 3.0)

            print("Shelf hover: always-on-top disabled; hide scheduled.")
        }
    }

    private func positionPanel(
        _ panel: NSPanel,
        on screen: NSScreen?,
        edge: ShelfEdge
    ) {
        let targetScreen = screen ?? NSScreen.main

        guard let targetScreen else {
            panel.center()
            return
        }

        let screenFrame = targetScreen.visibleFrame
        let panelSize = panel.frame.size

        let x: CGFloat

        switch edge {
        case .left:
            x = screenFrame.minX + 8

        case .right:
            x = screenFrame.maxX - panelSize.width - 8
        }

        let y = screenFrame.midY - panelSize.height / 2

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
