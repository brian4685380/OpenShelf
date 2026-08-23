import XCTest
@testable import OpenShelf

@MainActor
final class ShelfDropStateTests: XCTestCase {
    func testAddedDuplicateAndUnsupportedFeedbackAreDistinct() throws {
        let state = ShelfDropState()

        state.report(ShelfImportOutcome(addedCount: 2, skippedCount: 0))

        XCTAssertEqual(state.successfulDropGeneration, 1)
        XCTAssertEqual(state.feedback?.message, "Added 2 items")
        XCTAssertEqual(state.feedback?.systemImage, "checkmark.circle.fill")
        XCTAssertFalse(try XCTUnwrap(state.feedback).isError)

        state.report(ShelfImportOutcome(addedCount: 0, skippedCount: 1))

        XCTAssertEqual(state.successfulDropGeneration, 1)
        XCTAssertEqual(state.feedback?.message, "Already on the shelf")
        XCTAssertFalse(try XCTUnwrap(state.feedback).isError)

        state.report(ShelfImportOutcome(addedCount: 0, skippedCount: 0))

        XCTAssertEqual(state.successfulDropGeneration, 1)
        XCTAssertEqual(state.feedback?.message, "This content couldn’t be added")
        XCTAssertTrue(try XCTUnwrap(state.feedback).isError)
    }

    func testEnteringDropTargetClearsOldFeedback() {
        let state = ShelfDropState()
        state.report(ShelfImportOutcome(addedCount: 1, skippedCount: 0))

        state.setTargeted(true)

        XCTAssertTrue(state.isTargeted)
        XCTAssertNil(state.feedback)
    }
}
