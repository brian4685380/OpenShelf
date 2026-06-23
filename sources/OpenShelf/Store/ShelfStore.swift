import AppKit
import Foundation

@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    private var fileMonitors: [UUID: FileExistenceMonitor] = [:]

    func add(url: URL) {
        let normalizedURL = url.standardizedFileURL

        guard
            FileManager.default.fileExists(
                atPath: normalizedURL.path
            )
        else {
            print("Cannot add missing file:", normalizedURL.path)
            return
        }

        guard
            !items.contains(where: {
                $0.url.standardizedFileURL == normalizedURL
            })
        else {
            return
        }

        let item = ShelfItem(url: normalizedURL)

        items.append(item)
        startMonitoring(item)

        /*
         Protect against the file being deleted between the initial
         fileExists check and monitor creation.
        */
        removeIfMissing(item)
    }

    func remove(_ item: ShelfItem) {
        fileMonitors.removeValue(forKey: item.id)?.stop()
        items.removeAll { $0.id == item.id }
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
        items.removeAll()
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
}
