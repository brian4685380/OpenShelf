import AppKit

/// Opt-in metadata for fullscreen bugs. Never records shelf paths or the
/// titles/content of another application's windows.
@MainActor
enum ShelfWindowDiagnostics {
    private static let enabled = ProcessInfo.processInfo.environment["OPENSHELF_WINDOW_DIAGNOSTICS"] == "1"
    private static var previous = ""

    static func record(shelves: [FloatingShelfController]) {
        guard enabled else { return }
        let onScreenWindows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let onScreenIDs = Set(onScreenWindows.compactMap { $0[kCGWindowNumber as String] as? Int })
        let foreground = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        let panels = NSApp.windows.compactMap { $0 as? NSPanel }.sorted { $0.windowNumber < $1.windowNumber }
        let state = "foreground=\(foreground) appKitButtons=\(NSEvent.pressedMouseButtons) "
            + "sessionLeft=\(CGEventSource.buttonState(.combinedSessionState, button: .left)) "
            + shelves.map(\.windowDiagnosticState).joined(separator: "; ") + " " + panels.map { panel in
            let role = panel is ShelfPanel ? "shelf" : "capture/trigger"
            return "\(role)#\(panel.windowNumber) visible=\(panel.isVisible) activeSpace=\(panel.isOnActiveSpace) "
                + "onscreen=\(onScreenIDs.contains(panel.windowNumber)) occluded=\(!panel.occlusionState.contains(.visible)) "
                + "level=\(panel.level.rawValue) behavior=\(panel.collectionBehavior.rawValue) frame=\(panel.frame)"
        }.joined(separator: "; ")
        guard state != previous else { return }
        previous = state
        print("Window diagnostic:", state)
        fflush(stdout)
    }
}
