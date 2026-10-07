import AppKit
import XCTest
import ShelfCore
@testable import OpenShelf

@MainActor
final class ShelfWorkflowTests: XCTestCase {
    func testExportedTemporaryContentSurvivesRemovalUntilSessionCleanup() throws {
        for usingCopy in [true, false] {
            let urls = try files()
            defer { try? FileManager.default.removeItem(at: urls[0].deletingLastPathComponent()) }
            let store = ShelfStore()
            store.add(url: urls[0], isManagedByShelf: true)
            store.add(url: urls[1])
            let pasteboard = NSPasteboard.withUniqueName()
            defer { pasteboard.releaseGlobally() }
            if usingCopy {
                XCTAssertTrue(store.copy(store.items, to: pasteboard))
            } else {
                store.finishExport(store.items)
            }
            store.clear()
            XCTAssertTrue(FileManager.default.fileExists(atPath: urls[0].path), "A destination may still need to read the exported file URL.")
            store.cleanUpSession()
            XCTAssertFalse(FileManager.default.fileExists(atPath: urls[0].path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: urls[1].path), "Original files are never deleted by session cleanup.")
        }
    }

    func testKeyboardSelectionExtendsAndShrinksAroundFixedAnchor() {
        let items = (0..<5).map { ShelfItem(url: URL(fileURLWithPath: "/tmp/\($0)")) }
        let selection = ShelfSelectionModel()
        selection.navigate(in: items, direction: 1, extending: false)
        XCTAssertEqual(selection.itemIDs, [items[0].id])
        selection.navigate(in: items, direction: 1, extending: true)
        selection.navigate(in: items, direction: 1, extending: true)
        XCTAssertEqual(selection.itemIDs, Set(items.prefix(3).map(\.id)))
        selection.navigate(in: items, direction: -1, extending: true)
        XCTAssertEqual(selection.itemIDs, Set(items.prefix(2).map(\.id)))
        selection.navigate(in: items, direction: -1, extending: true)
        selection.navigate(in: items, direction: -1, extending: true)
        XCTAssertEqual(selection.itemIDs, [items[0].id])
        selection.clear()
        selection.navigate(in: items, direction: -1, extending: false)
        XCTAssertEqual(selection.itemIDs, [items[4].id])
        selection.selectAll(in: items)
        XCTAssertEqual(selection.itemIDs.count, 5)
        selection.prune(to: [])
        XCTAssertNil(selection.focusedItemID)
        XCTAssertTrue(selection.itemIDs.isEmpty)
    }

    func testMouseSelectionDoesNotRequestKeyboardScrolling() {
        let item = ShelfItem(url: URL(fileURLWithPath: "/tmp/a"))
        let selection = ShelfSelectionModel()
        selection.handleClick(on: item, in: [item], modifiers: [])
        selection.replace(with: [item.id], anchorItemID: item.id)
        XCTAssertEqual(selection.keyboardNavigationGeneration, 0)
    }

    func testKeyboardParserRecognizesCommandsWithoutHijackingOtherModifiers() throws {
        func command(_ characters: String, code: UInt16 = 0, modifiers: NSEvent.ModifierFlags = []) throws -> ShelfKeyboardCommand? {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
            return ShelfKeyboardCommand(event: event)
        }
        XCTAssertEqual(try command("a", modifiers: [.command, .capsLock]), .selectAll)
        XCTAssertEqual(try command("c", modifiers: .command), .copy)
        XCTAssertEqual(try command("c", modifiers: [.command, .option]), .copyPaths)
        XCTAssertEqual(try command("v", modifiers: .command), .paste)
        XCTAssertEqual(try command("p", modifiers: .command), .togglePin)
        XCTAssertEqual(try command("n", modifiers: .command), .newShelf)
        XCTAssertEqual(try command("", code: 125, modifiers: [.shift, .function, .numericPad]), .navigate(direction: 1, extending: true))
        XCTAssertEqual(try command(" ", code: 49), .preview)
        XCTAssertEqual(try command("", code: 51), .remove)
        XCTAssertNil(try command("a"))
        XCTAssertNil(try command("a", modifiers: [.command, .shift]))
        XCTAssertNil(try command("", code: 51, modifiers: .shift))
    }

