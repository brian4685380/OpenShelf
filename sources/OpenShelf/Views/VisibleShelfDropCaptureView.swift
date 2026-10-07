import AppKit

@MainActor
final class VisibleShelfDropCaptureView: NSView {
    private weak var shelfController: FloatingShelfController?

    init(shelfController: FloatingShelfController) {
        self.shelfController = shelfController
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        registerForDraggedTypes(ShelfDropSupport.readableDraggedTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(
        _ sender: NSDraggingInfo
    ) -> NSDragOperation {
        guard canImport(sender.draggingPasteboard) else {
            return []
        }

        print(
            "Visible shelf fallback received drag:",
            sender.draggingPasteboard.types?.map(\.rawValue) ?? []
        )
        shelfController?.beginVisibleShelfDrag()
        sender.numberOfValidItemsForDrop = max(
            1,
            sender.draggingPasteboard.pasteboardItems?.count ?? 1
        )
        return .copy
    }

    override func draggingUpdated(
        _ sender: NSDraggingInfo
    ) -> NSDragOperation {
        canImport(sender.draggingPasteboard) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        shelfController?.endVisibleShelfDrag()
    }

    override func prepareForDragOperation(
        _ sender: NSDraggingInfo
    ) -> Bool {
        canImport(sender.draggingPasteboard)
    }

    override func performDragOperation(
        _ sender: NSDraggingInfo
    ) -> Bool {
        shelfController?.performVisibleShelfDrop(
            from: sender.draggingPasteboard
        ) ?? false
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        shelfController?.endVisibleShelfDrag()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        shelfController?.endVisibleShelfDrag()
    }

    override func wantsPeriodicDraggingUpdates() -> Bool {
        false
    }

    private func canImport(_ pasteboard: NSPasteboard) -> Bool {
        guard let shelfController else { return false }
        return ShelfDropSupport.canImport(pasteboard, destinationShelfID: shelfController.id)
    }
}
