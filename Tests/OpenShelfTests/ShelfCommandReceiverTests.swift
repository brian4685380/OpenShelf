import AppKit
import XCTest
@testable import OpenShelf

@MainActor
final class ShelfCommandReceiverTests: XCTestCase {
    func testAcknowledgmentIsIdempotentAcrossRetries() throws {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CLI Ack \(UUID()).txt")
        try Data("fixture".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = FloatingShelfController()
        defer { controller.clearShelf(); controller.closeShelf() }
        let requestName = Notification.Name("OpenShelf.tests.request.\(UUID())")
        let replyName = Notification.Name("OpenShelf.tests.reply.\(UUID())")
        let receiver = ShelfCommandReceiver(shelfController: controller,
            notificationName: requestName, acknowledgmentName: replyName)
        let id = UUID().uuidString
        var counts: [Int] = []
        let center = DistributedNotificationCenter.default()
        let observer = center.addObserver(forName: replyName, object: id, queue: .main) {
            if let count = $0.userInfo?["addedCount"] as? Int { counts.append(count) }
        }
        defer { center.removeObserver(observer) }
        withExtendedLifetime(receiver) {
            for _ in 0..<2 {
                center.postNotificationName(requestName, object: nil,
                    userInfo: ["paths": [url.path], "requestID": id], deliverImmediately: true)
                RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            }
        }
        XCTAssertEqual(counts, [1, 1], "A retry must acknowledge the original result, not add/show again.")
        let panel = try XCTUnwrap(NSApp.windows.first { $0.title == "OpenShelf" && $0.isVisible })
        let view = try XCTUnwrap(panel.contentView as? ShelfDropContainerView<ContentView>)
        XCTAssertEqual(view.rootView.store.items.count, 1)
        XCTAssertEqual(view.rootView.dropState.successfulDropGeneration, 1)
    }

    func testCommandNotificationAddsMultipleFilesAndShowsShelf() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenShelf CLI \(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let urls = try ["First.txt", "Second.txt"].map { name in
            let url = directory.appendingPathComponent(name)
            try Data(name.utf8).write(to: url)
            return url
        }
        defer { try? FileManager.default.removeItem(at: directory) }

        let controller = FloatingShelfController()
        controller.preparePanel()
        // Use the real distributed transport without adding fixture files to
        // a user's running shelf or moving it to the test's active display.
        let notificationName = Notification.Name(
            "com.brianyuan.OpenShelf.tests.addFiles.\(UUID().uuidString)"
        )
        let receiver = ShelfCommandReceiver(
            shelfController: controller,
            notificationName: notificationName
        )
        withExtendedLifetime(receiver) {
            DistributedNotificationCenter.default().postNotificationName(
                notificationName,
                object: nil,
                userInfo: ["paths": urls.map(\.path)],
                deliverImmediately: true
            )
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        defer {
            controller.clearShelf()
            controller.closeShelf()
        }

        let panel = try XCTUnwrap(
            NSApp.windows.first {
                $0.title == "OpenShelf" && $0.isVisible
            }
        )
        let container = try XCTUnwrap(
            panel.contentView as? ShelfDropContainerView<ContentView>
        )

        XCTAssertEqual(
            container.rootView.store.items.map(\.url),
            urls.map(\.standardizedFileURL)
        )
    }
}
