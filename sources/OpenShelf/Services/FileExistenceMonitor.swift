import Darwin
import Foundation

final class FileExistenceMonitor {
    private static let setupQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "OpenShelf.file-monitor-setup"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 4
        return queue
    }()
    private let stateLock = NSLock()
    private var source: DispatchSourceFileSystemObject?
    private var isStopped = false

    var isMonitoring: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return source != nil && !isStopped
    }

    init(
        url: URL,
        openDescriptor: @escaping (String) -> Int32 = { open($0, O_EVTONLY | O_NONBLOCK | O_CLOEXEC) },
        onUnavailable: @escaping () -> Void
    ) {
        // Even O_EVTONLY can block inside macOS (permissions, a filesystem
        // provider, or a slow volume). Never open a watcher on the UI thread.
        Self.setupQueue.addOperation { [weak self] in
            guard let self else { return }
            let descriptor = openDescriptor(url.path)
            guard descriptor >= 0 else {
                DispatchQueue.main.async(execute: onUnavailable)
                return
            }
            self.install(descriptor: descriptor, onUnavailable: onUnavailable)
        }
    }

    private func install(descriptor: Int32, onUnavailable: @escaping () -> Void) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isStopped else {
            close(descriptor)
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [
                .delete,
                .rename,
                .revoke,
            ],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            guard
                let self,
                let event = self.pendingEvents()
            else {
                return
            }

            guard
                event.contains(.delete)
                    || event.contains(.rename)
                    || event.contains(.revoke)
            else {
                return
            }

            DispatchQueue.main.async {
                onUnavailable()
            }

            self.stop()
        }

        source.setCancelHandler {
            close(descriptor)
        }

        self.source = source
        source.resume()
        // Recheck after setup so deletion between open and source registration
        // cannot leave a stale row. The store only removes actually missing files.
        DispatchQueue.main.async(execute: onUnavailable)
    }

    func stop() {
        let sourceToCancel: DispatchSourceFileSystemObject?

        stateLock.lock()

        if isStopped {
            stateLock.unlock()
            return
        }

        isStopped = true
        sourceToCancel = source
        source = nil

        stateLock.unlock()

        sourceToCancel?.cancel()
    }

    private func pendingEvents() -> DispatchSource.FileSystemEvent? {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard !isStopped else { return nil }
        return source?.data
    }

    deinit {
        stop()
    }
}
