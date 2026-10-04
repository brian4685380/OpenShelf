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
}
