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

    /// Another application can order its own floating window (picture in
    /// picture, call controls, another utility) above the shelf without
    /// activating or receiving a click, so no notification fires and the
    /// panel's own flags stay healthy. Ask WindowServer what is above it.
    static func isCoveredByOtherApplication(_ panel: NSPanel) -> Bool {
        guard panel.isVisible, panel.windowNumber > 0,
            let primaryScreen = NSScreen.screens.first
        else { return false }
        let windowsAbove = CGWindowListCopyWindowInfo(
            [.optionOnScreenAboveWindow, .excludeDesktopElements],
            CGWindowID(panel.windowNumber)
        ) as? [[String: Any]] ?? []
        return isCovered(frame: panel.frame, level: panel.level, by: windowsAbove,
                         ownProcessID: getpid(), primaryScreenMaxY: primaryScreen.frame.maxY)
    }

    /// Only windows at or below the shelf's level count: reordering cannot
    /// win against a higher level and would just reorder on every heartbeat.
    static func isCovered(
        frame: NSRect, level: NSWindow.Level, by windowsAbove: [[String: Any]],
        ownProcessID: pid_t, primaryScreenMaxY: CGFloat
    ) -> Bool {
        windowsAbove.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) != ownProcessID,
                let layer = window[kCGWindowLayer as String] as? Int, layer <= level.rawValue,
                (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
            else { return false }
            // CoreGraphics bounds use a top-left origin on the primary display.
            let appKitBounds = NSRect(x: bounds.minX, y: primaryScreenMaxY - bounds.maxY,
                                      width: bounds.width, height: bounds.height)
            return !appKitBounds.intersection(frame).isEmpty
        }
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
