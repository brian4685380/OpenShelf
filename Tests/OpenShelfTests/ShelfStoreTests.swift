import AppKit
import XCTest
@testable import OpenShelf

@MainActor
final class ShelfStoreTests: XCTestCase {
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
}
