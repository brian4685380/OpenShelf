import AppKit
import Foundation

struct ShelfImportOutcome {
    let addedCount: Int
    let skippedCount: Int
}

@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    private var fileMonitors: [UUID: FileExistenceMonitor] = [:]
    private let contentImporter = ShelfContentImporter()

    @discardableResult
    func add(
        url: URL,
        isManagedByShelf: Bool = false
    ) -> Bool {
        let normalizedURL = url.standardizedFileURL

        guard
            FileManager.default.fileExists(
                atPath: normalizedURL.path
            )
        else {
            print("Cannot add missing file:", normalizedURL.path)
            return false
        }

        guard
            !items.contains(where: {
                $0.url.standardizedFileURL == normalizedURL
            })
        else {
            return false
        }

        let item = ShelfItem(
            url: normalizedURL,
            isManagedByShelf: isManagedByShelf
        )

        items.append(item)
        startMonitoring(item)

        /*
         Protect against the file being deleted between the initial
         fileExists check and monitor creation.
        */
        removeIfMissing(item)
        return items.contains(item)
    }

    func remove(_ item: ShelfItem) {
        fileMonitors.removeValue(forKey: item.id)?.stop()
        items.removeAll { $0.id == item.id }

        if item.isManagedByShelf {
            removeManagedContent(at: item.url)
        }
    }

    func remove(_ items: [ShelfItem]) {
        for item in items {
            remove(item)
        }
    }

    func move(_ movingItems: [ShelfItem], to targetItem: ShelfItem) {
        let movingItemIDs = Set(movingItems.map(\.id))

        guard
            !movingItemIDs.isEmpty,
            !movingItemIDs.contains(targetItem.id),
            let targetIndex = items.firstIndex(of: targetItem),
            let firstMovingIndex = items.firstIndex(where: {
                movingItemIDs.contains($0.id)
            })
        else {
            return
        }

        let orderedMovingItems = items.filter {
            movingItemIDs.contains($0.id)
        }
        var remainingItems = items.filter {
            !movingItemIDs.contains($0.id)
        }

        guard let insertionTargetIndex = remainingItems.firstIndex(
            of: targetItem
        ) else {
            return
        }

        let insertionIndex = firstMovingIndex < targetIndex
            ? insertionTargetIndex + 1
            : insertionTargetIndex

        remainingItems.insert(
            contentsOf: orderedMovingItems,
            at: insertionIndex
        )

        items = remainingItems
    }

    func open(_ item: ShelfItem) {
        guard fileExists(item) else {
            remove(item)
            return
        }

        NSWorkspace.shared.open(item.url)
    }

    func open(_ items: [ShelfItem]) {
        for item in items {
            open(item)
        }
    }

    func quickLook(_ item: ShelfItem) {
        guard fileExists(item) else {
            remove(item)
            return
        }

        QuickLookPreviewer.shared.preview(url: item.url)
    }

    func quickLook(_ items: [ShelfItem]) {
        let existingItems = items.filter { item in
            if fileExists(item) {
                return true
            }

            remove(item)
            return false
        }

        QuickLookPreviewer.shared.preview(
            urls: existingItems.map(\.url)
        )
    }

    func revealInFinder(_ item: ShelfItem) {
        guard fileExists(item) else {
            remove(item)
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([
            item.url
        ])
    }

    func revealInFinder(_ items: [ShelfItem]) {
        let existingItems = items.filter { item in
            if fileExists(item) {
                return true
            }

            remove(item)
            return false
        }

        NSWorkspace.shared.activateFileViewerSelecting(
            existingItems.map(\.url)
        )
    }

    func copyPath(_ item: ShelfItem) {
        guard fileExists(item) else {
            remove(item)
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            item.url.path,
            forType: .string
        )
    }

    func copyPath(_ items: [ShelfItem]) {
        let existingItems = items.filter { item in
            if fileExists(item) {
                return true
            }

            remove(item)
            return false
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            existingItems.map(\.url.path).joined(separator: "\n"),
            forType: .string
        )
    }

    func clear() {
        for monitor in fileMonitors.values {
            monitor.stop()
        }

        fileMonitors.removeAll()

        for item in items where item.isManagedByShelf {
            removeManagedContent(at: item.url)
        }

        items.removeAll()
    }

    @discardableResult
    func importItemProviders(
        _ providers: [NSItemProvider],
        onImported: ((ShelfImportOutcome) -> Void)? = nil
    ) -> Bool {
        contentImporter.importItemProviders(providers) { [weak self] contents in
            guard let self else { return }

            var addedCount = 0

            for content in contents {
                if self.add(
                    url: content.url,
                    isManagedByShelf: content.isManagedByShelf
                ) {
                    addedCount += 1
                }

                print("Added content to shelf:", content.url.path)
            }

            onImported?(
                ShelfImportOutcome(
                    addedCount: addedCount,
                    skippedCount: contents.count - addedCount
                )
            )
        }
    }

    @discardableResult
    func importDroppedPasteboard(
        _ pasteboard: NSPasteboard,
        onImported: @escaping (ShelfImportOutcome) -> Void
    ) -> Bool {
        contentImporter.importDroppedPasteboard(pasteboard) {
            [weak self] contents in
            guard let self else { return }

            var addedCount = 0

            for content in contents {
                if self.add(
                    url: content.url,
                    isManagedByShelf: content.isManagedByShelf
                ) {
                    addedCount += 1
                    print("Dropped content onto shelf:", content.url.path)
                }
            }

            onImported(
                ShelfImportOutcome(
                    addedCount: addedCount,
                    skippedCount: contents.count - addedCount
                )
            )
        }
    }

    @discardableResult
    func importPasteboard(
        _ pasteboard: NSPasteboard = .general
    ) -> Bool {
        let contents = contentImporter.importPasteboard(pasteboard)

        guard !contents.isEmpty else {
            NSSound.beep()
            return false
        }

        var addedCount = 0

        for content in contents {
            if add(
                url: content.url,
                isManagedByShelf: content.isManagedByShelf
            ) {
                addedCount += 1
            }

            print("Pasted content onto shelf:", content.url.path)
        }

        guard addedCount > 0 else {
            NSSound.beep()
            return false
        }

        return true
    }

    private func startMonitoring(_ item: ShelfItem) {
        let monitor = FileExistenceMonitor(
            url: item.url
        ) { [weak self] in
            guard let self else { return }

            Task { @MainActor in
                self.removeIfMissing(item)
            }
        }

        guard let monitor else {
            /*
             The file may already have disappeared before monitoring
             could start.
            */
            removeIfMissing(item)
            return
        }

        fileMonitors[item.id] = monitor
    }

    private func removeIfMissing(_ item: ShelfItem) {
        guard !fileExists(item) else {
            return
        }

        print(
            "File no longer exists; removing from shelf:",
            item.url.path
        )

        remove(item)
    }

    private func fileExists(_ item: ShelfItem) -> Bool {
        FileManager.default.fileExists(
            atPath: item.url.path
        )
    }

    private func removeManagedContent(at url: URL) {
        try? FileManager.default.removeItem(at: url)

        let parentDirectory = url.deletingLastPathComponent()

        if let remainingContents = try? FileManager.default.contentsOfDirectory(
            at: parentDirectory,
            includingPropertiesForKeys: nil
        ),
            remainingContents.isEmpty
        {
            try? FileManager.default.removeItem(at: parentDirectory)
        }
    }
}
