import AppKit
import XCTest
@testable import OpenShelf

@MainActor
final class ShelfSelectionAndInteractionTests: XCTestCase {
    func testCommandClickTogglesRowsAndKeepsDeterministicAnchor() {
        let items = makeItems(count: 3)
        let selection = ShelfSelectionModel()

        selection.handleClick(on: items[0], in: items, modifiers: [])
        selection.handleClick(on: items[1], in: items, modifiers: .command)

        XCTAssertEqual(selection.itemIDs, [items[0].id, items[1].id])
        XCTAssertEqual(selection.anchorItemID, items[1].id)

        selection.handleClick(on: items[0], in: items, modifiers: .command)

        XCTAssertEqual(selection.itemIDs, [items[1].id])
        XCTAssertEqual(selection.anchorItemID, items[1].id)

        selection.handleClick(on: items[1], in: items, modifiers: .command)

        XCTAssertTrue(selection.itemIDs.isEmpty)
        XCTAssertNil(selection.anchorItemID)
    }

    func testShiftClickSelectsRangeInEitherDirection() {
        let items = makeItems(count: 5)
        let selection = ShelfSelectionModel()

        selection.handleClick(on: items[2], in: items, modifiers: [])
        selection.handleClick(on: items[4], in: items, modifiers: .shift)

        XCTAssertEqual(
            selection.itemIDs,
            Set(items[2...4].map(\.id))
        )

        selection.handleClick(on: items[0], in: items, modifiers: .shift)

        XCTAssertEqual(
            selection.itemIDs,
            Set(items[0...2].map(\.id))
        )
        XCTAssertEqual(selection.anchorItemID, items[2].id)
    }

    func testCommandShiftClickAddsRangeToExistingSelection() {
        let items = makeItems(count: 6)
        let selection = ShelfSelectionModel()

        selection.handleClick(on: items[1], in: items, modifiers: [])
        selection.handleClick(on: items[5], in: items, modifiers: .command)
        selection.handleClick(
            on: items[3],
            in: items,
            modifiers: [.command, .shift]
        )

        XCTAssertEqual(
            selection.itemIDs,
            Set([items[1].id, items[3].id, items[4].id, items[5].id])
        )
    }

    func testClickingSelectedRowPreservesGroupForDragAndActions() {
        let items = makeItems(count: 4)
        let selectedIDs = Set([items[0].id, items[2].id, items[3].id])
        let selection = ShelfSelectionModel(
            itemIDs: selectedIDs,
            anchorItemID: items[3].id
        )

        selection.handleClick(on: items[2], in: items, modifiers: [])

        XCTAssertEqual(selection.itemIDs, selectedIDs)
        XCTAssertEqual(selection.anchorItemID, items[2].id)
        XCTAssertEqual(
            selection.resolvedItems(for: items[2], in: items),
            [items[0], items[2], items[3]]
        )
        XCTAssertEqual(
            selection.resolvedItems(for: items[1], in: items),
            [items[1]]
        )
    }

    func testSelectionPrunesRemovedRowsAndClearsExplicitly() {
        let items = makeItems(count: 3)
        let selection = ShelfSelectionModel(
            itemIDs: Set(items.map(\.id)),
            anchorItemID: items[2].id
        )

        selection.prune(to: Array(items.prefix(2)))

        XCTAssertEqual(selection.itemIDs, Set(items.prefix(2).map(\.id)))
        XCTAssertEqual(selection.anchorItemID, items[0].id)

        selection.clear()

        XCTAssertTrue(selection.itemIDs.isEmpty)
        XCTAssertNil(selection.anchorItemID)
    }

    func testMarqueeSelectionShrinksWhenCursorReverses() {
        let items = makeItems(count: 4)
        let frames = rowFrames(for: items)

        let forwardSelection = ShelfInteractionGeometry.marqueeSelectionIDs(
            rowOrder: items.map(\.id),
            rowContentFrames: frames,
            startContentY: -5,
            currentContentY: 138
        )
        XCTAssertEqual(forwardSelection, Set(items.map(\.id)))

        let reversedSelection = ShelfInteractionGeometry.marqueeSelectionIDs(
            rowOrder: items.map(\.id),
            rowContentFrames: frames,
            startContentY: -5,
            currentContentY: 50
        )
        XCTAssertEqual(reversedSelection, Set(items.prefix(2).map(\.id)))
    }

    func testCommandMarqueeAddsToExistingSelection() {
        let items = makeItems(count: 4)
        let frames = rowFrames(for: items)

        let selection = ShelfInteractionGeometry.marqueeSelectionIDs(
            rowOrder: items.map(\.id),
            rowContentFrames: frames,
            startContentY: 70,
            currentContentY: 140,
            baseItemIDs: [items[0].id]
        )

        XCTAssertEqual(
            selection,
            Set([items[0].id, items[2].id, items[3].id])
        )
    }

