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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupMenuBarItem() {
        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )

        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "tray",
                accessibilityDescription: "OpenShelf"
            )
            button.image?.isTemplate = true
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
