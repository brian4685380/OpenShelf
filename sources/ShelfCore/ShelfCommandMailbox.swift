import Foundation
import Darwin

/// A per-user, short-lived request/reply queue. Distributed notifications are
/// wake-up hints only; losing one must not silently lose a CLI request.
public final class ShelfCommandMailbox {
    public struct Request: Codable {
        public let id: String
        public let paths: [String]
        public let createdAt: Date
        public init(id: String = UUID().uuidString, paths: [String], createdAt: Date = Date()) {
            self.id = id
            self.paths = paths
            self.createdAt = createdAt
        }
    }

    public struct Reply: Codable, Equatable {
        public let addedCount: Int
        public let skippedCount: Int
        public init(addedCount: Int, skippedCount: Int) {
            self.addedCount = addedCount
            self.skippedCount = skippedCount
        }
    }

    public static let lifetime: TimeInterval = 10
    public let directory: URL

    public init(directory: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("com.brianyuan.OpenShelf.commands", isDirectory: true)) {
        self.directory = directory
    }

    public func submit(_ request: Request) throws {
        try prepareDirectory()
        let data = try JSONEncoder().encode(request)
        guard data.count <= 1_048_576 else { throw MailboxError.requestTooLarge }
        try data.write(to: url(request.id, extension: "request"), options: .atomic)
    }

    public func pendingRequests(now: Date = Date()) -> [Request] {
        guard (try? prepareDirectory()) != nil else { return [] }
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]) else { return [] }
        var requests: [Request] = []
        for entry in entries {
            guard ["request", "reply"].contains(entry.pathExtension),
                UUID(uuidString: entry.deletingPathExtension().lastPathComponent) != nil,
                let values = try? entry.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]),
                values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            if now.timeIntervalSince(values.contentModificationDate ?? .distantPast) > Self.lifetime {
                try? FileManager.default.removeItem(at: entry)
                continue
            }
            guard entry.pathExtension == "request", (values.fileSize ?? Int.max) <= 1_048_576,
                let data = try? Data(contentsOf: entry),
                let request = try? JSONDecoder().decode(Request.self, from: data),
                request.id == entry.deletingPathExtension().lastPathComponent,
                now.timeIntervalSince(request.createdAt) >= -1,
                now.timeIntervalSince(request.createdAt) < Self.lifetime,
                !request.paths.isEmpty, request.paths.allSatisfy({ $0.hasPrefix("/") }) else { continue }
            requests.append(request)
        }
        return requests.sorted { $0.createdAt < $1.createdAt }
    }

    public func reply(to id: String, with reply: Reply) throws {
        try prepareDirectory()
        try JSONEncoder().encode(reply).write(to: url(id, extension: "reply"), options: .atomic)
        try? FileManager.default.removeItem(at: url(id, extension: "request"))
    }

    public func readReply(for id: String) -> Reply? {
        guard (try? prepareDirectory()) != nil,
            let path = try? url(id, extension: "reply"),
            let values = try? path.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
            values.isRegularFile == true, values.isSymbolicLink != true,
            (values.fileSize ?? Int.max) < 1024,
            let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode(Reply.self, from: data)
    }

    public func removeRequest(_ id: String) {
        for ext in ["request", "reply"] {
            if let path = try? url(id, extension: ext) { try? FileManager.default.removeItem(at: path) }
        }
    }

    private func url(_ id: String, extension ext: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw MailboxError.invalidRequestID }
        return directory.appendingPathComponent(id).appendingPathExtension(ext)
    }

    private func prepareDirectory() throws {
        let manager = FileManager.default
        if !manager.fileExists(atPath: directory.path) {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        }
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let attributes = try manager.attributesOfItem(atPath: directory.path)
        guard values.isDirectory == true, values.isSymbolicLink != true,
            (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
            throw MailboxError.unsafeDirectory
        }
        if (attributes[.posixPermissions] as? NSNumber)?.intValue != 0o700 {
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
    }

    public enum MailboxError: Error { case invalidRequestID, requestTooLarge, unsafeDirectory }
}