    func testSingleRowCanStartDragOutInEveryDirection() {
        XCTAssertEqual(
            ShelfInteractionGeometry.rowDragIntent(
                deltaX: 0,
                deltaY: 4,
                canReorder: false
            ),
            .dragOut
        )
        XCTAssertEqual(
            ShelfInteractionGeometry.rowDragIntent(
                deltaX: 0,
                deltaY: -4,
                canReorder: false
            ),
            .dragOut
        )
        XCTAssertEqual(
            ShelfInteractionGeometry.rowDragIntent(
                deltaX: 4,
                deltaY: 0,
                canReorder: false
            ),
            .dragOut
        )
    }

    func testReorderDirectionIsSymmetricAndDeliberatelyThresholded() {
        XCTAssertEqual(
            ShelfInteractionGeometry.rowDragIntent(
                deltaX: 0,
                deltaY: 7.9,
                canReorder: true
            ),
            .pending
        )
        XCTAssertEqual(
            ShelfInteractionGeometry.rowDragIntent(
                deltaX: 0,
                deltaY: 8,
                canReorder: true
            ),
            .reorder
        )
        XCTAssertEqual(
            ShelfInteractionGeometry.rowDragIntent(
                deltaX: 0,
                deltaY: -8,
                canReorder: true
            ),
            .reorder
        )
        XCTAssertEqual(
            ShelfInteractionGeometry.rowDragIntent(
                deltaX: 4,
                deltaY: 0,
                canReorder: true
            ),
            .dragOut
        )
        XCTAssertGreaterThanOrEqual(
            ShelfInteractionGeometry.reorderCooldown,
            0.1
        )
        XCTAssertGreaterThanOrEqual(
            ShelfInteractionGeometry.reorderTargetInset,
            8
        )
    }

    func testAutoScrollOnlyRunsInsideTopOrBottomEdgeZone() throws {
        let frame = CGRect(x: 0, y: 0, width: 300, height: 160)

        XCTAssertNil(
            ShelfInteractionGeometry.autoScrollDelta(
                for: CGPoint(x: -1, y: 5),
                in: frame,
                documentIsFlipped: true
            )
        )
        XCTAssertNil(
            ShelfInteractionGeometry.autoScrollDelta(
                for: CGPoint(x: 150, y: 80),
                in: frame,
                documentIsFlipped: true
            )
        )
        XCTAssertLessThan(
            try XCTUnwrap(
                ShelfInteractionGeometry.autoScrollDelta(
                    for: CGPoint(x: 150, y: 155),
                    in: frame,
                    documentIsFlipped: true
                )
            ),
            0
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(
                ShelfInteractionGeometry.autoScrollDelta(
                    for: CGPoint(x: 150, y: 5),
                    in: frame,
                    documentIsFlipped: true
                )
            ),
            0
        )
    }

    func testSelectionOverlayNeverInterceptsOneOrTwoFileRows() {
        let items = makeItems(count: 2)
        let overlay = ShelfSelectionOverlayView(
            frame: CGRect(x: 0, y: 0, width: 300, height: 164)
        )
        overlay.rowOrder = items.map(\.id)
        overlay.rowFrames = [
            items[0].id: CGRect(x: 10, y: 0, width: 280, height: 50),
            items[1].id: CGRect(x: 10, y: 56, width: 280, height: 50),
        ]

        XCTAssertNil(overlay.hitTest(CGPoint(x: 100, y: 139)))
        XCTAssertNil(overlay.hitTest(CGPoint(x: 100, y: 84)))
        XCTAssertTrue(overlay.hitTest(CGPoint(x: 4, y: 84)) === overlay)

        overlay.rowOrder = [items[0].id]
        overlay.rowFrames = [
            items[0].id: CGRect(x: 10, y: 0, width: 280, height: 50)
        ]

        XCTAssertNil(overlay.hitTest(CGPoint(x: 100, y: 139)))
        XCTAssertTrue(overlay.hitTest(CGPoint(x: 4, y: 139)) === overlay)
    }

