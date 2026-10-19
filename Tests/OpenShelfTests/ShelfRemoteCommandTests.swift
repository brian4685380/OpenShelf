import AppKit
import ShelfCore
import XCTest
@testable import OpenShelf

@MainActor
final class ShelfRemoteCommandTests: XCTestCase {
    func testRemoteRequestUsesActiveShelfAndRetainsExportUntilQuit() throws {
        _ = NSApplication.shared
        let prepared = try downloadFixture()
        defer { prepared.discard() }
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let local = root.appendingPathComponent("original.txt")
        try Data("original".utf8).write(to: local)
        let mailbox = ShelfCommandMailbox(directory: root.appendingPathComponent("mailbox"))
        let manager = ShelfManager()
        defer { manager.prepareForTermination() }
        let first = manager.activeShelf!
        let receiver = ShelfCommandReceiver(addFiles: { manager.addAndShow(urls: $0) },
            addTemporaryFiles: { manager.addAndShow(urls: $0, temporaryURLs: $1) },
            notificationName: .init("OpenShelf.remote.tests.\(UUID())"), mailbox: mailbox)
        let request = ShelfCommandMailbox.Request(paths: [local.path] + prepared.urls.map(\.path),
            temporaryPaths: prepared.temporaryURLs.map(\.path))
        try mailbox.submit(request)
        receiver.processPendingRequests()
        XCTAssertEqual(mailbox.readReply(for: request.id), .init(addedCount: 2, skippedCount: 0, temporaryFilesAccepted: true))
        XCTAssertEqual(first.store.items.map(\.isManagedByShelf), [false, true])
        XCTAssertNotNil(first.visibleShelfFrame())

        let second = manager.createShelf()
        try mailbox.submit(request)
        receiver.processPendingRequests()
        XCTAssertTrue(second.store.items.isEmpty, "Acknowledgment retry must not retarget the active shelf")
        XCTAssertEqual(first.store.items.count, 2)

        let downloaded = try XCTUnwrap(first.store.items.last)
        let saved = root.appendingPathComponent("saved.txt")
        try FileManager.default.copyItem(at: downloaded.url, to: saved)
        first.store.finishExport([downloaded])
        XCTAssertEqual(first.store.items.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloaded.url.path), "The destination may still be reading")
        first.prepareForTermination()
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloaded.url.path))
        XCTAssertEqual(try String(contentsOf: local), "original")
        XCTAssertEqual(try String(contentsOf: saved), "remote bytes")
    }

    func testForgedTemporaryOriginalOrSymlinkRejectsEntireRequest() throws {
        _ = NSApplication.shared
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original.txt")
        try Data("never delete me".utf8).write(to: original)
        let mailbox = ShelfCommandMailbox(directory: root.appendingPathComponent("mailbox"))
        let controller = FloatingShelfController()
        defer { controller.disposePanels(); controller.prepareForTermination() }
        let receiver = ShelfCommandReceiver(shelfController: controller,
            notificationName: .init("OpenShelf.remote.tests.\(UUID())"), mailbox: mailbox)
        let prepared = try downloadFixture()
        defer { prepared.discard() }
        let symlink = try XCTUnwrap(prepared.urls.first)
        try FileManager.default.removeItem(at: symlink)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: original)
        for unsafe in [original.path, symlink.path, "relative.txt"] {
            let request = ShelfCommandMailbox.Request(paths: [original.path, symlink.path], temporaryPaths: [unsafe])
            try mailbox.submit(request)
            receiver.processPendingRequests()
            XCTAssertEqual(mailbox.readReply(for: request.id)?.temporaryFilesAccepted, false)
            XCTAssertTrue(controller.store.items.isEmpty)
        }
        XCTAssertEqual(try String(contentsOf: original), "never delete me")
    }

    func testRemoteCopiesBetweenShelvesHaveIndependentLifetimes() throws {
        let prepared = try downloadFixture()
        defer { prepared.discard() }
        let source = ShelfStore()
        let target = ShelfStore()
        defer { source.cleanUpSession(); target.cleanUpSession() }
        let url = try XCTUnwrap(prepared.urls.first)
        XCTAssertTrue(source.add(url: url, isManagedByShelf: true))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(source.copy(source.items, to: pasteboard))
        XCTAssertTrue(target.importPasteboard(pasteboard))
        let copy = try XCTUnwrap(target.items.first)
        XCTAssertTrue(copy.isManagedByShelf)
        XCTAssertNotEqual(copy.url, url)
        source.cleanUpSession()
        XCTAssertEqual(try String(contentsOf: copy.url), "remote bytes")
    }

    func testReplyFromOlderAppDoesNotClaimTemporaryOwnership() throws {
        let legacy = Data(#"{"addedCount":1,"skippedCount":0}"#.utf8)
        let reply = try JSONDecoder().decode(ShelfCommandMailbox.Reply.self, from: legacy)
        XCTAssertNil(reply.temporaryFilesAccepted)
        let request = ShelfCommandMailbox.Request(paths: ["/tmp/ordinary-local"])
        let roundTrip = try JSONDecoder().decode(ShelfCommandMailbox.Request.self, from: JSONEncoder().encode(request))
        XCTAssertNil(roundTrip.temporaryPaths)
    }

    private func downloadFixture() throws -> ShelfRemoteFiles.Prepared {
        try ShelfRemoteFiles.prepare(["testhost:report.txt"], relativeTo: FileManager.default.temporaryDirectory,
            runSCP: { args in
                try Data("remote bytes".utf8).write(to: URL(fileURLWithPath: args.last!).appendingPathComponent("report.txt"))
                return 0
            })
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenShelfRemoteCommands-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
