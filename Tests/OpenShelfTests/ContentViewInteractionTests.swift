import AppKit
import SwiftUI
import XCTest
@testable import OpenShelf

@MainActor
final class ContentViewInteractionTests: XCTestCase {
    func testKeyboardNavigationScrollsToOffscreenRows() throws {
        let fixture = try makeFixture(count: 20)
        defer { fixture.remove() }
        let store = ShelfStore()
        fixture.urls.forEach { _ = store.add(url: $0) }
        defer { store.clear() }
        let selection = ShelfSelectionModel()
        let hosted = host(store: store, dropState: ShelfDropState(), selection: selection)
        defer { hosted.window.orderOut(nil) }
        pumpRunLoop(for: 0.1)
        for _ in 0..<20 {
            selection.navigate(in: store.items, direction: 1, extending: false)
            pumpRunLoop(for: 0.01)
        }
        pumpRunLoop(for: 0.1)
        let row = try XCTUnwrap(hosted.hostingView.descendants(ofType: FileDragSourceView.self)
            .first { $0.item?.id == store.items.last?.id })
        let visible = row.visibleRect
        XCTAssertGreaterThan(visible.height, 0)
        XCTAssertEqual(selection.itemIDs, [try XCTUnwrap(store.items.last?.id)])
    }

    func testShelfBackgroundIsOpaqueAndAdaptsToLightAndDarkMode() throws {
        let lightComponents = try colorComponents(for: .aqua)
        let darkComponents = try colorComponents(for: .darkAqua)
        let lightBrightness = (
            lightComponents.red
                + lightComponents.green
                + lightComponents.blue
        ) / 3
        let darkBrightness = (
            darkComponents.red
                + darkComponents.green
                + darkComponents.blue
        ) / 3

        XCTAssertEqual(lightComponents.alpha, 1, accuracy: 0.001)
        XCTAssertEqual(darkComponents.alpha, 1, accuracy: 0.001)
        XCTAssertGreaterThan(lightBrightness, darkBrightness + 0.25)
        XCTAssertGreaterThanOrEqual(ShelfAppearance.selectedRowOpacity, 0.38)
        XCTAssertGreaterThan(
            ShelfAppearance.selectedHoveredRowOpacity,
            ShelfAppearance.selectedRowOpacity
        )
    }

    func testSuccessfulDropClearsSelectionButDuplicateDoesNot() throws {
        let fixture = try makeFixture(count: 2)
        defer { fixture.remove() }

        let store = ShelfStore()
        fixture.urls.forEach { XCTAssertTrue(store.add(url: $0)) }
        defer { store.clear() }

        let selection = ShelfSelectionModel(
            itemIDs: Set(store.items.map(\.id)),
            anchorItemID: store.items.last?.id
        )
        let dropState = ShelfDropState()
        let hosted = host(
            store: store,
            dropState: dropState,
            selection: selection
        )
        defer { hosted.window.orderOut(nil) }

        dropState.report(
            ShelfImportOutcome(addedCount: 0, skippedCount: 1)
        )
        pumpRunLoop(for: 0.05)

        XCTAssertEqual(selection.itemIDs, Set(store.items.map(\.id)))

        dropState.report(
            ShelfImportOutcome(addedCount: 1, skippedCount: 0)
        )
        pumpRunLoop(for: 0.05)

        XCTAssertTrue(selection.itemIDs.isEmpty)
        XCTAssertNil(selection.anchorItemID)
    }

