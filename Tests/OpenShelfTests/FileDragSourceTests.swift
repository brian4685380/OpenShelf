import AppKit
import XCTest
@testable import OpenShelf

@MainActor
final class FileDragSourceTests: XCTestCase {
    func testReorderCanBecomeAFileDragThroughEveryShelfEdge() throws {
        let exits = [
            NSPoint(x: 60, y: 201), // top
            NSPoint(x: 60, y: -1),  // bottom
            NSPoint(x: -1, y: 60),  // left after starting vertically
            NSPoint(x: 301, y: 60), // right after starting vertically
        ]

        for exit in exits {
            let fixture = makeFixture()
            defer { fixture.window.orderOut(nil) }
            let source = fixture.source
            var started = 0
            var reordered: [ShelfItem] = []
            source.onDragStarted = { started += 1 }
            source.onReorderDropEntered = { _, target in reordered.append(target) }

            try beginReorder(in: fixture)
            XCTAssertEqual(reordered, [fixture.items[1]])
            XCTAssertTrue(source.sessions.isEmpty)

            source.mouseDragged(with: try event(.leftMouseDragged, at: exit, in: fixture.window))

            XCTAssertEqual(source.sessions.count, 1, "Exit at \(exit) must hand off to AppKit")
            XCTAssertEqual(started, 1, "Changing drag mode must not restart the selection")
            let session = try XCTUnwrap(source.sessions.first)
            XCTAssertEqual(fileURLs(in: session.items), [fixture.items[0].url.absoluteString])
            XCTAssertEqual(session.event.locationInWindow, exit)

            source.mouseDragged(with: try event(.leftMouseDragged, at: exit, in: fixture.window))
            XCTAssertEqual(source.sessions.count, 1, "Only one native drag may own a gesture")
            source.mouseUp(with: try event(.leftMouseUp, at: exit, in: fixture.window))
        }
    }

    func testFastVerticalExitStartsFileDragWithoutEnteringReorderMode() throws {
        for exit in [NSPoint(x: 60, y: 230), NSPoint(x: 60, y: -30)] {
            let fixture = makeFixture()
            defer { fixture.window.orderOut(nil) }
            var reorderCount = 0
            fixture.source.onReorderDropEntered = { _, _ in reorderCount += 1 }
            fixture.source.mouseDown(with: try event(.leftMouseDown, at: NSPoint(x: 60, y: 96), in: fixture.window))
            fixture.source.mouseDragged(with: try event(.leftMouseDragged, at: exit, in: fixture.window))

            XCTAssertEqual(fixture.source.sessions.count, 1)
            XCTAssertEqual(reorderCount, 0)
            fixture.source.mouseUp(with: try event(.leftMouseUp, at: exit, in: fixture.window))
        }
    }

    func testHandoffPreservesSelectedFilesAndAnchorsPreviewAfterRowMoves() throws {
        let fixture = makeFixture()
        defer { fixture.window.orderOut(nil) }
        let source = fixture.source
        source.dragItems = [fixture.items[0], fixture.items[2]]
        try beginReorder(in: fixture)

        // Model the representable updating while rows move or scroll. The
        // ongoing gesture must retain its original selection and cursor anchor.
        source.dragItems = [fixture.items[1]]
        source.frame.origin.y = 140
        let exit = NSPoint(x: 60, y: 210)
        source.mouseDragged(with: try event(.leftMouseDragged, at: exit, in: fixture.window))

        let session = try XCTUnwrap(source.sessions.first)
        XCTAssertEqual(fileURLs(in: session.items), [fixture.items[0], fixture.items[2]].map { $0.url.absoluteString })
        let preview = try XCTUnwrap(session.items.first).draggingFrame
        let cursor = source.convert(exit, from: nil)
        XCTAssertEqual(preview.midX, cursor.x, accuracy: 0.01)
        XCTAssertEqual(preview.midY, cursor.y, accuracy: 0.01)
        source.mouseUp(with: try event(.leftMouseUp, at: exit, in: fixture.window))
    }

    func testInternalReorderRemainsInternalIncludingAtScrollEdges() throws {
        let fixture = makeFixture()
        defer { fixture.window.orderOut(nil) }
        try beginReorder(in: fixture)

        for point in [NSPoint(x: 60, y: 1), NSPoint(x: 60, y: 199)] {
            fixture.source.mouseDragged(with: try event(.leftMouseDragged, at: point, in: fixture.window))
            XCTAssertTrue(fixture.source.sessions.isEmpty)
        }

        let ended = expectation(description: "reordering ended")
        fixture.source.onDragEnded = { ended.fulfill() }
        fixture.source.mouseUp(with: try event(.leftMouseUp, at: NSPoint(x: 60, y: 199), in: fixture.window))
        wait(for: [ended], timeout: 1)
        fixture.source.mouseDragged(with: try event(.leftMouseDragged, at: NSPoint(x: 60, y: 210), in: fixture.window))
        XCTAssertTrue(fixture.source.sessions.isEmpty, "Mouse release must end the gesture")
    }

    func testSingleRowCanStartANativeVerticalDrag() throws {
        for deltaY: CGFloat in [-4, 4] {
            let fixture = makeFixture()
            defer { fixture.window.orderOut(nil) }
            fixture.window.contentView?.subviews
                .filter { $0 !== fixture.source }
                .forEach { $0.removeFromSuperview() }
            let start = NSPoint(x: 60, y: 96)
            let point = NSPoint(x: start.x, y: start.y + deltaY)
            fixture.source.mouseDown(with: try event(.leftMouseDown, at: start, in: fixture.window))
            fixture.source.mouseDragged(with: try event(.leftMouseDragged, at: point, in: fixture.window))
            XCTAssertEqual(fixture.source.sessions.count, 1)
            fixture.source.mouseUp(with: try event(.leftMouseUp, at: point, in: fixture.window))
        }
    }

    private struct Fixture {
        let window: NSWindow
        let source: RecordingFileDragSourceView
        let items: [ShelfItem]
    }

    private func makeFixture() -> Fixture {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 300, height: 200),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        window.contentView = content
        let items = (0..<3).map { ShelfItem(url: URL(fileURLWithPath: "/tmp/Drag Fixture \($0).txt")) }
        let source = RecordingFileDragSourceView(frame: NSRect(x: 20, y: 80, width: 260, height: 32))
        source.item = items[0]
        content.addSubview(source)
        for (index, y) in [CGFloat(40), CGFloat(140)].enumerated() {
            let row = FileDragSourceView(frame: NSRect(x: 20, y: y, width: 260, height: 32))
            row.item = items[index + 1]
            content.addSubview(row)
        }
        return Fixture(window: window, source: source, items: items)
    }

    private func beginReorder(in fixture: Fixture) throws {
        fixture.source.mouseDown(with: try event(.leftMouseDown, at: NSPoint(x: 60, y: 96), in: fixture.window))
        fixture.source.mouseDragged(with: try event(.leftMouseDragged, at: NSPoint(x: 60, y: 60), in: fixture.window))
    }

    private func fileURLs(in items: [NSDraggingItem]) -> [String] {
        items.compactMap {
            ($0.item as? ShelfDragPasteboardWriter)?.pasteboardPropertyList(forType: .fileURL) as? String
        }
    }

    private func event(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: type == .leftMouseUp ? 0 : 1
        ))
    }
}

private final class RecordingFileDragSourceView: FileDragSourceView {
    var sessions: [(items: [NSDraggingItem], event: NSEvent)] = []

    override func startNativeDragSession(with items: [NSDraggingItem], event: NSEvent) {
        sessions.append((items, event))
    }
}
