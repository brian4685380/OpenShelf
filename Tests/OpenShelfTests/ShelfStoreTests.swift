import AppKit
import XCTest
@testable import OpenShelf

@MainActor
final class ShelfStoreTests: XCTestCase {
    func testItemsPreserveInsertionOrderInsteadOfSortingByName() throws {
        let urls = try makeFiles(named: ["Zulu.txt", "Alpha.txt", "Middle.txt"])
        defer { removeFilesAndParent(urls) }

        let store = ShelfStore()
        defer { store.clear() }

        for url in urls {
            XCTAssertTrue(store.add(url: url))
        }

        XCTAssertEqual(store.items.map(\.url), urls.map(\.standardizedFileURL))
    }

    func testSingleItemMovesDownAndBackUpInCursorDirection() throws {
        let urls = try makeFiles(named: ["A", "B", "C", "D", "E"])
        defer { removeFilesAndParent(urls) }

        let store = populatedStore(with: urls)
        defer { store.clear() }
        let originalItems = store.items

        store.move([originalItems[1]], to: originalItems[3])

        XCTAssertEqual(
            store.items.map(\.url),
            [urls[0], urls[2], urls[3], urls[1], urls[4]]
                .map(\.standardizedFileURL)
        )

        store.move([originalItems[1]], to: originalItems[0])

        XCTAssertEqual(
            store.items.map(\.url),
            [urls[1], urls[0], urls[2], urls[3], urls[4]]
                .map(\.standardizedFileURL)
        )
    }

    func testSelectedGroupMovesTogetherAndPreservesShelfOrder() throws {
        let urls = try makeFiles(named: ["A", "B", "C", "D", "E", "F"])
        defer { removeFilesAndParent(urls) }

        let store = populatedStore(with: urls)
        defer { store.clear() }
        let originalItems = store.items

        // Deliberately pass the moving rows in reverse order. The shelf's
        // visible order, rather than Set/caller order, must be preserved.
        store.move(
            [originalItems[2], originalItems[1]],
            to: originalItems[4]
        )

        XCTAssertEqual(
            store.items.map(\.url),
            [urls[0], urls[3], urls[4], urls[1], urls[2], urls[5]]
                .map(\.standardizedFileURL)
        )

        store.move(
            [originalItems[1], originalItems[2]],
            to: originalItems[0]
        )

        XCTAssertEqual(
            store.items.map(\.url),
            [urls[1], urls[2], urls[0], urls[3], urls[4], urls[5]]
                .map(\.standardizedFileURL)
        )
    }

    func testMoveIsIgnoredWhenTargetBelongsToMovingGroup() throws {
        let urls = try makeFiles(named: ["A", "B", "C"])
        defer { removeFilesAndParent(urls) }

        let store = populatedStore(with: urls)
        defer { store.clear() }
        let originalItems = store.items

        store.move(
            [originalItems[0], originalItems[1]],
            to: originalItems[1]
        )

        XCTAssertEqual(store.items, originalItems)
    }

    func testMissingFileIsRejected() {
        let store = ShelfStore()
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Missing \(UUID().uuidString)")

        XCTAssertFalse(store.add(url: missingURL))
        XCTAssertTrue(store.items.isEmpty)
    }

