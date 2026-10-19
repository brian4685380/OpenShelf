import Foundation
import ShelfCore
import XCTest

final class ShelfRemoteFilesTests: XCTestCase {
    func testRemoteSyntaxAndExplicitLocalColonNames() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let local = root.appendingPathComponent("host:file.txt")
        try Data("local".utf8).write(to: local)
        for value in ["server:/tmp/file", "me@alias:relative folder", "server:~/file", "[::1]:/tmp/file", "me@[fe80::1%en0]:folder"] {
            XCTAssertEqual(try ShelfRemoteFiles.Input(value, relativeTo: root), .remote(value))
        }
        XCTAssertEqual(try ShelfRemoteFiles.Input("./host:file.txt", relativeTo: root), .local(local))
        XCTAssertEqual(try ShelfRemoteFiles.Input(local.path, relativeTo: root), .local(local))
        for value in ["host:", ":file", "-host:file", "me@-host:file", "@host:file", "a@b@c:file", "host name:file", "host;echo:file", "scp://host/file", "host:\0bad"] {
            XCTAssertThrowsError(try ShelfRemoteFiles.Input(value, relativeTo: root), value)
        }
    }

    func testAllInputsAreValidatedBeforeTransfer() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var transfers = 0
        XCTAssertThrowsError(try ShelfRemoteFiles.prepare(["server:file", "missing-local"], relativeTo: root,
            root: root.appendingPathComponent("downloads"), runSCP: { _ in transfers += 1; return 0 }))
        XCTAssertEqual(transfers, 0)
    }

    func testMixedInputsKeepOrderAndSameBasenamesCannotOverwriteEachOther() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let local = root.appendingPathComponent("local.txt")
        try Data("local".utf8).write(to: local)
        var commands: [[String]] = []
        let prepared = try ShelfRemoteFiles.prepare([local.path, "one:file.txt", "two:file.txt", "one:file.txt"],
            relativeTo: root, root: root.appendingPathComponent("downloads"), runSCP: { args in
                commands.append(args)
                let url = URL(fileURLWithPath: args.last!).appendingPathComponent("file.txt")
                try Data(args[2].utf8).write(to: url)
                return 0
            })
        XCTAssertEqual(prepared.urls.count, 3)
        XCTAssertEqual(prepared.urls.first, local)
        XCTAssertEqual(prepared.temporaryURLs.count, 2)
        XCTAssertNotEqual(prepared.temporaryURLs[0], prepared.temporaryURLs[1])
        XCTAssertEqual(try String(contentsOf: prepared.temporaryURLs[0]), "one:file.txt")
        XCTAssertEqual(try String(contentsOf: prepared.temporaryURLs[1]), "two:file.txt")
        XCTAssertEqual(commands.map { Array($0.prefix(2)) }, [["-r", "--"], ["-r", "--"]])
        prepared.discard()
        XCTAssertTrue(FileManager.default.fileExists(atPath: local.path))
        XCTAssertTrue(prepared.temporaryURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    func testFailureOrCancellationRemovesAllPartialTransfers() throws {
        for interrupted in [false, true] {
            let root = try fixture()
            defer { try? FileManager.default.removeItem(at: root) }
            let downloads = root.appendingPathComponent("downloads")
            var count = 0
            XCTAssertThrowsError(try ShelfRemoteFiles.prepare(["host:first", "host:second"], relativeTo: root,
                root: downloads, runSCP: { args in
                    count += 1
                    try Data("partial".utf8).write(to: URL(fileURLWithPath: args.last!).appendingPathComponent("file"))
                    if count == 2, interrupted { throw ShelfRemoteFiles.ImportError.interrupted(SIGINT) }
                    return count == 1 ? 0 : 1
                }))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: downloads.path).isEmpty)
        }
    }

    func testUnsafeStorageAndSymlinkedResultsAreRejected() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        var called = false
        XCTAssertThrowsError(try ShelfRemoteFiles.prepare(["host:file"], relativeTo: root, root: link,
            runSCP: { _ in called = true; return 0 }))
        XCTAssertFalse(called)
        let original = root.appendingPathComponent("original")
        try Data("keep".utf8).write(to: original)
        XCTAssertThrowsError(try ShelfRemoteFiles.prepare(["host:file"], relativeTo: root,
            root: root.appendingPathComponent("downloads"), runSCP: { args in
                try FileManager.default.createSymbolicLink(at: URL(fileURLWithPath: args.last!).appendingPathComponent("file"),
                    withDestinationURL: original)
                return 0
            }))
        XCTAssertEqual(try String(contentsOf: original), "keep")
    }

    func testRealSCPDownloadsFileAndDirectoryWithoutChangingSources() throws {
        // Actual macOS scp/SFTP, using a local protocol server over pipes: no
        // network, SSH credentials, known_hosts changes, or external host.
        guard FileManager.default.isExecutableFile(atPath: "/usr/libexec/sftp-server") else {
            throw XCTSkip("macOS SFTP test server unavailable")
        }
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source folder")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let file = source.appendingPathComponent("name ; literal.txt")
        try Data("unchanged remote bytes".utf8).write(to: file)
        let prepared = try ShelfRemoteFiles.prepare(["fixture:\(file.path)", "fixture:\(source.path)"], relativeTo: root,
            root: root.appendingPathComponent("downloads"), runSCP: { args in
                try ShelfRemoteFiles.runSCP(["-D", "/usr/libexec/sftp-server"] + args)
            })
        XCTAssertEqual(prepared.temporaryURLs.count, 2)
        XCTAssertEqual(try Data(contentsOf: prepared.urls[0]), try Data(contentsOf: file))
        XCTAssertEqual(try Data(contentsOf: prepared.urls[1].appendingPathComponent(file.lastPathComponent)),
                       try Data(contentsOf: file))
        prepared.discard()
        XCTAssertEqual(try String(contentsOf: file), "unchanged remote bytes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenShelfRemoteTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return root
    }
}
