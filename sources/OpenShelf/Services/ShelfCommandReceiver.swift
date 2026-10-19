import AppKit
import ShelfCore

@MainActor
final class ShelfCommandReceiver: NSObject {
    private let addFiles: ([URL]) -> ShelfImportOutcome?
    private let addTemporaryFiles: (([URL], Set<URL>) -> ShelfImportOutcome?)?
    private let acknowledgmentName: Notification.Name
    private var completedRequests: [String: ShelfCommandMailbox.Reply] = [:]
    private var requestOrder: [String] = []
    private let mailbox: ShelfCommandMailbox
    convenience init(
        shelfController: FloatingShelfController,
        notificationName: Notification.Name = ShelfCommandProtocol.addFiles,
        acknowledgmentName: Notification.Name = ShelfCommandProtocol.acknowledged,
        mailbox: ShelfCommandMailbox = ShelfCommandMailbox()
    ) {
        self.init(addFiles: { [weak shelfController] in shelfController?.addAndShow(urls: $0) },
                  addTemporaryFiles: { [weak shelfController] urls, temporary in
                      shelfController?.addAndShow(urls: urls, temporaryURLs: temporary)
                  },
                  notificationName: notificationName, acknowledgmentName: acknowledgmentName, mailbox: mailbox)
    }

    init(
        addFiles: @escaping ([URL]) -> ShelfImportOutcome?,
        addTemporaryFiles: (([URL], Set<URL>) -> ShelfImportOutcome?)? = nil,
        notificationName: Notification.Name = ShelfCommandProtocol.addFiles,
        acknowledgmentName: Notification.Name = ShelfCommandProtocol.acknowledged,
        mailbox: ShelfCommandMailbox = ShelfCommandMailbox()
    ) {
        self.addFiles = addFiles
        self.addTemporaryFiles = addTemporaryFiles
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
            completedRequests[requestID] = .init(addedCount: outcome.addedCount, skippedCount: outcome.skippedCount)
            requestOrder.append(requestID)
            if requestOrder.count > 128 {
                completedRequests.removeValue(forKey: requestOrder.removeFirst())
            }
            acknowledge(requestID, outcome: .init(addedCount: outcome.addedCount, skippedCount: outcome.skippedCount))
        }
    }

    func processPendingRequests() {
        for request in mailbox.pendingRequests() {
            let outcome: ShelfCommandMailbox.Reply
            if let cached = completedRequests[request.id] {
                outcome = cached
            } else {
                let urls = request.paths.map { URL(fileURLWithPath: $0).standardizedFileURL }
                let temporary = Set((request.temporaryPaths ?? []).map { URL(fileURLWithPath: $0).standardizedFileURL })
                if !temporary.isEmpty {
                    // Reject the whole request before changing any shelf if
                    // ownership metadata could cause deletion of an original.
                    guard let addTemporaryFiles, temporary.isSubset(of: Set(urls)),
                          request.temporaryPaths?.allSatisfy({ $0.hasPrefix("/") }) == true,
                          temporary.allSatisfy({ (try? ShelfRemoteFiles.validateTemporaryFile($0)) != nil })
                    else {
                        try? mailbox.reply(to: request.id, with: .init(addedCount: 0,
                            skippedCount: urls.count, temporaryFilesAccepted: false))
                        continue
                    }
                    guard let result = addTemporaryFiles(urls, temporary) else { return }
                    outcome = .init(addedCount: result.addedCount, skippedCount: result.skippedCount,
                                    temporaryFilesAccepted: true)
                } else {
                    guard let result = addFiles(urls) else { return }
                    outcome = .init(addedCount: result.addedCount, skippedCount: result.skippedCount)
                }
                completedRequests[request.id] = outcome
                requestOrder.append(request.id)
                if requestOrder.count > 128 {
                    completedRequests.removeValue(forKey: requestOrder.removeFirst())
                }
            }
            // Keep the request for a later retry if the reply couldn't be
            // persisted. The cached outcome prevents duplicate UI changes.
            try? mailbox.reply(to: request.id, with: outcome)
        }
    }

    private func acknowledge(_ requestID: String, outcome: ShelfCommandMailbox.Reply) {
        DistributedNotificationCenter.default().postNotificationName(
            acknowledgmentName, object: requestID,
            userInfo: ["addedCount": outcome.addedCount, "skippedCount": outcome.skippedCount],
            deliverImmediately: true
        )
    }
}
