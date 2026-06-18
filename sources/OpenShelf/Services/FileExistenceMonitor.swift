import Darwin
import Foundation

final class FileExistenceMonitor {
    private var fileDescriptor: Int32 = -1
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

        fileDescriptor = descriptor

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
            guard let self else { return }

            let event = source.data

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
        guard !isStopped else { return }

        isStopped = true
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    deinit {
        stop()
    }
}
