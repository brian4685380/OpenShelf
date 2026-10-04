import AppKit
import Foundation
import ShelfCore

private let appBundleIdentifier = "com.brianyuan.OpenShelf"

private func fail(_ message: String, code: Int32) -> Never {
    fputs("shelf: \(message)\n", stderr)
    exit(code)
}

private func launchIfNeeded() {
    guard !NSWorkspace.shared.runningApplications.contains(where: {
        $0.bundleIdentifier == appBundleIdentifier || $0.localizedName == "OpenShelf"
    }) else { return }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-b", appBundleIdentifier]
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        fail("could not launch OpenShelf: \(error.localizedDescription)", code: 69)
    }
    guard process.terminationStatus == 0 else {
        fail("install OpenShelf.app in /Applications and launch it once before using shelf.", code: 69)
    }
}

let arguments: ShelfCLIArguments
do { arguments = try ShelfCLIArguments(Array(CommandLine.arguments.dropFirst())) }
catch { fail("\(error)\n\n\(ShelfCLIArguments.usage)", code: 64) }

switch arguments {
case .help:
    print(ShelfCLIArguments.usage)
case .version:
    print("shelf \(OpenShelfVersion.current)")
case .files(let arguments):
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    var seen = Set<String>()
    var paths: [String] = []
    // Validate the entire request first; don't silently add a partial set.
    for argument in arguments {
        let path = URL(fileURLWithPath: argument, relativeTo: cwd).standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            fail("file does not exist: \(argument)", code: 66)
        }
        if seen.insert(path).inserted { paths.append(path) }
    }

    let center = DistributedNotificationCenter.default()
    let requestID = UUID().uuidString
    var reply: [AnyHashable: Any]?
    let observer = center.addObserver(forName: ShelfCommandProtocol.acknowledged,
        object: requestID, queue: .main) { reply = $0.userInfo }
    defer { center.removeObserver(observer) }
    launchIfNeeded()
    let deadline = Date().addingTimeInterval(5)
    repeat {
        center.postNotificationName(ShelfCommandProtocol.addFiles, object: nil,
            userInfo: ["paths": paths, "requestID": requestID], deliverImmediately: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    } while reply == nil && Date() < deadline

    guard let reply, let added = reply["addedCount"] as? Int,
        let skipped = reply["skippedCount"] as? Int else {
        fail("no acknowledgment from OpenShelf. Quit and reopen the updated app, then try again. Files may already have been added.", code: 75)
    }
    print("OpenShelf: added \(added), skipped \(skipped).")
}
