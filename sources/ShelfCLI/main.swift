import AppKit
import Foundation

private let appBundleIdentifier = "com.brianyuan.OpenShelf"
private let notificationName = Notification.Name(
    "com.brianyuan.OpenShelf.cli.addFiles"
)

enum LaunchState {
    case alreadyRunning
    case launched
    case failed
}

private func printUsageAndExit() -> Never {
    fputs(
        """
        Usage:
          shelf <file-or-folder> [more-files-or-folders...]

        Adds files or folders to OpenShelf. If OpenShelf is not running,
        the command will try to launch it first.

        """,
        stderr
    )
    exit(64)
}

private func existingFilePaths(from arguments: [String]) -> [String] {
    let currentDirectoryURL = URL(
        fileURLWithPath: FileManager.default.currentDirectoryPath,
        isDirectory: true
    )

    return arguments.compactMap { argument in
        let url = URL(fileURLWithPath: argument, relativeTo: currentDirectoryURL)
            .standardizedFileURL

        guard FileManager.default.fileExists(atPath: url.path) else {
            fputs("shelf: file does not exist: \(argument)\n", stderr)
            return nil
        }

        return url.path
    }
}

private func isOpenShelfRunning() -> Bool {
    NSWorkspace.shared.runningApplications.contains {
        $0.bundleIdentifier == appBundleIdentifier
    }
}

private func launchOpenShelfIfNeeded() -> LaunchState {
    guard !isOpenShelfRunning() else {
        return .alreadyRunning
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-b", appBundleIdentifier]

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        fputs("shelf: could not launch OpenShelf: \(error)\n", stderr)
        return .failed
    }

    guard process.terminationStatus == 0 else {
        fputs(
            """
            shelf: could not launch OpenShelf.
            Make sure OpenShelf.app is installed in /Applications.

            """,
            stderr
        )
        return .failed
    }

    return .launched
}

private func postAddFilesNotification(paths: [String]) {
    DistributedNotificationCenter.default().postNotificationName(
        notificationName,
        object: nil,
        userInfo: ["paths": paths],
        deliverImmediately: true
    )
}

let arguments = Array(CommandLine.arguments.dropFirst())

guard !arguments.isEmpty else {
    printUsageAndExit()
}

let paths = existingFilePaths(from: arguments)

guard !paths.isEmpty else {
    exit(66)
}

let launchState = launchOpenShelfIfNeeded()

guard launchState != .failed else {
    exit(69)
}

/*
 The app may need a moment to finish launching and install its distributed
 notification observer. Posting repeatedly keeps the command simple and makes
 the cold-start path reliable enough without introducing a long-running helper.
 The app de-duplicates file URLs in ShelfStore.add(url:).
*/
let attempts = launchState == .launched ? 12 : 2

for attempt in 0..<attempts {
    postAddFilesNotification(paths: paths)

    if attempt < attempts - 1 {
        Thread.sleep(forTimeInterval: 0.15)
    }
}
