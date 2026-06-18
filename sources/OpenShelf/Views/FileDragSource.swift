import AppKit
import SwiftUI

struct FileDragSource: NSViewRepresentable {
    let item: ShelfItem
    let onSuccessfulDrag: () -> Void

    func makeNSView(context: Context) -> FileDragSourceView {
        let view = FileDragSourceView()
        view.item = item
        view.onSuccessfulDrag = onSuccessfulDrag
        return view
    }

    func updateNSView(
        _ view: FileDragSourceView,
        context: Context
    ) {
        view.item = item
        view.onSuccessfulDrag = onSuccessfulDrag
    }
}

final class FileDragSourceView: NSView, NSDraggingSource {
    var item: ShelfItem?
    var onSuccessfulDrag: (() -> Void)?

    override func mouseDragged(with event: NSEvent) {
        guard let item else { return }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(
            item.url.absoluteString,
            forType: .fileURL
        )

        let draggingItem = NSDraggingItem(
            pasteboardWriter: pasteboardItem
        )

        let icon = NSWorkspace.shared.icon(
            forFile: item.url.path
        )

        let size = NSSize(width: 48, height: 48)
        draggingItem.setDraggingFrame(
            NSRect(
                origin: convert(event.locationInWindow, from: nil),
                size: size
            ),
            contents: icon
        )

        beginDraggingSession(
            with: [draggingItem],
            event: event,
            source: self
        )
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        guard operation != [] else {
            print("Drag cancelled.")
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.onSuccessfulDrag?()
        }
    }
}
