import AppKit

/// Owns independent shelves. Screen-edge windows and the CLI remain shared.
@MainActor
final class ShelfManager {
    private(set) var shelves: [FloatingShelfController] = []
    private(set) var activeShelf: FloatingShelfController!
    private var preparedShelf: FloatingShelfController?

    init() {
        createShelf(show: false)
    }

    @discardableResult
    func createShelf(show: Bool = true, on screen: NSScreen? = nil,
                     edge: ShelfEdge? = nil, triggerY: CGFloat? = nil) -> FloatingShelfController {
        let shelf = preparedShelf ?? FloatingShelfController()
        preparedShelf = nil
        shelf.onInteraction = { [weak self, weak shelf] in
            guard let shelf else { return }
            self?.activate(shelf)
        }
        shelf.onNewShelf = { [weak self] in self?.createShelf() }
        shelves.append(shelf)
        activeShelf = shelf
        shelf.preparePanel()
        if show {
            let targetScreen = screen ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
                ?? NSScreen.main
            if let edge {
                shelf.show(on: targetScreen, edge: edge, triggerY: triggerY)
            } else {
                let placement = newShelfPlacement(on: targetScreen)
                shelf.show(on: targetScreen, edge: placement.edge, triggerY: placement.y)
            }
        }
        prepareNextShelf()
        return shelf
    }

    func activate(_ shelf: FloatingShelfController) {
        guard shelves.contains(where: { $0 === shelf }) else { return }
        activeShelf = shelf
    }

    func show(_ shelf: FloatingShelfController) {
        activate(shelf)
        shelf.reveal()
    }

    func remove(_ shelf: FloatingShelfController) {
        guard shelves.contains(where: { $0 === shelf }) else { return }
        shelf.disposePanels()
        shelf.clearShelf()
        // Exported temporary files must survive until app termination, even
        // when their source shelf has been removed from the menu.
        retiredStores.append(shelf.store)
        shelf.onInteraction = nil
        shelf.onNewShelf = nil
        shelves.removeAll { $0 === shelf }
        if shelves.isEmpty {
            createShelf(show: false)
        } else if activeShelf === shelf {
            activeShelf = shelves.last
        }
    }

    private var retiredStores: [ShelfStore] = []

    /// Pre-register a spare destination while idle so an edge drag does not
    /// need to create its AppKit windows mid-gesture.
    func prepareNextShelf() {
        guard preparedShelf == nil,
            NSEvent.pressedMouseButtons == 0,
            !CGEventSource.buttonState(.combinedSessionState, button: .left),
            !CGEventSource.buttonState(.combinedSessionState, button: .right) else { return }
        let shelf = FloatingShelfController()
        shelf.preparePanel()
        preparedShelf = shelf
    }

    /// An edge gesture starts an empty shelf, even on an occupied edge. Direct
    /// drops on a shelf still target that shelf through its own destination.
    /// Reuse only hidden, empty drafts (including the initial launch shelf).
    func shelfForEdge(on screen: NSScreen, edge: ShelfEdge, triggerY: CGFloat?) -> FloatingShelfController {
        if let shelf = shelves.first(where: { $0.visibleShelfFrame() == nil && $0.store.items.isEmpty }) {
            activate(shelf)
            return shelf
        }
        return createShelf(show: false)
    }

    @discardableResult
    func addAndShow(urls: [URL]) -> ShelfImportOutcome {
        activeShelf.addAndShow(urls: urls)
    }

    func prepareForTermination() {
        for shelf in shelves {
            shelf.disposePanels()
            shelf.prepareForTermination()
        }
        retiredStores.forEach { $0.cleanUpSession() }
        retiredStores.removeAll()
        preparedShelf?.disposePanels()
        preparedShelf?.prepareForTermination()
        preparedShelf = nil
    }

    private func newShelfPlacement(on screen: NSScreen?) -> (edge: ShelfEdge, y: CGFloat?) {
        guard let screen else { return (.right, nil) }
        let frame = screen.visibleFrame
        let occupied = shelves.compactMap { $0.expandedShelfFrame() }
        // Fill separate vertical slots before using the opposite edge.
        for edge in [ShelfEdge.right, .left] {
            let x = edge == .right ? frame.maxX - 308 : frame.minX + 8
            var y = frame.maxY - 208
            while y >= frame.minY {
                let proposed = NSRect(x: x, y: y, width: 300, height: 200)
                if !occupied.contains(where: { $0.insetBy(dx: -4, dy: -4).intersects(proposed) }) {
                    return (edge, proposed.midY)
                }
                y -= 212
            }
        }
        // On a full display, stagger titles so every shelf stays reachable
        // through either its header or the menu-bar shelf list.
        let offset = CGFloat((shelves.count - 1) % 6) * 28
        return (.right, frame.maxY - 108 - offset)
    }
}
