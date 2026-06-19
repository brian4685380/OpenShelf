import Darwin
import Foundation

final class FileExistenceMonitor {
    private let stateLock = NSLock()
    private var source: DispatchSourceFileSystemObject?
    private var isStopped = false

    init?(
        url: URL,
        onUnavailable: @escaping () -> Void
    ) {
        let descriptor = open(url.path, O_EVTONLY)

        guard descriptor >= 0 else {
            return nil
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
