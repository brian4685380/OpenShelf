import AppKit
import SwiftUI

@MainActor
final class ShelfDropState: ObservableObject {
    struct Feedback: Equatable {
        let id = UUID()
        let message: String
        let systemImage: String
        let isError: Bool

        static func == (lhs: Feedback, rhs: Feedback) -> Bool {
            lhs.id == rhs.id
        }
    }

    @Published private(set) var isTargeted = false
    @Published private(set) var successfulDropGeneration: UInt = 0
    @Published private(set) var feedback: Feedback?

    private var feedbackDismissal: DispatchWorkItem?

    func setTargeted(_ isTargeted: Bool) {
        self.isTargeted = isTargeted

        if isTargeted {
            feedbackDismissal?.cancel()
            feedback = nil
        }
    }

    func report(_ outcome: ShelfImportOutcome) {
        feedbackDismissal?.cancel()

        if outcome.addedCount > 0 {
            successfulDropGeneration &+= 1

            let noun = outcome.addedCount == 1 ? "item" : "items"
            feedback = Feedback(
                message: "Added \(outcome.addedCount) \(noun)",
                systemImage: "checkmark.circle.fill",
                isError: false
            )
        } else if outcome.skippedCount > 0 {
            feedback = Feedback(
                message: "Already on the shelf",
                systemImage: "equal.circle.fill",
                isError: false
            )
        } else {
            NSSound.beep()
            feedback = Feedback(
                message: "This content couldn’t be added",
                systemImage: "exclamationmark.triangle.fill",
                isError: true
            )
        }

        let feedbackID = feedback?.id
        let workItem = DispatchWorkItem { [weak self] in
            guard self?.feedback?.id == feedbackID else {
                return
            }

            self?.feedback = nil
        }
        feedbackDismissal = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 1.8,
            execute: workItem
        )
    }
}
