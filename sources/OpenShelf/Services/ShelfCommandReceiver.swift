import AppKit

@MainActor
final class ShelfCommandReceiver: NSObject {
    private weak var shelfController: FloatingShelfController?
    private let notificationName = Notification.Name(
        "com.brianyuan.OpenShelf.cli.addFiles"
    )

    init(shelfController: FloatingShelfController) {
        self.shelfController = shelfController
        super.init()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleAddFilesNotification(_:)),
            name: notificationName,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func handleAddFilesNotification(
        _ notification: Notification
    ) {
        guard let paths = notification.userInfo?["paths"] as? [String] else {
            return
        }

        let urls = paths.map {
            URL(fileURLWithPath: $0).standardizedFileURL
        }

        shelfController?.addAndShow(urls: urls)
    }
}
