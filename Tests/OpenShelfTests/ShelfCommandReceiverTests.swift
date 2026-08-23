import AppKit
import XCTest
@testable import OpenShelf

@MainActor
final class ShelfCommandReceiverTests: XCTestCase {
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
        let receiver = ShelfCommandReceiver(shelfController: controller)
        withExtendedLifetime(receiver) {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("com.brianyuan.OpenShelf.cli.addFiles"),
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
