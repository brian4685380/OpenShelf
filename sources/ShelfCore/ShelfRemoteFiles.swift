import Foundation
import Darwin

/// Downloads are local, session-owned copies. Neither this type nor its
/// cleanup paths ever run a remote deletion command.
public enum ShelfRemoteFiles {
    public static let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("com.brianyuan.OpenShelf.remote", isDirectory: true)

    public enum Input: Hashable {
        case local(URL)
        case remote(String)

        public init(_ argument: String, relativeTo cwd: URL) throws {
            guard !argument.isEmpty, !argument.contains("\0")
            else { throw ImportError.invalidRemote(argument) }
            // Like scp, ./ and absolute paths disambiguate local colon names.
            let delimiter: String.Index?
            if let bracket = argument.firstIndex(of: "["),
               let end = argument[bracket...].firstIndex(of: "]"),
               argument.index(after: end) < argument.endIndex,
               argument[argument.index(after: end)] == ":" {
                delimiter = argument.index(after: end)
            } else {
                delimiter = argument.firstIndex(of: ":")
            }
            if let delimiter, !argument[..<delimiter].contains("/") {
                let authority = String(argument[..<delimiter])
                let path = String(argument[argument.index(after: delimiter)...])
                let parts = authority.split(separator: "@", omittingEmptySubsequences: false)
                let host = String(parts.last ?? "")
                let plain = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
                let ipv6 = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:.%_-")
                let validHost: Bool
                if host.hasPrefix("["), host.hasSuffix("]") {
                    let address = host.dropFirst().dropLast()
                    validHost = address.contains(":") && address.unicodeScalars.allSatisfy(ipv6.contains)
                } else {
                    validHost = !host.isEmpty && !host.hasPrefix("-") && host.unicodeScalars.allSatisfy(plain.contains)
                }
                guard parts.count <= 2, validHost, !path.isEmpty, !argument.contains("://"),
                      parts.count == 1 || (!parts[0].isEmpty && parts[0].unicodeScalars.allSatisfy(plain.contains))
                else { throw ImportError.invalidRemote(argument) }
                self = .remote(argument)
            } else {
                let expanded = (argument as NSString).expandingTildeInPath
                let base = URL(fileURLWithPath: cwd.path, isDirectory: true)
                let url = URL(fileURLWithPath: expanded, relativeTo: base).standardizedFileURL
                guard FileManager.default.fileExists(atPath: url.path) else { throw ImportError.missingFile(argument) }
                self = .local(url)
            }
        }
    }

    public struct Prepared {
        public let urls: [URL]
        public let temporaryURLs: [URL]
        private let directories: [URL]
        fileprivate init(urls: [URL], temporaryURLs: [URL], directories: [URL]) {
            self.urls = urls; self.temporaryURLs = temporaryURLs; self.directories = directories
        }

        /// Use only before a request has been queued. After an uncertain
        /// acknowledgment the app may already own these files: retain them.
        public func discard() {
            for directory in directories { try? FileManager.default.removeItem(at: directory) }
        }
    }

