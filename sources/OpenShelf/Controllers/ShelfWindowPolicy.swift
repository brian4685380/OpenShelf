import AppKit

@MainActor
enum ShelfWindowPolicy {
    // Higher levels such as .screenSaver can break cross-process Finder
    // drops. Space membership must be fixed independently of window level.
    static let level = NSWindow.Level.floating
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .canJoinAllApplications,
        .fullScreenAuxiliary,
        .stationary,
        .ignoresCycle,
    ]

    static func apply(to panel: NSPanel) {
        // Changing isFloatingPanel can reset the level. Avoid reapplying
        // unchanged collection flags during maintenance: WindowServer owns
        // Space membership and should not be disturbed during a transition.
        if !panel.isFloatingPanel { panel.isFloatingPanel = true }
        if panel.level != level { panel.level = level }
        panel.hidesOnDeactivate = false
        if panel.collectionBehavior != collectionBehavior {
            panel.collectionBehavior = collectionBehavior
        }
    }

    static func needsRecovery(_ panel: NSPanel) -> Bool {
        !panel.isVisible || !panel.isOnActiveSpace
            || !panel.isFloatingPanel || panel.level != level
            || panel.hidesOnDeactivate || panel.collectionBehavior != collectionBehavior
    }

    /// Call only when no native drag is in progress. Ordering an already
    /// ordered-in window frontmost does not repair stale Space membership.
    /// Temporarily move an affected panel to the current Space, then restore
    /// its all-Spaces role. Never activate the application or make it key.
    static func orderOnActiveSpace(_ panel: NSPanel, below parent: NSPanel? = nil) {
        apply(to: panel)
        let mustRejoinSpace = !panel.isOnActiveSpace
        if mustRejoinSpace {
            print("Recovering floating window on active Space:", panel.title)
            panel.orderOut(nil)
            // These two flags are mutually exclusive. Keep the fullscreen /
            // all-applications roles throughout the recovery.
            panel.collectionBehavior = collectionBehavior
                .subtracting(.canJoinAllSpaces).union(.moveToActiveSpace)
        }

        if let parent {
            panel.order(.below, relativeTo: parent.windowNumber)
        } else {
            panel.orderFrontRegardless()
        }

        if mustRejoinSpace { apply(to: panel) }
    }
}
