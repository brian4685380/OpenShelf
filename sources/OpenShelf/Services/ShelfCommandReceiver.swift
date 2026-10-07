import AppKit
import ShelfCore

@MainActor
final class ShelfCommandReceiver: NSObject {
    private let addFiles: ([URL]) -> ShelfImportOutcome?
    private let acknowledgmentName: Notification.Name
    private var completedRequests: [String: ShelfImportOutcome] = [:]
    private var requestOrder: [String] = []
    private let mailbox: ShelfCommandMailbox
    convenience init(
        shelfController: FloatingShelfController,
        notificationName: Notification.Name = ShelfCommandProtocol.addFiles,
        acknowledgmentName: Notification.Name = ShelfCommandProtocol.acknowledged,
        mailbox: ShelfCommandMailbox = ShelfCommandMailbox()
    ) {
        self.init(addFiles: { [weak shelfController] in shelfController?.addAndShow(urls: $0) },
                  notificationName: notificationName, acknowledgmentName: acknowledgmentName, mailbox: mailbox)
    }

    init(
        addFiles: @escaping ([URL]) -> ShelfImportOutcome?,
        notificationName: Notification.Name = ShelfCommandProtocol.addFiles,
        acknowledgmentName: Notification.Name = ShelfCommandProtocol.acknowledged,
        mailbox: ShelfCommandMailbox = ShelfCommandMailbox()
    ) {
        self.addFiles = addFiles
        self.acknowledgmentName = acknowledgmentName
        self.mailbox = mailbox
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
        if notification.userInfo?["mailbox"] as? Bool == true {
            processPendingRequests()
            return
        }
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

        guard let outcome = addFiles(urls) else { return }
        if let requestID {
            completedRequests[requestID] = outcome
            requestOrder.append(requestID)
            if requestOrder.count > 128 {
                completedRequests.removeValue(forKey: requestOrder.removeFirst())
            }
            acknowledge(requestID, outcome: outcome)
        }
    }

    func processPendingRequests() {
        for request in mailbox.pendingRequests() {
            let outcome: ShelfImportOutcome
            if let cached = completedRequests[request.id] {
                outcome = cached
            } else {
                guard let result = addFiles(request.paths.map { URL(fileURLWithPath: $0) }) else { return }
                outcome = result
                completedRequests[request.id] = result
                requestOrder.append(request.id)
                if requestOrder.count > 128 {
                    completedRequests.removeValue(forKey: requestOrder.removeFirst())
                }
            }
            // Keep the request for a later retry if the reply couldn't be
            // persisted. The cached outcome prevents duplicate UI changes.
            try? mailbox.reply(to: request.id, with: .init(addedCount: outcome.addedCount, skippedCount: outcome.skippedCount))
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