    func testSelectionOverlayYieldsScrollbarRegion() throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 300, height: 164),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }

        let rootView = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = rootView

        let scrollView = NSScrollView(frame: rootView.bounds)
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .legacy
        scrollView.documentView = NSView(
            frame: CGRect(x: 0, y: 0, width: 280, height: 600)
        )
        rootView.addSubview(scrollView)

        let item = makeItems(count: 1)[0]
        let overlay = ShelfSelectionOverlayView(frame: rootView.bounds)
        overlay.rowOrder = [item.id]
        overlay.rowFrames = [
            item.id: CGRect(x: 10, y: 0, width: 270, height: 50)
        ]
        rootView.addSubview(overlay, positioned: .above, relativeTo: scrollView)
        rootView.layoutSubtreeIfNeeded()
        scrollView.tile()

        let scroller = try XCTUnwrap(scrollView.verticalScroller)
        let scrollerCenterInWindow = scroller.convert(
            CGPoint(x: scroller.bounds.midX, y: scroller.bounds.midY),
            to: nil
        )
        let pointInOverlay = overlay.convert(scrollerCenterInWindow, from: nil)

        XCTAssertNil(overlay.hitTest(pointInOverlay))
    }

    func testSelectionOverlayMousePathSelectsForwardAndDeselectsOnReverse() throws {
        _ = NSApplication.shared
        let items = makeItems(count: 3)
        let overlay = ShelfSelectionOverlayView(
            frame: CGRect(x: 0, y: 0, width: 300, height: 164)
        )
        overlay.rowOrder = items.map(\.id)
        overlay.rowFrames = [
            items[0].id: CGRect(x: 10, y: 0, width: 280, height: 50),
            items[1].id: CGRect(x: 10, y: 56, width: 280, height: 50),
            items[2].id: CGRect(x: 10, y: 112, width: 280, height: 50),
        ]
        var selectionUpdates: [Set<ShelfItem.ID>] = []
        overlay.onSelectionChanged = { itemIDs, _ in
            selectionUpdates.append(itemIDs)
        }

        let window = NSWindow(
            contentRect: overlay.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = overlay
        defer { window.orderOut(nil) }

        overlay.mouseDown(
            with: try mouseEvent(
                type: .leftMouseDown,
                point: CGPoint(x: 5, y: 150),
                window: window
            )
        )
        overlay.mouseDragged(
            with: try mouseEvent(
                type: .leftMouseDragged,
                point: CGPoint(x: 5, y: 20),
                window: window
            )
        )

        XCTAssertEqual(selectionUpdates.last, Set(items.map(\.id)))

        overlay.mouseDragged(
            with: try mouseEvent(
                type: .leftMouseDragged,
                point: CGPoint(x: 5, y: 80),
                window: window
            )
        )

        XCTAssertEqual(
            selectionUpdates.last,
            Set(items.prefix(2).map(\.id))
        )

        overlay.mouseUp(
            with: try mouseEvent(
                type: .leftMouseUp,
                point: CGPoint(x: 5, y: 80),
                window: window
            )
        )
    }

    func testClickingSideAreaWithoutDraggingClearsSelection() throws {
        _ = NSApplication.shared
        let item = makeItems(count: 1)[0]
        let overlay = ShelfSelectionOverlayView(
            frame: CGRect(x: 0, y: 0, width: 300, height: 164)
        )
        overlay.rowOrder = [item.id]
        overlay.rowFrames = [
            item.id: CGRect(x: 10, y: 0, width: 280, height: 50)
        ]
        var clearCount = 0
        overlay.onClearSelection = {
            clearCount += 1
        }

        let window = NSWindow(
            contentRect: overlay.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = overlay
        defer { window.orderOut(nil) }

        overlay.mouseDown(
            with: try mouseEvent(
                type: .leftMouseDown,
                point: CGPoint(x: 4, y: 120),
                window: window
            )
        )
        overlay.mouseUp(
            with: try mouseEvent(
                type: .leftMouseUp,
                point: CGPoint(x: 4, y: 120),
                window: window
            )
        )

        XCTAssertEqual(clearCount, 1)
    }

    func testMultipleSelectedFilesAreWrittenToOneDragPasteboard() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenShelf Multi Drag \(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let items = try ["First.txt", "Second.txt", "Third.txt"].map {
            name -> ShelfItem in
            let url = directory.appendingPathComponent(name)
            try Data(name.utf8).write(to: url)
            return ShelfItem(url: url)
        }
        defer { try? FileManager.default.removeItem(at: directory) }

        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        XCTAssertTrue(
            pasteboard.writeObjects(
                items.map { ShelfDragPasteboardWriter(item: $0) }
            )
        )

        let draggedURLs = try XCTUnwrap(
            pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL]
        )

        XCTAssertEqual(draggedURLs, items.map(\.url))
        XCTAssertTrue(
            pasteboard.types?.contains(
                NSPasteboard.PasteboardType(
                    shelfReorderPasteboardTypeIdentifier
                )
            ) == true
        )
    }

    private func makeItems(count: Int) -> [ShelfItem] {
        (0..<count).map { index in
            ShelfItem(
                url: URL(fileURLWithPath: "/tmp/OpenShelf Item \(index).txt")
            )
        }
    }

    private func rowFrames(
        for items: [ShelfItem]
    ) -> [ShelfItem.ID: CGRect] {
        Dictionary(uniqueKeysWithValues: items.enumerated().map { index, item in
            (
                item.id,
                CGRect(
                    x: 10,
                    y: CGFloat(index) * 36,
                    width: 280,
                    height: 30
                )
            )
        })
    }

    private func mouseEvent(
        type: NSEvent.EventType,
        point: CGPoint,
        window: NSWindow
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1
            )
        )
    }
}