    public static func prepare(_ arguments: [String], relativeTo cwd: URL,
                               root: URL = directory,
                               runSCP: ([String]) throws -> Int32 = runSCP) throws -> Prepared {
        // Validate all local paths and remote syntax before network activity.
        var seen = Set<Input>()
        let inputs = try arguments.map { try Input($0, relativeTo: cwd) }.filter { seen.insert($0).inserted }
        var urls: [URL] = []
        var temporaryURLs: [URL] = []
        var directories: [URL] = []
        do {
            for input in inputs {
                switch input {
                case .local(let url): urls.append(url)
                case .remote(let source):
                    try preparePrivateDirectory(root)
                    let destination = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false,
                        attributes: [.posixPermissions: 0o700])
                    directories.append(destination)
                    // No shell interpolation and no weakening of host-key or
                    // filename verification. macOS 13+ scp uses SFTP by default.
                    let status = try runSCP(["-r", "--", source, destination.path + "/"])
                    guard status == 0 else { throw ImportError.transferFailed(source, status) }
                    let downloads = try FileManager.default.contentsOfDirectory(at: destination,
                        includingPropertiesForKeys: nil).sorted { $0.lastPathComponent < $1.lastPathComponent }
                    guard !downloads.isEmpty else { throw ImportError.emptyTransfer(source) }
                    for url in downloads { try validateTemporaryFile(url, root: root) }
                    urls += downloads
                    temporaryURLs += downloads
                }
            }
            return Prepared(urls: urls, temporaryURLs: temporaryURLs, directories: directories)
        } catch {
            for directory in directories { try? FileManager.default.removeItem(at: directory) }
            throw error
        }
    }

    /// Only direct children of our private UUID transfer directories may be
    /// adopted for deletion. An IPC caller cannot mark an arbitrary original
    /// or a symlink into another directory as temporary content.
    public static func validateTemporaryFile(_ url: URL, root: URL = directory) throws {
        let path = url.standardizedFileURL
        let parent = path.deletingLastPathComponent()
        guard url.isFileURL, UUID(uuidString: parent.lastPathComponent) != nil,
              parent.deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path
        else { throw ImportError.unsafeDirectory }
        try validatePrivateDirectory(root)
        try validatePrivateDirectory(parent)
        let values = try path.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
        guard values.isSymbolicLink != true, values.isDirectory == true || values.isRegularFile == true
        else { throw ImportError.unsafeDirectory }
    }

    public static func containsManagedFile(_ url: URL) -> Bool {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        return url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root)
    }

    private static func preparePrivateDirectory(_ url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        }
        try validatePrivateDirectory(url)
    }

    private static func validatePrivateDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard values.isDirectory == true, values.isSymbolicLink != true,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700
        else { throw ImportError.unsafeDirectory }
    }

    public static func runSCP(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
        process.arguments = arguments
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        // Keep the parent alive long enough to remove partial downloads when
        // Ctrl-C interrupts scp. SSH authentication remains in the terminal.
        let queue = DispatchQueue(label: "OpenShelf.scp.signals")
        var interrupted: Int32?
        let signals: [Int32] = [SIGINT, SIGTERM]
        let previous = signals.map { Darwin.signal($0, SIG_IGN) }
        let sources = signals.map { number -> DispatchSourceSignal in
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler {
                interrupted = number
                if process.isRunning { process.terminate() }
            }
            source.resume()
            return source
        }
        defer {
            queue.sync { sources.forEach { $0.cancel() } }
            for (number, handler) in zip(signals, previous) { Darwin.signal(number, handler) }
        }
        try process.run()
        queue.sync { if interrupted != nil, process.isRunning { process.terminate() } }
        process.waitUntilExit()
        if let signal = queue.sync(execute: { interrupted }) { throw ImportError.interrupted(signal) }
        return process.terminationStatus
    }

    public enum ImportError: Error, CustomStringConvertible {
        case missingFile(String), invalidRemote(String), transferFailed(String, Int32), emptyTransfer(String)
        case unsafeDirectory, interrupted(Int32)
        public var exitCode: Int32 {
            switch self {
            case .missingFile: return 66
            case .invalidRemote: return 64
            case .interrupted(let signal): return 128 + signal
            default: return 74
            }
        }
        public var description: String {
            switch self {
            case .missingFile(let path): return "file does not exist: \(path)"
            case .invalidRemote(let path): return "invalid source: \(path) (use [user@]host:path, or ./ for local names containing a colon)"
            case .transferFailed(let source, let status): return "scp failed for \(source) (exit \(status)); nothing was added"
            case .emptyTransfer(let source): return "scp returned no files for \(source); nothing was added"
            case .unsafeDirectory: return "refusing unsafe temporary download storage"
            case .interrupted: return "transfer interrupted; partial downloads removed"
            }
        }
    }
}
