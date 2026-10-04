import AppKit
import SwiftUI
import XCTest
@testable import OpenShelf

@MainActor
final class FloatingShelfControllerTests: XCTestCase {
    func testShelfDropWindowCanBePreparedBeforeFinderDragStarts() throws {
        _ = NSApplication.shared
        let controller = FloatingShelfController()
        controller.preparePanel()
        defer { controller.closeShelf() }

        let panel = try XCTUnwrap(
            NSApp.windows.first { $0.title == "OpenShelf" }
        )
        let dropContainer = try XCTUnwrap(
            panel.contentView as? ShelfDropContainerView<ContentView>
        )

        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(
            dropContainer.hostingView.registeredDraggedTypes.contains(.fileURL)
        )
        XCTAssertTrue(
            dropContainer.registeredDraggedTypes.contains(.fileURL)
        )
        let shelfPanel = try XCTUnwrap(panel as? ShelfPanel)
        XCTAssertTrue(
            shelfPanel.registeredShelfDraggedTypes.contains(.fileURL)
        )
    }

    func testShelfPanelUsesFullscreenSafeWindowConfiguration() throws {
        _ = NSApplication.shared
        let controller = FloatingShelfController()
        controller.show()
        defer { controller.closeShelf() }

        let panel = try XCTUnwrap(openShelfPanel() as? ShelfPanel)
        let shelfPanel = panel

        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllApplications))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.collectionBehavior.contains(.stationary))
        XCTAssertFalse(panel.isKeyWindow)
        let dropContainer = try XCTUnwrap(
            panel.contentView as? ShelfDropContainerView<ContentView>
        )
        XCTAssertTrue(
            dropContainer.hostingView.registeredDraggedTypes.contains(.fileURL)
        )
        XCTAssertTrue(
            dropContainer.registeredDraggedTypes.contains(.fileURL)
        )
        XCTAssertTrue(
            shelfPanel.registeredShelfDraggedTypes.contains(.fileURL)
        )
        XCTAssertTrue(
            shelfPanel.registeredShelfDraggedTypes.contains(.string)
        )
        XCTAssertTrue(
            shelfPanel.registeredShelfDraggedTypes.contains(.png)
        )
        XCTAssertTrue(
            shelfPanel.delegate is ShelfPanelDropDestination
        )

        let capturePanel = try XCTUnwrap(
            NSApp.windows.first {
                $0.title == "OpenShelf Drop Capture" && $0.isVisible
            }
        )
        let captureView = try XCTUnwrap(
            capturePanel.contentView as? VisibleShelfDropCaptureView
        )
        XCTAssertEqual(capturePanel.frame, panel.frame)
        XCTAssertEqual(capturePanel.level, .floating)
        XCTAssertEqual(capturePanel.level, panel.level)
        XCTAssertTrue(capturePanel.collectionBehavior.contains(.canJoinAllApplications))
        XCTAssertTrue(capturePanel.collectionBehavior.contains(.stationary))
        XCTAssertTrue(captureView.registeredDraggedTypes.contains(.fileURL))
    }

    func testShelfUsesRequestedEdgeAndVerticalTriggerPosition() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
        let controller = FloatingShelfController(
            primaryMouseButtonPressed: { false }
        )
        defer { controller.closeShelf() }
        let desiredCenterY = screen.visibleFrame.midY + 35

        controller.show(
            on: screen,
            edge: .left,
            triggerY: desiredCenterY
        )
        let panel = try XCTUnwrap(openShelfPanel())

        XCTAssertEqual(
            panel.frame.minX,
            screen.visibleFrame.minX + 8,
            accuracy: 0.5
        )
        XCTAssertEqual(panel.frame.midY, desiredCenterY, accuracy: 0.5)

        controller.show(
            on: screen,
            edge: .right,
            triggerY: desiredCenterY
        )

        XCTAssertEqual(
            panel.frame.maxX,
            screen.visibleFrame.maxX - 8,
            accuracy: 0.5
        )
        XCTAssertEqual(panel.frame.midY, desiredCenterY, accuracy: 0.5)
    }

    func testIdleShelfCollapsesToTabAndExpandsAgain() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
        let controller = FloatingShelfController(
            primaryMouseButtonPressed: { false }
        )
        let testEdge: ShelfEdge =
            NSEvent.mouseLocation.x >= screen.frame.midX ? .left : .right
        controller.show(on: screen, edge: testEdge)
        defer { controller.closeShelf() }
        let panel = try XCTUnwrap(openShelfPanel())
        let dropContainer = try XCTUnwrap(
            panel.contentView as? ShelfDropContainerView<ContentView>
        )

        // Keep this controller-timing test independent of the real cursor's
        // position while XCTest is driving an on-screen AppKit window.
        panel.ignoresMouseEvents = true
        dropContainer.rootView.onHoverChanged(false)

        controller.collapse()
        waitForAnimation()

        switch testEdge {
        case .left:
            XCTAssertEqual(
                panel.frame.maxX,
                screen.visibleFrame.minX + 32,
                accuracy: 1
            )
        case .right:
            XCTAssertEqual(
                panel.frame.minX,
                screen.visibleFrame.maxX - 32,
                accuracy: 1
            )
        }

        controller.expand()
        waitForAnimation()

        switch testEdge {
        case .left:
            XCTAssertEqual(
                panel.frame.minX,
                screen.visibleFrame.minX + 8,
                accuracy: 1
            )
        case .right:
            XCTAssertEqual(
                panel.frame.maxX,
                screen.visibleFrame.maxX - 8,
                accuracy: 1
            )
        }
    }

    func testAlwaysOnTopRefreshRestoresPanelAndCaptureConfiguration() throws {
        _ = NSApplication.shared
        let controller = FloatingShelfController(
            primaryMouseButtonPressed: { false }
        )
        controller.show()
        defer { controller.closeShelf() }

        let panel = try XCTUnwrap(openShelfPanel() as? ShelfPanel)
        let capturePanel = try XCTUnwrap(
            NSApp.windows.first {
                $0.title == "OpenShelf Drop Capture" && $0.isVisible
            }
        )
        panel.level = .normal
        capturePanel.level = .normal

        controller.refreshAlwaysOnTop()

        XCTAssertEqual(panel.level, .floating)
        XCTAssertEqual(capturePanel.level, .floating)
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(capturePanel.isVisible)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    func testAlwaysOnTopRefreshDoesNotRetargetAnActiveFinderDrag() throws {
        _ = NSApplication.shared
        var mouseButtonPressed = true
        let controller = FloatingShelfController(
            primaryMouseButtonPressed: { mouseButtonPressed }
        )
        controller.show()
        defer { controller.closeShelf() }

        let panel = try XCTUnwrap(openShelfPanel() as? ShelfPanel)
        let capturePanel = try XCTUnwrap(
            NSApp.windows.first {
                $0.title == "OpenShelf Drop Capture" && $0.isVisible
            }
        )
        panel.level = .normal
        capturePanel.level = .normal

        controller.refreshAlwaysOnTop()

        XCTAssertEqual(panel.level, .normal)
        XCTAssertEqual(capturePanel.level, .normal)

        mouseButtonPressed = false
        controller.refreshAlwaysOnTop()

        XCTAssertEqual(panel.level, .floating)
        XCTAssertEqual(capturePanel.level, .floating)
    }

    func testEdgeTriggersUseInteractiveAllSpacesConfiguration() throws {
        _ = NSApplication.shared
        let shelfController = FloatingShelfController()
        let triggerController = EdgeTriggerController(
            shelfController: shelfController
        )
        triggerController.start()
        defer { triggerController.stop() }

        let triggerPanels = visibleEdgeTriggerPanels()

        XCTAssertEqual(triggerPanels.count, NSScreen.screens.count * 2)

        for panel in triggerPanels {
            XCTAssertEqual(panel.level, .floating)
            XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
            XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllApplications))
            XCTAssertTrue(panel.collectionBehavior.contains(.stationary))
        }
    }

    func testEdgeTriggerRefreshRestoresGlobalLevelAfterWindowSwitch() {
        _ = NSApplication.shared
        let shelfController = FloatingShelfController()
        var canReorderWindows = true
        let triggerController = EdgeTriggerController(
            shelfController: shelfController,
            canReorderWindows: { canReorderWindows }
        )
        triggerController.start()
        defer { triggerController.stop() }

        let triggerPanels = visibleEdgeTriggerPanels()
        XCTAssertFalse(triggerPanels.isEmpty)

        for panel in triggerPanels {
            panel.level = .normal
        }

        canReorderWindows = false
        triggerController.refresh()

        for panel in triggerPanels {
            XCTAssertEqual(panel.level, .normal)
        }

        canReorderWindows = true
        triggerController.refresh()

        for panel in triggerPanels {
            XCTAssertEqual(panel.level, .floating)
            XCTAssertTrue(panel.isVisible)
            XCTAssertTrue(panel.collectionBehavior.contains(.stationary))
        }
    }

    func testSpaceRefreshDeferredDuringDragRetriesAfterRelease() throws {
        _ = NSApplication.shared
        var mouseDown = true
        let controller = FloatingShelfController(primaryMouseButtonPressed: { mouseDown })
        controller.show()
        defer { controller.closeShelf() }
        let panel = try XCTUnwrap(openShelfPanel())
        panel.level = .normal

        controller.refreshAlwaysOnTop()
        controller.maintainAlwaysOnTop()
        XCTAssertEqual(panel.level, .normal, "Never reorder Finder's active destination")

        mouseDown = false
        controller.maintainAlwaysOnTop()
        XCTAssertEqual(panel.level, .floating, "Retry even without another workspace notification")

        panel.level = .normal
        controller.maintainAlwaysOnTop()
        XCTAssertEqual(panel.level, .normal, "Do not continually reorder after the retry succeeds")
    }

    func testInterruptedDragDoesNotPermanentlyBlockSpaceRefresh() throws {
        _ = NSApplication.shared
        var mouseDown = true
        let controller = FloatingShelfController(primaryMouseButtonPressed: { mouseDown })
        controller.show()
        defer { controller.closeShelf() }
        let panel = try XCTUnwrap(openShelfPanel())
        let container = try XCTUnwrap(panel.contentView as? ShelfDropContainerView<ContentView>)
        controller.beginVisibleShelfDrag()
        panel.level = .normal
        controller.refreshAlwaysOnTop()
        controller.maintainAlwaysOnTop()
        XCTAssertTrue(container.rootView.dropState.isTargeted)
        XCTAssertEqual(panel.level, .normal)

        // WindowServer changed Spaces without delivering draggingEnded.
        mouseDown = false
        controller.maintainAlwaysOnTop()
        XCTAssertFalse(container.rootView.dropState.isTargeted)
        XCTAssertEqual(panel.level, .floating)
    }

    func testSpaceMaintenanceRestoresPresentedWindowButNeverReopensClosedShelf() throws {
        _ = NSApplication.shared
        let controller = FloatingShelfController(primaryMouseButtonPressed: { false })
        controller.show()
        defer { controller.closeShelf() }
        let panel = try XCTUnwrap(openShelfPanel())
        panel.orderOut(nil)

        controller.maintainAlwaysOnTop()
        XCTAssertTrue(panel.isVisible)

        controller.closeShelf()
        controller.maintainAlwaysOnTop()
        controller.refreshAlwaysOnTop()
        XCTAssertFalse(panel.isVisible)
    }

    func testScreenChangeReanchorsShelfAndDropCaptureAfterDragEnds() throws {
        _ = NSApplication.shared
        var mouseDown = true
        let controller = FloatingShelfController(primaryMouseButtonPressed: { mouseDown })
        let screen = try XCTUnwrap(NSScreen.screens.first)
        controller.show(on: screen, edge: .left)
        defer { controller.closeShelf() }
        let panel = try XCTUnwrap(openShelfPanel())
        let capture = try XCTUnwrap(NSApp.windows.first {
            $0.title == "OpenShelf Drop Capture" && $0.isVisible
        })
        let unreachable = NSPoint(x: screen.frame.maxX + 10_000, y: 10_000)
        panel.setFrameOrigin(unreachable)
        controller.screenParametersDidChange()
        XCTAssertEqual(panel.frame.origin, unreachable)

        mouseDown = false
        controller.maintainAlwaysOnTop()
        XCTAssertEqual(panel.frame.minX, screen.visibleFrame.minX + 8, accuracy: 0.5)
        XCTAssertTrue(screen.visibleFrame.contains(panel.frame))
        XCTAssertEqual(capture.frame, panel.frame)
    }

    func testScreenChangePreservesCollapsedTabAndItsHiddenDropCapture() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let edge: ShelfEdge = NSEvent.mouseLocation.x >= screen.frame.midX ? .left : .right
        let controller = FloatingShelfController(primaryMouseButtonPressed: { false })
        controller.show(on: screen, edge: edge)
        defer { controller.closeShelf() }
        let panel = try XCTUnwrap(openShelfPanel())
        let capture = try XCTUnwrap(NSApp.windows.first {
            $0.title == "OpenShelf Drop Capture" && $0.isVisible
        })
        let container = try XCTUnwrap(panel.contentView as? ShelfDropContainerView<ContentView>)
        panel.ignoresMouseEvents = true
        container.rootView.onHoverChanged(false)
        controller.collapse()
        waitForAnimation()
        controller.screenParametersDidChange()

        XCTAssertEqual(panel.frame.intersection(screen.visibleFrame).width, 32, accuracy: 1)
        XCTAssertFalse(capture.isVisible)
    }

    func testScreenChangesDoNotReplaceEdgeDragDestinationUntilRelease() throws {
        _ = NSApplication.shared
        let controller = FloatingShelfController()
        var canReorder = true
        let edges = EdgeTriggerController(shelfController: controller, canReorderWindows: { canReorder })
        edges.start()
        defer { edges.stop() }
        let original = visibleEdgeTriggerPanels()
        canReorder = false
        edges.screenParametersDidChange()
        edges.refresh()
        XCTAssertTrue(original.allSatisfy(\.isVisible))
        XCTAssertEqual(Set(visibleEdgeTriggerPanels().map(\.windowNumber)), Set(original.map(\.windowNumber)))

        canReorder = true
        edges.refresh()
        XCTAssertTrue(original.allSatisfy { !$0.isVisible })
        XCTAssertEqual(visibleEdgeTriggerPanels().count, NSScreen.screens.count * 2)
    }

    func testHoverMakesShelfKeyForCommandVPaste() throws {
        _ = NSApplication.shared
        var panelAskedToBecomeKey: NSPanel?
        let focusSettled = expectation(description: "hovered shelf becomes key")
        let controller = FloatingShelfController(
            makePanelKey: { panel in
                panelAskedToBecomeKey = panel
                focusSettled.fulfill()
            },
            primaryMouseButtonPressed: { false }
        )
        controller.show()
        defer { controller.closeShelf() }

        let panel = try XCTUnwrap(openShelfPanel() as? ShelfPanel)
        let dropContainer = try XCTUnwrap(
            panel.contentView as? ShelfDropContainerView<ContentView>
        )
        XCTAssertFalse(panel.becomesKeyOnlyIfNeeded)
        XCTAssertTrue(panel.canBecomeKey)
        panel.ignoresMouseEvents = true

        dropContainer.rootView.onHoverChanged(true)

        // Wait for the actual callback, not a timer that can overtake the
        // nested MainActor task on a loaded/virtualized CI runner.
        wait(for: [focusSettled], timeout: 3)

        XCTAssertTrue(panelAskedToBecomeKey === panel)
    }

    func testEdgeTriggerRegistersFilesImagesTextAndPromises() throws {
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
        let trigger = EdgeTriggerView(
            shelfController: nil,
            screen: screen,
            edge: .right
        )
        let types = Set(trigger.registeredDraggedTypes)

        XCTAssertTrue(types.contains(.fileURL))
        XCTAssertTrue(types.contains(.png))
        XCTAssertTrue(types.contains(.string))

        for type in NSFilePromiseReceiver.readableDraggedTypes {
            XCTAssertTrue(types.contains(NSPasteboard.PasteboardType(type)))
        }
    }

    func testActiveEdgeDestinationExpandsAcrossVisibleShelf() throws {
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
        let originalFrame = NSRect(
            x: screen.frame.maxX - 12,
            y: screen.frame.minY,
            width: 12,
            height: screen.frame.height
        )
        let shelfFrame = NSRect(
            x: screen.visibleFrame.maxX - 308,
            y: screen.visibleFrame.midY - 100,
            width: 300,
            height: 200
        )
        let trigger = EdgeTriggerView(
            shelfController: nil,
            screen: screen,
            edge: .right
        )
        let panel = NSPanel(
            contentRect: originalFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = trigger
        defer { panel.orderOut(nil) }

        trigger.beginShelfDropCapture(over: shelfFrame)

        XCTAssertTrue(
            panel.frame.contains(
                NSPoint(x: shelfFrame.midX, y: shelfFrame.midY)
            )
        )
        XCTAssertTrue(
            panel.frame.contains(
                NSPoint(
                    x: screen.frame.maxX - 1,
                    y: shelfFrame.midY
                )
            )
        )
        XCTAssertEqual(panel.frame.minX, shelfFrame.minX, accuracy: 0.5)
        XCTAssertEqual(panel.frame.height, shelfFrame.height, accuracy: 0.5)

        trigger.endShelfDropCapture()

        XCTAssertEqual(panel.frame, originalFrame)
    }

    func testVisibleShelfRetainsDropRegionDuringHideDelay() throws {
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
        let originalFrame = NSRect(
            x: screen.frame.maxX - 12,
            y: screen.frame.minY,
            width: 12,
            height: screen.frame.height
        )
        let shelfFrame = NSRect(
            x: screen.visibleFrame.maxX - 308,
            y: screen.visibleFrame.midY - 100,
            width: 300,
            height: 200
        )
        let trigger = EdgeTriggerView(
            shelfController: nil,
            screen: screen,
            edge: .right
        )
        let panel = NSPanel(
            contentRect: originalFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = trigger
        defer { panel.orderOut(nil) }

        trigger.beginShelfDropCapture(over: shelfFrame)
        XCTAssertTrue(
            panel.frame.contains(
                NSPoint(x: shelfFrame.midX, y: shelfFrame.midY)
            )
        )

        trigger.scheduleShelfDropCaptureEnd(after: 0.02)
        trigger.cancelScheduledShelfDropCaptureEnd()

        let cancellationSettled = expectation(
            description: "returning to visible shelf cancels capture end"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            cancellationSettled.fulfill()
        }
        wait(for: [cancellationSettled], timeout: 1)

        XCTAssertTrue(
            panel.frame.contains(
                NSPoint(x: shelfFrame.midX, y: shelfFrame.midY)
            )
        )

        trigger.scheduleShelfDropCaptureEnd(after: 0.01)

        let hideSettled = expectation(
            description: "capture returns to edge after shelf hides"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            hideSettled.fulfill()
        }
        wait(for: [hideSettled], timeout: 1)

        XCTAssertEqual(panel.frame, originalFrame)
    }

    func testReleasingFileOnScreenEdgeAddsItToShelf() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
        let controller = FloatingShelfController()
        let trigger = EdgeTriggerView(
            shelfController: controller,
            screen: screen,
            edge: .right
        )
        defer {
            controller.clearShelf()
            controller.closeShelf()
        }

        let sourceFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "OpenShelf Edge Drop \(UUID().uuidString).txt"
            )
        try Data("edge drop".utf8).write(to: sourceFile)
        defer { try? FileManager.default.removeItem(at: sourceFile) }

        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([sourceFile as NSURL]))

        XCTAssertTrue(
            trigger.performDrop(from: pasteboard, triggerY: nil)
        )

        let panel = try XCTUnwrap(openShelfPanel() as? ShelfPanel)
        let dropContainer = try XCTUnwrap(
            panel.contentView as? ShelfDropContainerView<ContentView>
        )

        XCTAssertTrue(
            dropContainer.rootView.store.items.contains(where: {
                $0.url == sourceFile.standardizedFileURL
            })
        )
        XCTAssertEqual(
            dropContainer.rootView.dropState.successfulDropGeneration,
            1
        )
    }

    func testReleasingFileInMiddleOfShelfAddsItToShelf() throws {
        _ = NSApplication.shared
        let controller = FloatingShelfController()
        controller.show()
        defer {
            controller.clearShelf()
            controller.closeShelf()
        }

        let panel = try XCTUnwrap(openShelfPanel() as? ShelfPanel)
        let dropContainer = try XCTUnwrap(
            panel.contentView as? ShelfDropContainerView<ContentView>
        )

        let sourceFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "OpenShelf Finder \(UUID().uuidString).txt"
            )
        try Data("finder".utf8).write(to: sourceFile)
        defer { try? FileManager.default.removeItem(at: sourceFile) }

        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([sourceFile as NSURL]))

        XCTAssertEqual(
            panel.updateDropTarget(for: pasteboard),
            .copy
        )
        XCTAssertTrue(dropContainer.rootView.dropState.isTargeted)
        XCTAssertTrue(panel.performDrop(from: pasteboard))
        XCTAssertFalse(dropContainer.rootView.dropState.isTargeted)
        XCTAssertTrue(
            dropContainer.rootView.store.items.contains(where: {
                $0.url == sourceFile.standardizedFileURL
            })
        )
        XCTAssertEqual(
            dropContainer.rootView.dropState.successfulDropGeneration,
            1
        )
    }

    func testVisibleShelfAcceptsFinderFileWithoutEdgeTrigger() throws {
        _ = NSApplication.shared
        let controller = FloatingShelfController()
        controller.show()
        defer {
            controller.clearShelf()
            controller.closeShelf()
        }

        let panel = try XCTUnwrap(openShelfPanel() as? ShelfPanel)
        let dropContainer = try XCTUnwrap(
            panel.contentView as? ShelfDropContainerView<ContentView>
        )
        let sourceFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "OpenShelf Visible Direct \(UUID().uuidString).txt"
            )
        try Data("visible direct".utf8).write(to: sourceFile)
        defer { try? FileManager.default.removeItem(at: sourceFile) }

        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([sourceFile as NSURL]))

        XCTAssertEqual(
            dropContainer.updateDropTarget(for: pasteboard),
            .copy
        )
        XCTAssertTrue(dropContainer.rootView.dropState.isTargeted)
        XCTAssertTrue(dropContainer.performDrop(from: pasteboard))
        XCTAssertFalse(dropContainer.rootView.dropState.isTargeted)
        XCTAssertTrue(
            dropContainer.rootView.store.items.contains(where: {
                $0.url == sourceFile.standardizedFileURL
            })
        )
        XCTAssertEqual(
            dropContainer.rootView.dropState.successfulDropGeneration,
            1
        )
    }

    func testSecondFileCanDropDirectlyOnShelfAfterFirstEdgeDrop() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
        let controller = FloatingShelfController()
        let trigger = EdgeTriggerView(
            shelfController: controller,
            screen: screen,
            edge: .right
        )
        defer {
            controller.clearShelf()
            controller.closeShelf()
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
        let firstFile = temporaryDirectory.appendingPathComponent(
            "OpenShelf First Edge Drop \(UUID().uuidString).txt"
        )
        let secondFile = temporaryDirectory.appendingPathComponent(
            "OpenShelf Second Panel Drop \(UUID().uuidString).txt"
        )
        try Data("first".utf8).write(to: firstFile)
        try Data("second".utf8).write(to: secondFile)
        defer {
            try? FileManager.default.removeItem(at: firstFile)
            try? FileManager.default.removeItem(at: secondFile)
        }

        let firstPasteboard = NSPasteboard.withUniqueName()
        firstPasteboard.clearContents()
        XCTAssertTrue(firstPasteboard.writeObjects([firstFile as NSURL]))
        XCTAssertTrue(
            trigger.performDrop(from: firstPasteboard, triggerY: nil)
        )

        let panel = try XCTUnwrap(openShelfPanel() as? ShelfPanel)
        let dropContainer = try XCTUnwrap(
            panel.contentView as? ShelfDropContainerView<ContentView>
        )
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(
            dropContainer.rootView.store.items.contains(where: {
                $0.url == firstFile.standardizedFileURL
            })
        )

        let secondPasteboard = NSPasteboard.withUniqueName()
        secondPasteboard.clearContents()
        XCTAssertTrue(secondPasteboard.writeObjects([secondFile as NSURL]))

        XCTAssertEqual(panel.updateDropTarget(for: secondPasteboard), .copy)
        XCTAssertTrue(dropContainer.rootView.dropState.isTargeted)
        XCTAssertTrue(panel.performDrop(from: secondPasteboard))
        XCTAssertFalse(dropContainer.rootView.dropState.isTargeted)
        XCTAssertTrue(
            dropContainer.rootView.store.items.contains(where: {
                $0.url == secondFile.standardizedFileURL
            })
        )
        XCTAssertEqual(
            dropContainer.rootView.dropState.successfulDropGeneration,
            2
        )
    }

    func testFileRowsReserveDropRegistrationForInternalReordering() {
        let row = FileDragSourceView(frame: .zero)
        let types = Set(row.registeredDraggedTypes)
        let reorderType = NSPasteboard.PasteboardType(
            shelfReorderPasteboardTypeIdentifier
        )

        XCTAssertTrue(types.contains(reorderType))
        XCTAssertFalse(types.contains(.fileURL))
        XCTAssertFalse(types.contains(.string))
    }

    func testMarqueeSelectionAreaDoesNotInterceptExternalDrops() {
        let selectionArea = ShelfSelectionOverlayView(frame: .zero)

        XCTAssertFalse(
            selectionArea.registeredDraggedTypes.contains(.fileURL)
        )
    }

    private func openShelfPanel() -> NSWindow? {
        NSApp.windows.first { window in
            window.title == "OpenShelf" && window.isVisible
        }
    }

    private func visibleEdgeTriggerPanels() -> [NSPanel] {
        NSApp.windows.compactMap { window -> NSPanel? in
            guard window.isVisible,
                window.contentView is EdgeTriggerView
            else {
                return nil
            }

            return window as? NSPanel
        }
    }

    private func waitForAnimation() {
        let animationSettled = expectation(description: "animation settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            animationSettled.fulfill()
        }
        wait(for: [animationSettled], timeout: 1)
    }

}
