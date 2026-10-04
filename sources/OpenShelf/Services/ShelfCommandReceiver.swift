import AppKit
import ShelfCore

@MainActor
final class ShelfCommandReceiver: NSObject {
    private weak var shelfController: FloatingShelfController?
    private let acknowledgmentName: Notification.Name
    private var completedRequests: [String: ShelfImportOutcome] = [:]
    private var requestOrder: [String] = []
    init(
        shelfController: FloatingShelfController,
        notificationName: Notification.Name = ShelfCommandProtocol.addFiles,
        acknowledgmentName: Notification.Name = ShelfCommandProtocol.acknowledged
    ) {
        self.shelfController = shelfController
        self.acknowledgmentName = acknowledgmentName
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

        let requestID = notification.userInfo?["requestID"] as? String
        if let requestID, let outcome = completedRequests[requestID] {
            acknowledge(requestID, outcome: outcome)
            return
        }
        let urls = paths.filter { $0.hasPrefix("/") }.map {
            URL(fileURLWithPath: $0).standardizedFileURL
        }

        guard let outcome = shelfController?.addAndShow(urls: urls) else { return }
        if let requestID {
            completedRequests[requestID] = outcome
            requestOrder.append(requestID)
            if requestOrder.count > 128 {
                completedRequests.removeValue(forKey: requestOrder.removeFirst())
            }
            acknowledge(requestID, outcome: outcome)
        }
    }

    private func acknowledge(_ requestID: String, outcome: ShelfImportOutcome) {
        DistributedNotificationCenter.default().postNotificationName(
            acknowledgmentName, object: requestID,
            userInfo: ["addedCount": outcome.addedCount, "skippedCount": outcome.skippedCount],
            deliverImmediately: true
        )
    }
}