    func testPinnedShelfStaysExpandedAndCanStillBeExplicitlyClosed() throws {
        _ = NSApplication.shared
        let controller = FloatingShelfController(primaryMouseButtonPressed: { false })
        controller.show(edge: .left)
        defer { controller.closeShelf() }
        let panel = try XCTUnwrap(NSApp.windows.first { $0.title == "OpenShelf" && $0.isVisible })
        let view = try XCTUnwrap(panel.contentView as? ShelfDropContainerView<ContentView>)
        panel.ignoresMouseEvents = true
        view.rootView.onHoverChanged(false)
        let expandedFrame = panel.frame
        controller.togglePin()
        XCTAssertTrue(view.rootView.presentation.isPinned)
        controller.collapse()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        XCTAssertEqual(panel.frame, expandedFrame)
        view.rootView.onEmpty()
        XCTAssertTrue(panel.isVisible)
        controller.toggleShelf()
        XCTAssertFalse(panel.isVisible)
    }

    func testNativePanelRoutesSelectionAndDeleteWithoutDeletingOriginals() throws {
        _ = NSApplication.shared
        let urls = try files()
        defer { try? FileManager.default.removeItem(at: urls[0].deletingLastPathComponent()) }
        let controller = FloatingShelfController(primaryMouseButtonPressed: { false })
        controller.addAndShow(urls: urls)
        defer { controller.closeShelf() }
        let panel = try XCTUnwrap(NSApp.windows.first { $0.title == "OpenShelf" && $0.isVisible } as? ShelfPanel)
        let container = try XCTUnwrap(panel.contentView as? ShelfDropContainerView<ContentView>)
        for (key, code, modifiers) in [("a", UInt16(0), NSEvent.ModifierFlags.command), ("", UInt16(51), NSEvent.ModifierFlags())] {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: modifiers, timestamp: 0, windowNumber: panel.windowNumber,
                context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: code))
            XCTAssertTrue(panel.performKeyEquivalent(with: event))
        }
        XCTAssertTrue(container.rootView.store.items.isEmpty)
        XCTAssertTrue(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    func testCopyPublishesEveryFileURLAndDoesNotRemoveItems() throws {
        let urls = try files()
        defer { try? FileManager.default.removeItem(at: urls[0].deletingLastPathComponent()) }
        let store = ShelfStore()
        defer { store.clear() }
        urls.forEach { _ = store.add(url: $0) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(store.copy(store.items, to: pasteboard))
        let copied = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        XCTAssertEqual(copied, urls.map(\.standardizedFileURL))
        XCTAssertEqual(store.items.count, 2)
        XCTAssertFalse(store.copy([], to: pasteboard))
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 2)
    }

    func testCLIArgumentsSupportHelpVersionSpacesAndLiteralDashNames() throws {
        XCTAssertEqual(try ShelfCLIArguments(["--help"]), .help)
        XCTAssertEqual(try ShelfCLIArguments(["-v"]), .version)
        XCTAssertEqual(try ShelfCLIArguments(["space name", "folder/a"]), .files(["space name", "folder/a"]))
        XCTAssertEqual(try ShelfCLIArguments(["--", "-file", "--help"]), .files(["-file", "--help"]))
        XCTAssertThrowsError(try ShelfCLIArguments([]))
        XCTAssertThrowsError(try ShelfCLIArguments(["--"]))
        XCTAssertThrowsError(try ShelfCLIArguments(["--unknown"]))
    }

    private func files() throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try ["First.txt", "Second.txt"].map {
            let url = directory.appendingPathComponent($0)
            try Data($0.utf8).write(to: url)
            return url
        }
    }
}
