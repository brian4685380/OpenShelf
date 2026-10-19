import AppKit
import XCTest
@testable import OpenShelf

@MainActor
final class ShelfWindowPolicyTests: XCTestCase {
    func testStrandedPanelRejoinsSpaceBeforeRestoringAllSpacesRole() {
        let panel = makePanel()
        defer { panel.close() }
        panel.simulatedActiveSpace = false
        let frame = panel.frame

        ShelfWindowPolicy.orderOnActiveSpace(panel)

        XCTAssertEqual(panel.orderOutCount, 1)
        XCTAssertEqual(panel.frontCount, 1)
        XCTAssertTrue(panel.behaviorWhenOrdered.contains(.moveToActiveSpace))
        XCTAssertFalse(panel.behaviorWhenOrdered.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.behaviorWhenOrdered.contains(.canJoinAllApplications))
        XCTAssertTrue(panel.behaviorWhenOrdered.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.isOnActiveSpace)
        XCTAssertEqual(panel.collectionBehavior, ShelfWindowPolicy.collectionBehavior)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertEqual(panel.frame, frame)
        XCTAssertFalse(panel.isKeyWindow)
    }

    func testHealthyPanelDoesNotDetachFromItsSpaces() {
        let panel = makePanel()
        defer { panel.close() }

        ShelfWindowPolicy.orderOnActiveSpace(panel)
        ShelfWindowPolicy.orderOnActiveSpace(panel)

        XCTAssertEqual(panel.orderOutCount, 0)
        XCTAssertFalse(panel.behaviorWhenOrdered.contains(.moveToActiveSpace))
        XCTAssertEqual(panel.behaviorWhenOrdered, ShelfWindowPolicy.collectionBehavior)
    }

    func testCaptureRejoinsBelowItsShelfWithoutTakingFocus() {
        let shelf = makePanel()
        let capture = makePanel()
        defer { capture.close(); shelf.close() }
        shelf.orderFrontRegardless()
        capture.simulatedActiveSpace = false

        ShelfWindowPolicy.orderOnActiveSpace(capture, below: shelf)

        XCTAssertEqual(capture.orderOutCount, 1)
        XCTAssertEqual(capture.frontCount, 0)
        XCTAssertEqual(capture.relativeWindow, shelf.windowNumber)
        XCTAssertEqual(capture.orderingMode, .below)
        XCTAssertTrue(capture.behaviorWhenOrdered.contains(.moveToActiveSpace))
        XCTAssertEqual(capture.collectionBehavior, ShelfWindowPolicy.collectionBehavior)
        XCTAssertTrue(capture.isOnActiveSpace)
        XCTAssertFalse(capture.isKeyWindow)
    }

    private func makePanel() -> SpaceTrackingPanel {
        _ = NSApplication.shared
        let panel = SpaceTrackingPanel(contentRect: NSRect(x: 50, y: 50, width: 100, height: 80),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        ShelfWindowPolicy.apply(to: panel)
        return panel
    }
}

/// Model a WindowServer association that survived a Space transition. These
/// tests verify the recovery protocol; live Desktop/fullscreen checks are
/// still needed to validate the OS's actual Space assignment.
@MainActor
private final class SpaceTrackingPanel: NSPanel {
    var simulatedActiveSpace = true
    var orderOutCount = 0
    var frontCount = 0
    var behaviorWhenOrdered: NSWindow.CollectionBehavior = []
    var relativeWindow: Int?
    var orderingMode: NSWindow.OrderingMode?
    override var isOnActiveSpace: Bool { simulatedActiveSpace }

    override func orderOut(_ sender: Any?) {
        orderOutCount += 1
        super.orderOut(sender)
    }

    override func orderFrontRegardless() {
        frontCount += 1
        recordSpaceAssignment()
        super.orderFrontRegardless()
    }

    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        orderingMode = place
        relativeWindow = otherWin
        recordSpaceAssignment()
        super.order(place, relativeTo: otherWin)
    }

    private func recordSpaceAssignment() {
        behaviorWhenOrdered = collectionBehavior
        if collectionBehavior.contains(.moveToActiveSpace) { simulatedActiveSpace = true }
    }
}
