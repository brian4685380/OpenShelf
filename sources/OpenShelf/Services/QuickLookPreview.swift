import Foundation

final class QuickLookPreviewer {
    static let shared = QuickLookPreviewer()

    private var activeProcesses: [Process] = []

    private init() {}

    func preview(url: URL) {
        preview(urls: [url])
    }

    func preview(urls: [URL]) {
        let existingURLs = urls.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }

        guard !existingURLs.isEmpty else {
            print("Quick Look failed: no selected files exist.")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-p"] + existingURLs.map(\.path)

        process.terminationHandler = { [weak self, weak process] _ in
            DispatchQueue.main.async {
                guard let process else { return }
                self?.activeProcesses.removeAll { $0 === process }
            }
        }

        do {
            activeProcesses.append(process)
            try process.run()
            print("Quick Look opened \(existingURLs.count) file(s).")
        } catch {
            activeProcesses.removeAll { $0 === process }
            print("Quick Look failed:", error)
        }
    }
}
