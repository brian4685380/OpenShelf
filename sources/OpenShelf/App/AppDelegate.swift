import AppKit
import Darwin
import ShelfCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private lazy var shelfManager = ShelfManager()
    private let shelvesMenu = NSMenu(title: "Shelves")
    private var edgeTriggerController: EdgeTriggerController?
    private var commandReceiver: ShelfCommandReceiver?
    private var floatingRefreshWorkItems: [DispatchWorkItem] = []
    private var floatingWindowMaintenanceTimer: Timer?
    private var globalMouseUpMonitor: Any?

    private var statusItem: NSStatusItem?
    private var instanceLockFileDescriptor: Int32 = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard acquireSingleInstanceLock() else {
            print("Another OpenShelf instance is already running.")
            NSApp.terminate(nil)
            return
        }

        // Menu bar utility app.
        // This prevents OpenShelf from appearing as a normal Dock app.
        NSApp.setActivationPolicy(.accessory)

        // Register hidden native destinations before Finder starts a drag.
        _ = shelfManager
        setupMenuBarItem()
        commandReceiver = ShelfCommandReceiver(
            addFiles: { [weak self] in self?.shelfManager.addAndShow(urls: $0) }
        )
        commandReceiver?.processPendingRequests()

        let triggerController = EdgeTriggerController(
            shelfProvider: { [weak self] screen, edge, y in
                self?.shelfManager.shelfForEdge(on: screen, edge: edge, triggerY: y)
            }
        )

        triggerController.start()
        edgeTriggerController = triggerController
        observeWorkspaceChanges()
        startFloatingWindowMaintenance()

        print("OpenShelf is running as a menu bar app.")
        print("Drag a file to the left or right edge of the screen.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        shelfManager.prepareForTermination()
        floatingRefreshWorkItems.forEach { $0.cancel() }
        floatingRefreshWorkItems.removeAll()
        stopFloatingWindowMaintenance()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        edgeTriggerController?.stop()

        if instanceLockFileDescriptor >= 0 {
            flock(instanceLockFileDescriptor, LOCK_UN)
            close(instanceLockFileDescriptor)
            instanceLockFileDescriptor = -1
        }
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        edgeTriggerController?.screenParametersDidChange()
        shelfManager.shelves.forEach { $0.screenParametersDidChange() }
        refreshFloatingWindows()
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
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "New Shelf", action: #selector(newShelf), keyEquivalent: "n"))
        let shelvesItem = NSMenuItem(title: "Shelves", action: nil, keyEquivalent: "")
        shelvesItem.submenu = shelvesMenu
        menu.addItem(shelvesItem)
        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            NSMenuItem(
                title: "Show / Hide Active Shelf",
                action: #selector(toggleShelf),
                keyEquivalent: ""
            )
        )

        menu.addItem(
            NSMenuItem(
                title: "Clear Active Shelf",
                action: #selector(clearShelf),
                keyEquivalent: ""
            )
        )

        menu.addItem(NSMenuItem(title: "Remove Active Shelf…", action: #selector(removeActiveShelf), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            NSMenuItem(
                title: "Install CLI Tool…",
                action: #selector(installCLITool),
                keyEquivalent: ""
            )
        )

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Keyboard Shortcuts…", action: #selector(showKeyboardShortcuts), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "About OpenShelf", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            NSMenuItem(
                title: "Quit OpenShelf",
                action: #selector(quit),
                keyEquivalent: "q"
            )
        )

        item.menu = menu
        for menuItem in menu.items where menuItem.action != nil { menuItem.target = self }
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        shelvesMenu.removeAllItems()
        for shelf in shelfManager.shelves {
            let hidden = shelf.visibleShelfFrame() == nil ? " · hidden" : ""
            let count = shelf.store.items.count
            let preview = shelf.store.items.first.map { " — \($0.url.lastPathComponent)" } ?? ""
            let item = NSMenuItem(title: "\(shelf.name)\(preview) · \(count) \(count == 1 ? "item" : "items")\(hidden)",
                                 action: #selector(showShelf(_:)), keyEquivalent: "")
            item.representedObject = shelf.id
            item.state = shelf === shelfManager.activeShelf ? .on : .off
            item.target = self
            shelvesMenu.addItem(item)
        }
    }

    @objc private func newShelf() { shelfManager.createShelf() }

    @objc private func showShelf(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
            let shelf = shelfManager.shelves.first(where: { $0.id == id }) else { return }
        shelfManager.show(shelf)
    }

    @objc private func removeActiveShelf() {
        guard let shelf = shelfManager.activeShelf else { return }
        if !shelf.store.items.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Remove \(shelf.name)?"
            alert.informativeText = "This removes its staged entries and temporary clips. Original files are not deleted. Hide the shelf instead to keep its contents."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Remove Shelf")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        shelfManager.remove(shelf)
    }

    @objc private func showKeyboardShortcuts() {
        let alert = NSAlert()
        alert.messageText = "Make room for your next move."
        alert.informativeText = """
        Hover over the shelf to use these shortcuts:

        ⌘N                     Create a new independent shelf
        ↑ / ↓                  Select previous / next item
        ⇧↑ / ⇧↓              Extend or shrink selection
        ⌘A                     Select all
        ⌘C                     Copy selected files
        ⌥⌘C                  Copy selected paths
        ⌘V                     Paste content onto the shelf
        Space                 Quick Look
        Return / ⌘O       Open selected files
        Delete                 Remove from shelf (not the originals)
        ⌘P                     Pin / unpin the expanded shelf
        Escape               Clear selection, then close the shelf

        Drag from blank space to select. Drag rows to reorder;
        continue past any shelf edge to drag them into another app.
        """
        alert.addButton(withTitle: "Got it")
        alert.runModal()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "OpenShelf \(OpenShelfVersion.current)"
        alert.informativeText = "A little space between pick up and put down.\n\nNative macOS. Local by design. MIT licensed.\n© 2026 Brian Yuan"
        alert.addButton(withTitle: "Done")
        alert.addButton(withTitle: "View on GitHub")
        if alert.runModal() == .alertSecondButtonReturn,
            let url = URL(string: "https://github.com/brian4685380/OpenShelf") {
            NSWorkspace.shared.open(url)
        }
    }

    private func acquireSingleInstanceLock() -> Bool {
        let lockPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "com.brianyuan.OpenShelf.\(getuid()).lock"
            )
            .path
        let descriptor = open(
            lockPath,
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR
        )

        guard descriptor >= 0 else {
            print("Could not create OpenShelf instance lock:", lockPath)
            return false
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return false
        }

        instanceLockFileDescriptor = descriptor
        return true
    }

    private func observeWorkspaceChanges() {
        let notificationCenter = NSWorkspace.shared.notificationCenter

        notificationCenter.addObserver(
            self,
            selector: #selector(refreshFloatingWindows),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(refreshFloatingWindows),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        for name in [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ] {
            notificationCenter.addObserver(
                self,
                selector: #selector(refreshFloatingWindows),
                name: name,
                object: nil
            )
        }
    }

    private func startFloatingWindowMaintenance() {
        stopFloatingWindowMaintenance()

        let timer = Timer(
            timeInterval: 0.35,
            target: self,
            selector: #selector(maintainFloatingWindows),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        floatingWindowMaintenanceTimer = timer

        // NSWorkspace reports application and Space changes, but not a new
        // foreground window or tab inside the same application. Refresh as
        // soon as a click that may have changed that foreground surface ends.
        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp, .otherMouseUp]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshFloatingWindowsNow()
            }
        }
    }

    private func stopFloatingWindowMaintenance() {
        floatingWindowMaintenanceTimer?.invalidate()
        floatingWindowMaintenanceTimer = nil

        if let globalMouseUpMonitor {
            NSEvent.removeMonitor(globalMouseUpMonitor)
            self.globalMouseUpMonitor = nil
        }
    }

    func menuBarIcon() -> NSImage? {
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
        shelfManager.activeShelf.toggleShelf()
    }

    @objc private func clearShelf() {
        shelfManager.activeShelf.clearShelf()
    }

    @objc private func refreshFloatingWindows() {
        floatingRefreshWorkItems.forEach { $0.cancel() }
        floatingRefreshWorkItems.removeAll()

        refreshFloatingWindowsNow()

        // A native fullscreen transition moves windows between Spaces
        // asynchronously. Refresh a few times while that animation settles so
        // the shelf and its edge triggers join the newly active fullscreen
        // Space instead of remaining behind the fullscreen application.
        for delay in [0.15, 0.45, 0.9] {
            let workItem = DispatchWorkItem { [weak self] in
                self?.refreshFloatingWindowsNow()
            }

            floatingRefreshWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(
                deadline: .now() + delay,
                execute: workItem
            )
        }
    }

    @objc private func maintainFloatingWindows() {
        refreshEdgeTriggersNow()
        shelfManager.shelves.forEach { $0.maintainAlwaysOnTop() }
        shelfManager.prepareNextShelf()
        commandReceiver?.processPendingRequests()
    }

    private func refreshFloatingWindowsNow() {
        refreshEdgeTriggersNow()
        // Restore the active shelf last so its capture window cannot end up
        // underneath another shelf's invisible destination.
        shelfManager.shelves.filter { $0 !== shelfManager.activeShelf }.forEach { $0.refreshAlwaysOnTop() }
        shelfManager.activeShelf.refreshAlwaysOnTop()
    }

    private func refreshEdgeTriggersNow() {
        edgeTriggerController?.refresh()
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
