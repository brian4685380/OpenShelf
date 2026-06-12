import Foundation

final class QuickLookPreviewer {
    static let shared = QuickLookPreviewer()

    private var activeProcesses: [Process] = []

    private init() {}

    func preview(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Quick Look failed: file does not exist:", url.path)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = [
            "-p",
            url.path,
        ]

        process.terminationHandler = { [weak self, weak process] _ in
            DispatchQueue.main.async {
                guard let process else { return }
                self?.activeProcesses.removeAll { $0 === process }
            }
        }

        do {
            activeProcesses.append(process)
            try process.run()
            print("Quick Look opened:", url.path)
        } catch {
            activeProcesses.removeAll { $0 === process }
            print("Quick Look failed:", error)
        }
    }
}
