import AppKit
import Foundation

final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    func add(url: URL) {
        guard !items.contains(where: { $0.url == url }) else {
            return
        }

        items.append(ShelfItem(url: url))
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    func quickLook(_ item: ShelfItem) {
        QuickLookPreviewer.shared.preview(url: item.url)
    }

    func revealInFinder(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func copyPath(_ item: ShelfItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.url.path, forType: .string)
    }

    func clear() {
        items.removeAll()
    }
}
