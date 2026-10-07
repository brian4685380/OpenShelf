import AppKit
import SwiftUI

final class ShelfDropContainerView<Content: View>: NSView {
    let hostingView: ShelfDropHostingView<Content>

    var rootView: Content {
        get { hostingView.rootView }
        set { hostingView.rootView = newValue }
    }

    var onDropTargetChanged: ((Bool) -> Void)? {
        didSet {
            hostingView.onDropTargetChanged = onDropTargetChanged
        }
    }

    var onPerformDrop: ((NSPasteboard) -> Bool)? {
        didSet {
            hostingView.onPerformDrop = onPerformDrop
        }
    }

    init(rootView: Content) {
        hostingView = ShelfDropHostingView(rootView: rootView)
        super.init(frame: .zero)

        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
        registerForDraggedTypes(ShelfDropSupport.readableDraggedTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateDropTarget(
        for pasteboard: NSPasteboard
    ) -> NSDragOperation {
        hostingView.updateDropTarget(for: pasteboard)
    }

    func performDrop(from pasteboard: NSPasteboard) -> Bool {
        hostingView.performDrop(from: pasteboard)
    }

    func clearDropTarget() {
        hostingView.clearDropTarget()
    }

    override func draggingEntered(
        _ sender: NSDraggingInfo
    ) -> NSDragOperation {
        print(
            "Visible shelf container received drag:",
            sender.draggingPasteboard.types?.map(\.rawValue) ?? []
        )
        return hostingView.draggingEntered(sender)
    }

    override func draggingUpdated(
        _ sender: NSDraggingInfo
    ) -> NSDragOperation {
        hostingView.draggingUpdated(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        hostingView.draggingExited(sender)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        hostingView.draggingEnded(sender)
    }

    override func prepareForDragOperation(
        _ sender: NSDraggingInfo
    ) -> Bool {
        hostingView.prepareForDragOperation(sender)
    }

    override func performDragOperation(
        _ sender: NSDraggingInfo
    ) -> Bool {
        hostingView.performDragOperation(sender)
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        hostingView.concludeDragOperation(sender)
    }

    override func wantsPeriodicDraggingUpdates() -> Bool {
        false
    }
}

final class ShelfDropHostingView<Content: View>: NSHostingView<Content> {
    var destinationShelfID: UUID?
    var onDropTargetChanged: ((Bool) -> Void)?
    var onPerformDrop: ((NSPasteboard) -> Bool)?

    private var isDropTargeted = false

    required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes(ShelfDropSupport.readableDraggedTypes)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        // NSHostingView may rebuild its internal hierarchy when attached to a
        // window. Reassert the native destination on the actual full-size
        // hosting view after that reconciliation has happened.
        registerForDraggedTypes(ShelfDropSupport.readableDraggedTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(
        _ sender: NSDraggingInfo
    ) -> NSDragOperation {
        print(
            "Visible shelf content received drag:",
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

    override func draggingUpdated(
        _ sender: NSDraggingInfo
    ) -> NSDragOperation {
        updateDropTarget(for: sender.draggingPasteboard)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        clearDropTarget()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        clearDropTarget()
    }

    override func prepareForDragOperation(
        _ sender: NSDraggingInfo
    ) -> Bool {
        ShelfDropSupport.canImport(sender.draggingPasteboard, destinationShelfID: destinationShelfID)
    }

    override func performDragOperation(
        _ sender: NSDraggingInfo
    ) -> Bool {
        performDrop(from: sender.draggingPasteboard)
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        clearDropTarget()
    }

    override func wantsPeriodicDraggingUpdates() -> Bool {
        false
    }

    func updateDropTarget(
        for pasteboard: NSPasteboard
    ) -> NSDragOperation {
        guard ShelfDropSupport.canImport(pasteboard, destinationShelfID: destinationShelfID) else {
            clearDropTarget()
            return []
        }

        setDropTargeted(true)
        return .copy
    }

    func performDrop(from pasteboard: NSPasteboard) -> Bool {
        guard ShelfDropSupport.canImport(pasteboard, destinationShelfID: destinationShelfID) else {
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