    func testDeletedOriginalIsRemovedAutomatically() throws {
        let urls = try makeFiles(named: ["Monitored.txt"])
        let sourceURL = try XCTUnwrap(urls.first)
        let parentDirectory = sourceURL.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: parentDirectory) }

        let store = ShelfStore()
        XCTAssertTrue(store.add(url: sourceURL))
        try FileManager.default.removeItem(at: sourceURL)

        let removed = expectation(description: "missing original removed")
        pollUntil(timeout: 2) {
            store.items.isEmpty
        } completion: { succeeded in
            XCTAssertTrue(succeeded)
            removed.fulfill()
        }
        wait(for: [removed], timeout: 3)
    }

    func testClearRemovesAllManagedContentAndItsEmptyDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenShelf Managed \(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let firstURL = directory.appendingPathComponent("First.txt")
        let secondURL = directory.appendingPathComponent("Second.txt")
        try Data("first".utf8).write(to: firstURL)
        try Data("second".utf8).write(to: secondURL)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ShelfStore()
        XCTAssertTrue(store.add(url: firstURL, isManagedByShelf: true))
        XCTAssertTrue(store.add(url: secondURL, isManagedByShelf: true))

        store.clear()

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testCopyPathUsesEverySelectedItemInShelfOrder() throws {
        let urls = try makeFiles(named: ["A", "B", "C"])
        defer { removeFilesAndParent(urls) }

        let store = populatedStore(with: urls)
        defer { store.clear() }

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        store.copyPath([store.items[0], store.items[2]], to: pasteboard)

        XCTAssertEqual(
            pasteboard.string(forType: .string),
            [urls[0].path, urls[2].path].joined(separator: "\n")
        )
    }

    func testDroppedFileIsAddedAndDuplicateIsReported() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenShelf Store \(UUID().uuidString).txt")
        try Data("file".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let pasteboard = makePasteboard()
        XCTAssertTrue(pasteboard.writeObjects([sourceURL as NSURL]))

        let store = ShelfStore()
        let firstOutcome = await importDrop(pasteboard, into: store)

        XCTAssertEqual(firstOutcome?.addedCount, 1)
        XCTAssertEqual(firstOutcome?.skippedCount, 0)
        XCTAssertEqual(store.items.map(\.url), [sourceURL.standardizedFileURL])

        let duplicateOutcome = await importDrop(pasteboard, into: store)

        XCTAssertEqual(duplicateOutcome?.addedCount, 0)
        XCTAssertEqual(duplicateOutcome?.skippedCount, 1)
        XCTAssertEqual(store.items.count, 1)
    }

    func testRemovingDroppedTextCleansUpManagedFile() async throws {
        let pasteboard = makePasteboard()
        XCTAssertTrue(pasteboard.setString("Temporary note", forType: .string))

        let store = ShelfStore()
        let outcome = await importDrop(pasteboard, into: store)
        let item = try XCTUnwrap(store.items.first)
        let managedURL = item.url
        let managedDirectory = managedURL.deletingLastPathComponent()

        XCTAssertEqual(outcome?.addedCount, 1)
        XCTAssertTrue(item.isManagedByShelf)
        XCTAssertTrue(FileManager.default.fileExists(atPath: managedURL.path))

        store.remove(item)

        XCTAssertFalse(FileManager.default.fileExists(atPath: managedURL.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: managedDirectory.path)
        )
    }

    private func importDrop(
        _ pasteboard: NSPasteboard,
        into store: ShelfStore
    ) async -> ShelfImportOutcome? {
        await withCheckedContinuation { continuation in
            let accepted = store.importDroppedPasteboard(pasteboard) {
                continuation.resume(returning: $0)
            }

            if !accepted {
                continuation.resume(returning: nil)
            }
        }
    }

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        return pasteboard
    }

    private func makeFiles(named names: [String]) throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenShelf Store \(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        return try names.map { name in
            let url = directory.appendingPathComponent(name)
            try Data(name.utf8).write(to: url)
            return url
        }
    }

    private func removeFilesAndParent(_ urls: [URL]) {
        guard let firstURL = urls.first else {
            return
        }

        try? FileManager.default.removeItem(
            at: firstURL.deletingLastPathComponent()
        )
    }

    private func populatedStore(with urls: [URL]) -> ShelfStore {
        let store = ShelfStore()

        for url in urls {
            XCTAssertTrue(store.add(url: url))
        }

        return store
    }

    private func pollUntil(
        timeout: TimeInterval,
        condition: @escaping () -> Bool,
        completion: @escaping (Bool) -> Void
    ) {
        let deadline = Date().addingTimeInterval(timeout)

        func poll() {
            if condition() {
                completion(true)
            } else if Date() >= deadline {
                completion(false)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    poll()
                }
            }
        }

        poll()
    }
}