    func testRemovingLastRowInvokesEmptyShelfCallback() throws {
        let fixture = try makeFixture(count: 1)
        defer { fixture.remove() }

        let store = ShelfStore()
        XCTAssertTrue(store.add(url: fixture.urls[0]))
        let becameEmpty = expectation(description: "empty shelf callback")
        let hosted = host(
            store: store,
            dropState: ShelfDropState(),
            onEmpty: {
                becameEmpty.fulfill()
            }
        )
        defer { hosted.window.orderOut(nil) }

        pumpRunLoop(for: 0.05)
        store.remove(store.items[0])

        wait(for: [becameEmpty], timeout: 1)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testSelectionOverlayLeavesEveryRowInteractiveWithOneOrTwoItems() throws {
        for itemCount in [1, 2] {
            let fixture = try makeFixture(count: itemCount)
            defer { fixture.remove() }

            let store = ShelfStore()
            fixture.urls.forEach { XCTAssertTrue(store.add(url: $0)) }
            defer { store.clear() }

            let hosted = host(
                store: store,
                dropState: ShelfDropState()
            )
            defer { hosted.window.orderOut(nil) }
            pumpRunLoop(for: 0.12)

            let rowViews = hosted.hostingView.descendants(
                ofType: FileDragSourceView.self
            )
            let selectionOverlay = try XCTUnwrap(
                hosted.hostingView.descendants(
                    ofType: ShelfSelectionOverlayView.self
                ).first
            )

            XCTAssertEqual(rowViews.count, itemCount)
            XCTAssertEqual(selectionOverlay.rowFrames.count, itemCount)

            for rowView in rowViews {
                let rowCenterInWindow = rowView.convert(
                    CGPoint(x: rowView.bounds.midX, y: rowView.bounds.midY),
                    to: nil
                )
                let pointInOverlay = selectionOverlay.convert(
                    rowCenterInWindow,
                    from: nil
                )

                XCTAssertNil(
                    selectionOverlay.hitTest(pointInOverlay),
                    "The marquee overlay intercepted a row in a \(itemCount)-item shelf."
                )
                XCTAssertTrue(rowView.acceptsFirstMouse(for: nil))
            }

            XCTAssertTrue(
                selectionOverlay.hitTest(
                    CGPoint(x: 3, y: selectionOverlay.bounds.midY)
                ) === selectionOverlay
            )
        }
    }

    func testFirstRowBeginsImmediatelyBelowHeaderWithoutOuterGap() throws {
        let fixture = try makeFixture(count: 1)
        defer { fixture.remove() }

        let store = ShelfStore()
        XCTAssertTrue(store.add(url: fixture.urls[0]))
        defer { store.clear() }

        let hosted = host(store: store, dropState: ShelfDropState())
        defer { hosted.window.orderOut(nil) }
        pumpRunLoop(for: 0.12)

        let rowView = try XCTUnwrap(
            hosted.hostingView.descendants(ofType: FileDragSourceView.self).first
        )
        let rowFrame = rowView.convert(rowView.bounds, to: hosted.hostingView)
        let distanceBelowHeader: CGFloat

        if hosted.hostingView.isFlipped {
            distanceBelowHeader = rowFrame.minY - 36
        } else {
            distanceBelowHeader = hosted.hostingView.bounds.maxY
                - 36
                - rowFrame.maxY
        }

        // Six points are the row's intentional internal vertical padding. Any
        // larger distance indicates that list/header spacing regressed.
        XCTAssertEqual(distanceBelowHeader, 6, accuracy: 1)
    }

    private func host(
        store: ShelfStore,
        dropState: ShelfDropState,
        selection: ShelfSelectionModel? = nil,
        onEmpty: @escaping () -> Void = {}
    ) -> (window: NSWindow, hostingView: NSHostingView<ContentView>) {
        _ = NSApplication.shared
        let contentView = ContentView(
            store: store,
            dropState: dropState,
            selection: selection,
            onHoverChanged: { _ in },
            onClose: {},
            onEmpty: onEmpty,
            onDragOutCompleted: {}
        )
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = CGRect(x: 0, y: 0, width: 300, height: 200)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.contentView?.layoutSubtreeIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        return (window, hostingView)
    }

    private func pumpRunLoop(for interval: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(interval))
    }

    private func makeFixture(count: Int) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenShelf ContentView \(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let urls = try (0..<count).map { index in
            let url = directory.appendingPathComponent("Item \(index).txt")
            try Data("item \(index)".utf8).write(to: url)
            return url
        }

        return Fixture(directory: directory, urls: urls)
    }

    private func colorComponents(
        for appearanceName: NSAppearance.Name
    ) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
        var result: (CGFloat, CGFloat, CGFloat, CGFloat)?

        appearance.performAsCurrentDrawingAppearance {
            guard let color = ShelfAppearance.backgroundColor
                .usingColorSpace(.deviceRGB)
            else {
                return
            }

            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            color.getRed(
                &red,
                green: &green,
                blue: &blue,
                alpha: &alpha
            )
            result = (red, green, blue, alpha)
        }

        let components = try XCTUnwrap(result)
        return (
            components.0,
            components.1,
            components.2,
            components.3
        )
    }
}

private struct Fixture {
    let directory: URL
    let urls: [URL]

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private extension NSView {
    func descendants<T: NSView>(ofType type: T.Type) -> [T] {
        var matches: [T] = []

        for subview in subviews {
            if let match = subview as? T {
                matches.append(match)
            }

            matches.append(contentsOf: subview.descendants(ofType: type))
        }

        return matches
    }
}
