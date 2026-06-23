import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let shelfController = FloatingShelfController()
    private var edgeTriggerController: EdgeTriggerController?
    private var commandReceiver: ShelfCommandReceiver?

    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar utility app.
        // This prevents OpenShelf from appearing as a normal Dock app.
        NSApp.setActivationPolicy(.accessory)

        setupMenuBarItem()
        commandReceiver = ShelfCommandReceiver(
            shelfController: shelfController
        )

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
                title: "Install CLI Tool…",
                action: #selector(installCLITool),
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

    @objc private func installCLITool() {
        guard let cliURL = bundledCLIURL() else {
            showAlert(
                title: "CLI Tool Not Found",
                message: "OpenShelf could not find the bundled shelf command."
            )
            return
        }

        let destinationPath = "/usr/local/bin/shelf"
        let command = [
            "/bin/mkdir -p /usr/local/bin",
            "/bin/ln -sf \(shellQuoted(cliURL.path)) \(shellQuoted(destinationPath))",
        ].joined(separator: " && ")

        let script = """
        do shell script \(appleScriptQuoted(command)) with administrator privileges
        """

        var errorInfo: NSDictionary?
        NSAppleScript(source: script)?
            .executeAndReturnError(&errorInfo)

        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String
                ?? "The CLI tool could not be installed."

            showAlert(
                title: "CLI Install Failed",
                message: message
            )
            return
        }

        showAlert(
            title: "CLI Tool Installed",
            message: "You can now run shelf <file-or-folder> from Terminal."
        )
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func bundledCLIURL() -> URL? {
        let bundledURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent("shelf")

        if FileManager.default.isExecutableFile(atPath: bundledURL.path) {
            return bundledURL
        }

        // Development fallback for `swift run`.
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let debugURL = sourceRoot
            .appendingPathComponent(".build")
            .appendingPathComponent("debug")
            .appendingPathComponent("shelf")

        if FileManager.default.isExecutableFile(atPath: debugURL.path) {
            return debugURL
        }

        return nil
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appleScriptQuoted(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
