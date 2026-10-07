import AppKit
import ShelfCore
import XCTest
@testable import OpenShelf

@MainActor
final class ShelfManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    func testNewShelvesHaveIndependentWindowsAndNonoverlappingPlacement() throws {
        let manager = ShelfManager()
        defer { manager.prepareForTermination() }
        let first = manager.activeShelf!
        manager.show(first)
        let second = manager.createShelf()
        let firstPanel = try panel(first)
        let secondPanel = try panel(second)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(firstPanel.title, "OpenShelf")
        XCTAssertEqual(secondPanel.title, "OpenShelf")
        XCTAssertTrue(firstPanel.isVisible && secondPanel.isVisible)
        XCTAssertFalse(firstPanel.frame.intersects(secondPanel.frame))
        XCTAssertEqual(firstPanel.level, .floating)
        XCTAssertEqual(secondPanel.level, .floating)
        try content(second).onNewShelf()
        XCTAssertEqual(manager.shelves.count, 3)
        XCTAssertEqual(manager.activeShelf.name, "OpenShelf")
    }

    func testSelectionPinAndClearAreIndependent() throws {
        let manager = ShelfManager()
        defer { manager.prepareForTermination() }
        let urls = try files()
        defer { removeFiles(urls) }
        let first = manager.activeShelf!
        let second = manager.createShelf()
        first.addAndShow(urls: urls)
        second.addAndShow(urls: urls)
        XCTAssertTrue(first.handleKeyboardCommand(.selectAll))
        XCTAssertTrue(first.handleKeyboardCommand(.togglePin))
        XCTAssertTrue(try content(first).presentation.isPinned)
        XCTAssertFalse(try content(second).presentation.isPinned)
        // Nothing is selected in the other shelf.
        XCTAssertTrue(second.handleKeyboardCommand(.remove))
        XCTAssertEqual(second.store.items.count, 2)
        XCTAssertTrue(first.handleKeyboardCommand(.remove))
        XCTAssertTrue(first.store.items.isEmpty)
        XCTAssertEqual(second.store.items.count, 2)
        XCTAssertTrue(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    func testCLIUsesActiveShelfWithoutMovingAnyExpandedWindow() throws {
        let manager = ShelfManager()
        defer { manager.prepareForTermination() }
        let urls = try files()
        defer { removeFiles(urls) }
        let first = manager.activeShelf!
        manager.show(first)
        let second = manager.createShelf()
        let firstPanel = try panel(first)
        let secondFrame = try panel(second).frame
        let movedFrame = firstPanel.frame.offsetBy(dx: -120, dy: -35)
        firstPanel.setFrame(movedFrame, display: false)
        try content(first).onHoverChanged(true)
        XCTAssertTrue(manager.activeShelf === first)
        XCTAssertEqual(manager.addAndShow(urls: [urls[0]]).addedCount, 1)
        manager.activate(second)
        XCTAssertEqual(manager.addAndShow(urls: [urls[1]]).addedCount, 1)
        XCTAssertEqual(first.store.items.map(\.url), [urls[0]])
        XCTAssertEqual(second.store.items.map(\.url), [urls[1]])
        XCTAssertEqual(firstPanel.frame, movedFrame)
        XCTAssertEqual(try panel(second).frame, secondFrame)
        let capture = try XCTUnwrap(NSApp.windows.first { $0.identifier?.rawValue == "\(first.id.uuidString)-drop-capture" && $0.isVisible })
        XCTAssertEqual(capture.frame, movedFrame, "Moving a shelf must move its fallback drop destination too.")
    }

    func testCLIRequestRetryDoesNotRetargetAfterActiveShelfChanges() throws {
        let manager = ShelfManager()
        defer { manager.prepareForTermination() }
        let urls = try files()
        defer { removeFiles(urls) }
        let mailbox = ShelfCommandMailbox(directory: urls[0].deletingLastPathComponent().appendingPathComponent("mailbox"))
        let receiver = ShelfCommandReceiver(addFiles: { manager.addAndShow(urls: $0) },
            notificationName: .init("OpenShelf.tests.multi.\(UUID())"), mailbox: mailbox)
        let first = manager.activeShelf!
        let request = ShelfCommandMailbox.Request(paths: [urls[0].path])
        try mailbox.submit(request)
        receiver.processPendingRequests()
        let second = manager.createShelf()
        try mailbox.submit(request)
        receiver.processPendingRequests()
        XCTAssertEqual(first.store.items.count, 1)
        XCTAssertTrue(second.store.items.isEmpty)
        XCTAssertEqual(mailbox.readReply(for: request.id)?.addedCount, 1)
    }

    func testDirectDropsTargetOnlyThePanelUnderThePointer() throws {
        let manager = ShelfManager()
        defer { manager.prepareForTermination() }
        let urls = try files()
        defer { removeFiles(urls) }
        let first = manager.activeShelf!
        manager.show(first)
        let second = manager.createShelf()
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        for (shelf, url) in [(first, urls[0]), (second, urls[1])] {
            board.clearContents()
            XCTAssertTrue(board.writeObjects([url as NSURL]))
            let destination = try panel(shelf)
            XCTAssertEqual(destination.updateDropTarget(for: board), .copy)
            XCTAssertTrue(try content(shelf).dropState.isTargeted)
            XCTAssertTrue(destination.performDrop(from: board))
            XCTAssertFalse(try content(shelf).dropState.isTargeted)
            XCTAssertTrue(manager.activeShelf === shelf)
        }
        XCTAssertEqual(first.store.items.map(\.url), [urls[0]])
        XCTAssertEqual(second.store.items.map(\.url), [urls[1]])
    }

    func testCrossShelfRowsImportAGroupInsteadOfReorderingUnrelatedRows() throws {
        let manager = ShelfManager()
        defer { manager.prepareForTermination() }
        let urls = try files()
        defer { removeFiles(urls) }
        let source = manager.activeShelf!
        source.addAndShow(urls: urls)
        let destination = manager.createShelf()
        destination.addAndShow(urls: [urls[1]])
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        XCTAssertTrue(board.writeObjects(source.store.items.map { ShelfDragPasteboardWriter(item: $0, shelfID: source.id) }))
        XCTAssertFalse(ShelfDropSupport.canImport(board, destinationShelfID: source.id))
        XCTAssertTrue(ShelfDropSupport.canImport(board, destinationShelfID: destination.id))
        let destinationPanel = try panel(destination)
        let row = FileDragSourceView(frame: .init(x: 10, y: 50, width: 200, height: 32))
        row.item = destination.store.items[0]
        var reordered = false
        row.onReorderDropEntered = { _, _ in reordered = true }
        destinationPanel.contentView?.addSubview(row)
        let drag = TestDraggingInfo(pasteboard: board, window: destinationPanel)
        XCTAssertEqual(row.draggingEntered(drag), .copy)
        XCTAssertTrue(try content(destination).dropState.isTargeted)
        XCTAssertTrue(row.prepareForDragOperation(drag))
        XCTAssertTrue(row.performDragOperation(drag))
        XCTAssertFalse(reordered)
        XCTAssertEqual(destination.store.items.map(\.url), [urls[1], urls[0]])
        XCTAssertEqual(board.string(forType: .init(shelfAcceptedDropPasteboardTypeIdentifier)), destination.id.uuidString)
        source.store.finishExport(source.store.items)
        XCTAssertTrue(source.store.items.isEmpty)
        XCTAssertTrue(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    func testSameShelfReorderDoesNotShowExternalDropCue() throws {
        let manager = ShelfManager()
        defer { manager.prepareForTermination() }
        let urls = try files()
        defer { removeFiles(urls) }
        let shelf = manager.activeShelf!
        shelf.addAndShow(urls: urls)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.writeObjects([ShelfDragPasteboardWriter(item: shelf.store.items[0], shelfID: shelf.id)])
        XCTAssertEqual(try panel(shelf).updateDropTarget(for: board), [])
        XCTAssertFalse(try panel(shelf).performDrop(from: board))
        let container = try XCTUnwrap(try panel(shelf).contentView as? ShelfDropContainerView<ContentView>)
        XCTAssertEqual(container.updateDropTarget(for: board), [])
        XCTAssertFalse(container.performDrop(from: board))
        XCTAssertFalse(try content(shelf).dropState.isTargeted)
        XCTAssertEqual(shelf.store.items.count, 2)
    }

    func testTransferredAndPastedClipsSurviveSourceShelfRemoval() throws {
        for paste in [false, true] {
            let manager = ShelfManager()
            defer { manager.prepareForTermination() }
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            board.setString("Independent clip", forType: .string)
            let source = manager.activeShelf!
            XCTAssertTrue(source.store.importPasteboard(board))
            let sourceItem = try XCTUnwrap(source.store.items.first)
            let destination = manager.createShelf()
            board.clearContents()
            if paste {
                XCTAssertTrue(source.store.copy(source.store.items, to: board))
                XCTAssertTrue(destination.store.importPasteboard(board))
            } else {
                board.writeObjects([ShelfDragPasteboardWriter(item: sourceItem, shelfID: source.id)])
                XCTAssertTrue(try panel(destination).performDrop(from: board))
            }
            let copy = try XCTUnwrap(destination.store.items.first)
            XCTAssertTrue(copy.isManagedByShelf)
            XCTAssertNotEqual(copy.url, sourceItem.url)
            manager.remove(source)
            XCTAssertEqual(try String(contentsOf: copy.url), "Independent clip")
            destination.clearShelf()
            XCTAssertFalse(FileManager.default.fileExists(atPath: copy.url.path))
        }
    }

    func testHideReopenAndRemoveDoNotAffectOtherShelves() throws {
        let manager = ShelfManager()
        defer { manager.prepareForTermination() }
        let urls = try files()
        defer { removeFiles(urls) }
        let first = manager.activeShelf!
        first.addAndShow(urls: urls)
        let second = manager.createShelf()
        let frame = try panel(first).frame
        first.closeShelf()
        XCTAssertNil(first.visibleShelfFrame())
        XCTAssertEqual(first.store.items.count, 2)
        XCTAssertNotNil(second.visibleShelfFrame())
        manager.show(first)
        XCTAssertEqual(first.visibleShelfFrame(), frame)
        manager.remove(first)
        XCTAssertEqual(manager.shelves.count, 1)
        XCTAssertTrue(manager.activeShelf === second)
        manager.remove(second)
        XCTAssertEqual(manager.shelves.count, 1)
        XCTAssertEqual(manager.activeShelf.name, "OpenShelf")
        XCTAssertNotEqual(manager.activeShelf.id, first.id)
        XCTAssertNotEqual(manager.activeShelf.id, second.id)
        XCTAssertTrue(manager.activeShelf.store.items.isEmpty)
        XCTAssertTrue(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    func testEdgeCreatesNewShelfEvenWhenShelvesAlreadyOccupyThatEdge() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let manager = ShelfManager()
        defer { manager.prepareForTermination() }
        let first = manager.activeShelf!
        first.show(on: screen, edge: .right, triggerY: screen.visibleFrame.maxY - 110)
        let second = manager.createShelf(on: screen, edge: .right, triggerY: screen.visibleFrame.minY + 110)
        let firstFrame = try panel(first).frame
        let secondFrame = try panel(second).frame
        let newRight = manager.shelfForEdge(on: screen, edge: .right, triggerY: firstFrame.midY)
        XCTAssertFalse(newRight === first || newRight === second)
        newRight.beginEdgeDrag(on: screen, edge: .right, triggerY: firstFrame.midY)
        newRight.endEdgeDrag()
        XCTAssertEqual(manager.shelves.count, 3)
        let left = manager.shelfForEdge(on: screen, edge: .left, triggerY: nil)
        XCTAssertFalse(left === first || left === second || left === newRight)
        left.beginEdgeDrag(on: screen, edge: .left, triggerY: nil)
        left.endEdgeDrag()
        XCTAssertEqual(first.visibleShelfFrame(), firstFrame)
        XCTAssertEqual(second.visibleShelfFrame(), secondFrame)
    }

    func testEdgeDragKeepsItsTargetEvenWhenActiveShelfChanges() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let manager = ShelfManager()
        defer { manager.prepareForTermination() }
        let urls = try files()
        defer { removeFiles(urls) }
        let first = manager.activeShelf!
        first.show(on: screen, edge: .right, triggerY: screen.visibleFrame.maxY - 110)
        let second = manager.createShelf(on: screen, edge: .left)
        let trigger = EdgeTriggerView(shelfProvider: { screen, edge, y in
            manager.shelfForEdge(on: screen, edge: edge, triggerY: y)
        }, screen: screen, edge: .right)
        let window = NSPanel(contentRect: NSRect(x: screen.frame.maxX - 12, y: screen.frame.minY,
            width: 12, height: screen.frame.height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = trigger
        defer { window.orderOut(nil) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.writeObjects([urls[0] as NSURL])
        let drag = TestDraggingInfo(pasteboard: board, window: window)
        XCTAssertEqual(trigger.draggingEntered(drag), .copy)
        let target = manager.activeShelf!
        XCTAssertFalse(target === first || target === second)
        manager.activate(second)
        XCTAssertTrue(trigger.performDragOperation(drag))
        XCTAssertEqual(target.store.items.map(\.url), [urls[0]])
        XCTAssertTrue(first.store.items.isEmpty)
        XCTAssertTrue(second.store.items.isEmpty)
        trigger.concludeDragOperation(drag)
    }

    func testRemovingSourceShelfKeepsExportedFilesUntilAppQuit() throws {
        let manager = ShelfManager()
        defer { manager.prepareForTermination() }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("Exported clip", forType: .string)
        let source = manager.activeShelf!
        source.store.importPasteboard(board)
        let url = try XCTUnwrap(source.store.items.first?.url)
        source.store.finishExport(source.store.items)
        manager.remove(source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        manager.prepareForTermination()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testConsecutiveEdgeDragsCreateShelvesButReentryReusesTheSamePreview() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let manager = ShelfManager()
        defer { manager.prepareForTermination() }
        let urls = try files()
        defer { removeFiles(urls) }
        let existing = manager.activeShelf!
        existing.addAndShow(urls: [urls[0]])
        let existingFrame = existing.visibleShelfFrame()
        let (trigger, window) = edgeFixture(manager: manager, screen: screen)
        defer { window.orderOut(nil) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.writeObjects([urls[1] as NSURL])
        let drag = TestDraggingInfo(pasteboard: board, window: window)

        XCTAssertEqual(trigger.draggingEntered(drag), .copy)
        let preview = manager.activeShelf!
        XCTAssertFalse(preview === existing)
        XCTAssertEqual(manager.shelves.count, 2)
        trigger.draggingExited(drag)
        // Model the capture-hide timer expiring during the same gesture.
        trigger.endShelfDropCapture()
        XCTAssertEqual(trigger.draggingEntered(drag), .copy)
        XCTAssertTrue(manager.activeShelf === preview)
        XCTAssertEqual(manager.shelves.count, 2)
        XCTAssertTrue(trigger.performDragOperation(drag))
        trigger.concludeDragOperation(drag)
        trigger.draggingEnded(drag)
        XCTAssertEqual(preview.store.items.map(\.url), [urls[1]])

        drag.draggingSequenceNumber = 2
        XCTAssertEqual(trigger.draggingEntered(drag), .copy)
        let next = manager.activeShelf!
        XCTAssertFalse(next === existing || next === preview)
        XCTAssertEqual(manager.shelves.count, 3)
        XCTAssertTrue(trigger.performDragOperation(drag))
        trigger.concludeDragOperation(drag)
        XCTAssertEqual(next.store.items.map(\.url), [urls[1]])
        XCTAssertEqual(existing.store.items.map(\.url), [urls[0]])
        XCTAssertEqual(existing.visibleShelfFrame(), existingFrame)

        // Direct content-area drops still add to the existing shelf.
        XCTAssertTrue(try panel(existing).performDrop(from: board))
        XCTAssertEqual(existing.store.items.map(\.url), urls)
        XCTAssertEqual(manager.shelves.count, 3)
    }

    func testCancelledEdgePreviewIsHiddenAndReusedByTheNextGesture() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let manager = ShelfManager()
        defer { manager.prepareForTermination() }
        let urls = try files()
        defer { removeFiles(urls) }
        let existing = manager.activeShelf!
        existing.addAndShow(urls: urls)
        let (trigger, window) = edgeFixture(manager: manager, screen: screen)
        defer { window.orderOut(nil) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.writeObjects([urls[0] as NSURL])
        let drag = TestDraggingInfo(pasteboard: board, window: window)
        XCTAssertEqual(trigger.draggingEntered(drag), .copy)
        let preview = manager.activeShelf!
        trigger.draggingExited(drag)
        trigger.draggingEnded(drag)
        XCTAssertNil(preview.visibleShelfFrame())
        XCTAssertNotNil(existing.visibleShelfFrame())
        XCTAssertEqual(existing.store.items.map(\.url), urls)

        drag.draggingSequenceNumber = 2
        XCTAssertEqual(trigger.draggingEntered(drag), .copy)
        XCTAssertTrue(manager.activeShelf === preview)
        XCTAssertEqual(manager.shelves.count, 2)
        trigger.draggingEnded(drag)
    }

    func testEdgeDoesNotReuseAHiddenPopulatedShelf() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let manager = ShelfManager()
        defer { manager.prepareForTermination() }
        let urls = try files()
        defer { removeFiles(urls) }
        let existing = manager.activeShelf!
        existing.addAndShow(urls: urls)
        existing.closeShelf()
        let target = manager.shelfForEdge(on: screen, edge: .right, triggerY: nil)
        XCTAssertFalse(target === existing)
        XCTAssertTrue(target.store.items.isEmpty)
        XCTAssertEqual(existing.store.items.map(\.url), urls)
        XCTAssertNil(existing.visibleShelfFrame())
    }

    func testCommandNCreatesAnotherShelfThroughTheNativePanel() throws {
        let manager = ShelfManager()
        defer { manager.prepareForTermination() }
        let first = manager.activeShelf!
        manager.show(first)
        let window = try panel(first)
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "n", charactersIgnoringModifiers: "n", isARepeat: false, keyCode: 45))
        XCTAssertTrue(window.performKeyEquivalent(with: event))
        XCTAssertEqual(manager.shelves.count, 2)
        XCTAssertTrue(window.isVisible)
        XCTAssertNotNil(manager.activeShelf.visibleShelfFrame())
        XCTAssertFalse(manager.activeShelf === first)
    }

    func testShelfCreatedForUnusedEdgeReusesPreRegisteredDestination() throws {
        let existingWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        let manager = ShelfManager()
        defer { manager.prepareForTermination() }
        let prepared = try XCTUnwrap(NSApp.windows.compactMap { $0 as? ShelfPanel }
            .first { $0.shelfID != manager.activeShelf.id && !$0.isVisible && !existingWindows.contains(ObjectIdentifier($0)) })
        XCTAssertTrue(prepared.registeredShelfDraggedTypes.contains(.fileURL))
        let second = manager.createShelf(show: false)
        XCTAssertTrue(try panel(second) === prepared)
        XCTAssertFalse(prepared.isVisible)
    }

    func testTransferredImageHasIndependentLifetime() throws {
        let manager = ShelfManager()
        defer { manager.prepareForTermination() }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            rect.fill()
            return true
        }
        XCTAssertTrue(board.writeObjects([image]))
        let source = manager.activeShelf!
        XCTAssertTrue(source.store.importPasteboard(board))
        let item = try XCTUnwrap(source.store.items.first)
        let destination = manager.createShelf()
        board.clearContents()
        board.writeObjects([ShelfDragPasteboardWriter(item: item, shelfID: source.id)])
        let container = try XCTUnwrap(try panel(destination).contentView as? ShelfDropContainerView<ContentView>)
        XCTAssertEqual(container.updateDropTarget(for: board), .copy)
        XCTAssertTrue(container.performDrop(from: board))
        let copied = try XCTUnwrap(destination.store.items.first)
        XCTAssertEqual(try Data(contentsOf: item.url), try Data(contentsOf: copied.url))
        source.clearShelf()
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.url.path))
        XCTAssertNotNil(NSImage(contentsOf: copied.url))
    }

    private func panel(_ shelf: FloatingShelfController) throws -> ShelfPanel {
        try XCTUnwrap(NSApp.windows.compactMap { $0 as? ShelfPanel }.first { $0.shelfID == shelf.id })
    }

    private func edgeFixture(manager: ShelfManager, screen: NSScreen) -> (EdgeTriggerView, NSPanel) {
        let trigger = EdgeTriggerView(shelfProvider: { screen, edge, y in
            manager.shelfForEdge(on: screen, edge: edge, triggerY: y)
        }, screen: screen, edge: .right)
        let window = NSPanel(contentRect: NSRect(x: screen.frame.maxX - 12, y: screen.frame.minY,
            width: 12, height: screen.frame.height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = trigger
        return (trigger, window)
    }

    private func content(_ shelf: FloatingShelfController) throws -> ContentView {
        try XCTUnwrap(try panel(shelf).contentView as? ShelfDropContainerView<ContentView>).rootView
    }

    private func files() throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpenShelf Multi \(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try ["First.txt", "Second.txt"].map {
            let url = directory.appendingPathComponent($0).standardizedFileURL
            try Data($0.utf8).write(to: url)
            return url
        }
    }

    private func removeFiles(_ urls: [URL]) {
        try? FileManager.default.removeItem(at: urls[0].deletingLastPathComponent())
    }
}

@MainActor
private final class TestDraggingInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let draggingDestinationWindow: NSWindow?
    let draggingSourceOperationMask: NSDragOperation = [.copy, .move]
    let draggingLocation = NSPoint(x: 5, y: 100)
    let draggedImageLocation = NSPoint.zero
    let draggedImage: NSImage? = nil
    let draggingSource: Any? = nil
    var draggingSequenceNumber = 1
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 0
    let springLoadingHighlight: NSSpringLoadingHighlight = .none

    init(pasteboard: NSPasteboard, window: NSWindow) {
        draggingPasteboard = pasteboard
        draggingDestinationWindow = window
    }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?,
        classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}
