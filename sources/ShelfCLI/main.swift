import AppKit
import Foundation
import ShelfCore

private let appBundleIdentifier = "com.brianyuan.OpenShelf"

private struct CLIError: Error {
    let message: String
    let code: Int32
}

private func fail(_ message: String, code: Int32) -> Never {
    fputs("shelf: \(message)\n", stderr)
    exit(code)
}

private func launchIfNeeded() throws {
    guard !NSWorkspace.shared.runningApplications.contains(where: {
        !$0.isTerminated && ($0.bundleIdentifier == appBundleIdentifier || $0.localizedName == "OpenShelf")
    }) else { return }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-b", appBundleIdentifier]
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        throw CLIError(message: "could not launch OpenShelf: \(error.localizedDescription)", code: 69)
    }
    guard process.terminationStatus == 0 else {
        throw CLIError(message: "install OpenShelf.app in /Applications and launch it once before using shelf.", code: 69)
    }
}

private func addFiles(_ arguments: [String]) throws {
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let prepared = try ShelfRemoteFiles.prepare(arguments, relativeTo: cwd, runSCP: { arguments in
        fputs("shelf: downloading \(arguments[arguments.count - 2])\n", stderr)
        return try ShelfRemoteFiles.runSCP(arguments)
    })
    var requestQueued = false
    defer { if !requestQueued { prepared.discard() } }

    let center = DistributedNotificationCenter.default()
    let requestID = UUID().uuidString
    let mailbox = ShelfCommandMailbox()
    try launchIfNeeded()
    do {
        try mailbox.submit(.init(id: requestID, paths: prepared.urls.map(\.path),
            temporaryPaths: prepared.temporaryURLs.isEmpty ? nil : prepared.temporaryURLs.map(\.path)))
    } catch { throw CLIError(message: "could not queue request: \(error.localizedDescription)", code: 75) }
    requestQueued = true
    defer { mailbox.removeRequest(requestID) }
    let retainedDownloads = prepared.temporaryURLs.isEmpty ? "" :
        "\nTemporary downloads retained (the app may already own them):\n" + prepared.temporaryURLs.map(\.path).joined(separator: "\n")
    var reply: ShelfCommandMailbox.Reply?
    let deadline = Date().addingTimeInterval(5)
    repeat {
        // LaunchServices can briefly report an app that is still terminating
        // after Quit/an upgrade. Recheck while the queued request is pending.
        do { try launchIfNeeded() }
        catch { throw CLIError(message: "could not reach OpenShelf.\(retainedDownloads)", code: 75) }
        center.postNotificationName(ShelfCommandProtocol.addFiles, object: nil,
            userInfo: ["mailbox": true], deliverImmediately: true)
        Thread.sleep(forTimeInterval: 0.1)
        reply = mailbox.readReply(for: requestID)
    } while reply == nil && Date() < deadline

    guard let reply else {
        throw CLIError(message: "no acknowledgment from OpenShelf. Quit and reopen the updated app, then try again. Files may already have been added.\(retainedDownloads)", code: 75)
    }
    if !prepared.temporaryURLs.isEmpty, reply.temporaryFilesAccepted != true {
        throw CLIError(message: "OpenShelf did not accept ownership of the temporary downloads. Restart OpenShelf 0.9.0 or newer.\(retainedDownloads)", code: 75)
    }
    print("OpenShelf: added \(reply.addedCount), skipped \(reply.skippedCount).")
}

do {
    let arguments: ShelfCLIArguments
    do { arguments = try ShelfCLIArguments(Array(CommandLine.arguments.dropFirst())) }
    catch { throw CLIError(message: "\(error)\n\n\(ShelfCLIArguments.usage)", code: 64) }
    switch arguments {
    case .help: print(ShelfCLIArguments.usage)
    case .version: print("shelf \(OpenShelfVersion.current)")
    case .files(let files): try addFiles(files)
    }
} catch let error as CLIError {
    fail(error.message, code: error.code)
} catch let error as ShelfRemoteFiles.ImportError {
    fail(error.description, code: error.exitCode)
} catch {
    fail("\(error.localizedDescription)", code: 74)
}
