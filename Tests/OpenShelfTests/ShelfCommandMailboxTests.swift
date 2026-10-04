import AppKit
import ShelfCore
import XCTest
@testable import OpenShelf

@MainActor
final class ShelfCommandMailboxTests: XCTestCase {
    func testRequestAndReplyWorkWithoutAnyDistributedNotification() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let mailbox = ShelfCommandMailbox(directory: directory.appendingPathComponent("commands"))
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("File with spaces.txt")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: file)
        let controller = FloatingShelfController()
        defer { controller.clearShelf(); controller.closeShelf() }
        let receiver = ShelfCommandReceiver(shelfController: controller,
            notificationName: .init("OpenShelf.tests.\(UUID())"), mailbox: mailbox)
        let request = ShelfCommandMailbox.Request(paths: [file.path])
        try mailbox.submit(request)
        XCTAssertNil(mailbox.readReply(for: request.id))
        receiver.processPendingRequests()
        XCTAssertEqual(mailbox.readReply(for: request.id), .init(addedCount: 1, skippedCount: 0))
        XCTAssertTrue(mailbox.pendingRequests().isEmpty)

        try mailbox.submit(request)
        receiver.processPendingRequests()
        XCTAssertEqual(mailbox.readReply(for: request.id), .init(addedCount: 1, skippedCount: 0))
        let panel = try XCTUnwrap(NSApp.windows.first { $0.title == "OpenShelf" && $0.isVisible })
        let view = try XCTUnwrap(panel.contentView as? ShelfDropContainerView<ContentView>)
        XCTAssertEqual(view.rootView.store.items.count, 1)
        XCTAssertEqual(view.rootView.dropState.successfulDropGeneration, 1)
        mailbox.removeRequest(request.id)
        XCTAssertNil(mailbox.readReply(for: request.id))
    }

    func testMailboxIsPrivateAndRejectsExpiredAndRelativeRequests() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = ShelfCommandMailbox(directory: directory)
        let expired = ShelfCommandMailbox.Request(paths: ["/tmp/a"], createdAt: Date().addingTimeInterval(-20))
        try mailbox.submit(expired)
        try mailbox.submit(.init(paths: ["relative.txt"]))
        XCTAssertTrue(mailbox.pendingRequests().isEmpty)
        let permissions = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o700)
        XCTAssertThrowsError(try mailbox.submit(.init(id: "../not-a-uuid", paths: ["/tmp/a"])))
        XCTAssertTrue(mailbox.pendingRequests(now: Date().addingTimeInterval(30)).isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    func testMailboxRejectsSymlinkedDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        let mailbox = ShelfCommandMailbox(directory: link)
        XCTAssertThrowsError(try mailbox.submit(.init(paths: ["/tmp/a"])))
        XCTAssertTrue(mailbox.pendingRequests().isEmpty)
    }
}
