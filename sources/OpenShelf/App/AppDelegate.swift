import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let shelfController = FloatingShelfController()
    private var edgeTriggerController: EdgeTriggerController?

    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar utility app.
        // This prevents OpenShelf from appearing as a normal Dock app.
        NSApp.setActivationPolicy(.accessory)

        setupMenuBarItem()

        let triggerController = EdgeTriggerController(
            shelfController: shelfController
        )

        triggerController.start()
        edgeTriggerController = triggerController

        print("OpenShelf is running as a menu bar app.")
        print("Drag a file to the left or right edge of the screen.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        edgeTriggerController?.stop()
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        edgeTriggerController?.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupMenuBarItem() {
        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )

        if let button = item.button {
            let image = menuBarIcon()
            image?.size = NSSize(width: 18, height: 18)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = "OpenShelf"
        }

        let menu = NSMenu()

        menu.addItem(
            NSMenuItem(
                title: "Show / Hide Shelf",
                action: #selector(toggleShelf),
                keyEquivalent: ""
            )
        )

        menu.addItem(
            NSMenuItem(
                title: "Clear Shelf",
                action: #selector(clearShelf),
                keyEquivalent: ""
            )
        )

        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            NSMenuItem(
                title: "Quit OpenShelf",
                action: #selector(quit),
                keyEquivalent: "q"
            )
        )

        item.menu = menu
        statusItem = item
    }

    private func menuBarIcon() -> NSImage? {
        let bundledIconURLs = [
            Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
            Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
        ]

        for case let iconURL? in bundledIconURLs {
            if let image = NSImage(contentsOf: iconURL) {
                return image
            }
        }

        // `swift run` does not create an app bundle, so load the same source
        // asset directly while developing from this repository.
        let sourceTreeIconURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Assets/AppIcon.png")

        return NSImage(contentsOf: sourceTreeIconURL)
    }

    @objc private func toggleShelf() {
        shelfController.toggleShelf()
    }

    @objc private func clearShelf() {
        shelfController.clearShelf()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
