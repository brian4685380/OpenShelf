import AppKit
import XCTest
@testable import OpenShelf

@MainActor
final class AppDelegateTests: XCTestCase {
    func testMenuBarIconLoadsTheProjectAppIconAsset() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let expectedURL = projectRoot
            .appendingPathComponent("Assets")
            .appendingPathComponent("AppIcon.png")
        let expectedImage = try XCTUnwrap(NSImage(contentsOf: expectedURL))
        let actualImage = try XCTUnwrap(AppDelegate().menuBarIcon())

        XCTAssertEqual(actualImage.size, expectedImage.size)
        XCTAssertEqual(
            actualImage.tiffRepresentation,
            expectedImage.tiffRepresentation
        )
    }
}
