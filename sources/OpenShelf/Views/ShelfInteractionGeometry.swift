import AppKit

enum ShelfRowDragIntent: Equatable {
    case pending
    case reorder
    case dragOut
}

enum ShelfInteractionGeometry {
    static let dragStartThreshold: CGFloat = 3
    static let reorderStartThreshold: CGFloat = 8
    static let reorderDominanceRatio: CGFloat = 1.25
    static let reorderCooldown: TimeInterval = 0.12
    static let reorderTargetInset: CGFloat = 8
    static let autoScrollEdgeInset: CGFloat = 30
    static let autoScrollMaxStep: CGFloat = 12
    static let autoScrollInterval: TimeInterval = 1.0 / 30.0

    static func rowDragIntent(
        deltaX: CGFloat,
        deltaY: CGFloat,
        canReorder: Bool
    ) -> ShelfRowDragIntent {
        let absoluteDeltaX = abs(deltaX)
        let absoluteDeltaY = abs(deltaY)

        guard hypot(deltaX, deltaY) >= dragStartThreshold else {
            return .pending
        }

        if canReorder,
            absoluteDeltaY >= reorderStartThreshold,
            absoluteDeltaY > absoluteDeltaX * reorderDominanceRatio
        {
            return .reorder
        }

        if !canReorder
            || absoluteDeltaX >= dragStartThreshold
            || absoluteDeltaX >= absoluteDeltaY
        {
            return .dragOut
        }

        return .pending
    }

    static func autoScrollDelta(
        for point: CGPoint,
        in scrollFrame: CGRect,
        documentIsFlipped: Bool
    ) -> CGFloat? {
        guard scrollFrame.contains(point) else {
            return nil
        }

        let distanceToTop = scrollFrame.maxY - point.y
        let distanceToBottom = point.y - scrollFrame.minY

        let direction: CGFloat
        let edgeDistance: CGFloat

        if distanceToTop < autoScrollEdgeInset {
            direction = documentIsFlipped ? -1 : 1
            edgeDistance = distanceToTop
        } else if distanceToBottom < autoScrollEdgeInset {
            direction = documentIsFlipped ? 1 : -1
            edgeDistance = distanceToBottom
        } else {
            return nil
        }

        let closeness = max(
            0,
            min(1, 1 - edgeDistance / autoScrollEdgeInset)
        )
        let step = max(3, autoScrollMaxStep * closeness)

        return step * direction
    }

    static func marqueeSelectionIDs(
        rowOrder: [ShelfItem.ID],
        rowContentFrames: [ShelfItem.ID: CGRect],
        startContentY: CGFloat,
        currentContentY: CGFloat,
        baseItemIDs: Set<ShelfItem.ID> = []
    ) -> Set<ShelfItem.ID> {
        let minimumY = min(startContentY, currentContentY)
        let maximumY = max(startContentY, currentContentY)

        let rangeItemIDs = Set(
            rowOrder.filter { itemID in
                guard let frame = rowContentFrames[itemID] else {
                    return false
                }

                return frame.maxY >= minimumY && frame.minY <= maximumY
            }
        )

        return baseItemIDs.union(rangeItemIDs)
    }
}
