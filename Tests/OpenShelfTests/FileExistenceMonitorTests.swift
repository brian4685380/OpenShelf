import AppKit
import Darwin
import XCTest
@testable import OpenShelf

@MainActor
final class FileExistenceMonitorTests: XCTestCase {
    func testSlowDescriptorOpenRunsOffMainThreadAndCanBeCancelled() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("fixture".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let opening = expectation(description: "background open started")
        let finished = expectation(description: "background open returned")
        let gate = DispatchSemaphore(value: 0)
        let monitor = FileExistenceMonitor(url: file, openDescriptor: { path in
            XCTAssertFalse(Thread.isMainThread, "Descriptor setup must never stall the UI thread.")
            opening.fulfill()
            _ = gate.wait(timeout: .now() + 3)
            let descriptor = open(path, O_EVTONLY)
            finished.fulfill()
            return descriptor
        }, onUnavailable: {})
        wait(for: [opening], timeout: 3)
        // This remains reachable while openDescriptor is blocked.
        monitor.stop()
        gate.signal()
        wait(for: [finished], timeout: 3)
        monitor.stop() // Repeated cancellation is safe.
    }

    func testFailedBackgroundOpenReportsBackOnMainThread() {
        let callback = expectation(description: "failed open callback")
        let monitor = FileExistenceMonitor(url: URL(fileURLWithPath: "/nonexistent"),
            openDescriptor: { _ in -1 }, onUnavailable: {
                XCTAssertTrue(Thread.isMainThread)
                callback.fulfill()
            })
        withExtendedLifetime(monitor) { wait(for: [callback], timeout: 3) }
    }
}
