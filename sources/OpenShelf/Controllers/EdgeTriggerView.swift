import AppKit

@MainActor
final class EdgeTriggerView: NSView {
    private weak var shelfController: FloatingShelfController?
    private let screen: NSScreen
    private let edge: ShelfEdge

    init(
        shelfController: FloatingShelfController?,
        screen: NSScreen,
        edge: ShelfEdge
    ) {
        self.shelfController = shelfController
        self.screen = screen
        self.edge = edge

        super.init(frame: .zero)

        wantsLayer = true

        // Normal invisible trigger strip.
        layer?.backgroundColor = NSColor.clear.cgColor

        // Debug option:
        // Uncomment this line if you want to see the trigger strips.
        // layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.25).cgColor

        registerForDraggedTypes([
            .fileURL
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        switch edge {
        case .left:
            print("Drag entered left edge.")

        case .right:
            print("Drag entered right edge.")
        }

        shelfController?.show(on: screen, edge: edge, triggerY: triggerPositionY(from: sender))
        return .copy
    }

    override func draggingUpdated(
        _ sender: NSDraggingInfo
    ) -> NSDragOperation {
        .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
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
