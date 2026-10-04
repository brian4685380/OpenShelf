import AppKit

@MainActor
final class ShelfSelectionModel: ObservableObject {
    @Published private(set) var itemIDs: Set<ShelfItem.ID>
    @Published private(set) var focusedItemID: ShelfItem.ID?
    @Published private(set) var keyboardNavigationGeneration: UInt = 0
    private(set) var anchorItemID: ShelfItem.ID?

    init(
        itemIDs: Set<ShelfItem.ID> = [],
        anchorItemID: ShelfItem.ID? = nil
    ) {
        self.itemIDs = itemIDs
        if let anchorItemID, itemIDs.contains(anchorItemID) {
            self.anchorItemID = anchorItemID
        } else {
            self.anchorItemID = nil
        }
    }

    func handleClick(
        on item: ShelfItem,
        in items: [ShelfItem],
        modifiers: NSEvent.ModifierFlags
    ) {
        focusedItemID = item.id
        if modifiers.contains(.shift),
            let anchorItemID,
            let anchorIndex = items.firstIndex(where: {
                $0.id == anchorItemID
            }),
            let currentIndex = items.firstIndex(of: item)
        {
            let range = anchorIndex <= currentIndex
                ? anchorIndex...currentIndex
                : currentIndex...anchorIndex
            let rangeIDs = Set(items[range].map(\.id))

            if modifiers.contains(.command) {
                itemIDs.formUnion(rangeIDs)
            } else {
                itemIDs = rangeIDs
            }

            return
        }

        if modifiers.contains(.command) {
            if itemIDs.contains(item.id) {
                itemIDs.remove(item.id)

                if anchorItemID == item.id {
                    self.anchorItemID = items.first(where: {
                        itemIDs.contains($0.id)
                    })?.id
                }
            } else {
                itemIDs.insert(item.id)
                anchorItemID = item.id
            }

            return
        }

        // Preserve a Finder-style group when the user presses a selected row,
        // so a subsequent drag, double-click, or context action uses the whole
        // selection instead of unexpectedly collapsing it first.
        if itemIDs.contains(item.id), itemIDs.count > 1 {
            anchorItemID = item.id
            return
        }

        selectOnly(item)
    }

    func selectOnly(_ item: ShelfItem) {
        itemIDs = [item.id]
        anchorItemID = item.id
        focusedItemID = item.id
    }

    func selectAll(in items: [ShelfItem]) {
        itemIDs = Set(items.map(\.id))
        anchorItemID = items.first?.id
        focusedItemID = items.first?.id
    }

    func navigate(in items: [ShelfItem], direction: Int, extending: Bool) {
        guard !items.isEmpty else { return }
        let currentIndex = items.firstIndex { $0.id == focusedItemID }
            ?? items.firstIndex { itemIDs.contains($0.id) }
        let nextIndex = currentIndex.map {
            min(max($0 + direction, 0), items.count - 1)
        } ?? (direction > 0 ? 0 : items.count - 1)
        let next = items[nextIndex]
        if extending, let anchorItemID,
            let anchorIndex = items.firstIndex(where: { $0.id == anchorItemID }) {
            itemIDs = Set(items[min(anchorIndex, nextIndex)...max(anchorIndex, nextIndex)].map(\.id))
            focusedItemID = next.id
        } else {
            selectOnly(next)
        }
        keyboardNavigationGeneration &+= 1
    }

    func replace(
        with itemIDs: Set<ShelfItem.ID>,
        anchorItemID: ShelfItem.ID?
    ) {
        self.itemIDs = itemIDs
        focusedItemID = anchorItemID
        if let anchorItemID, itemIDs.contains(anchorItemID) {
            self.anchorItemID = anchorItemID
        } else {
            self.anchorItemID = nil
        }
    }

    func clear() {
        itemIDs = []
        anchorItemID = nil
        focusedItemID = nil
    }

    func subtract(_ removedItemIDs: [ShelfItem.ID]) {
        itemIDs.subtract(removedItemIDs)
        if let focusedItemID, removedItemIDs.contains(focusedItemID) {
            self.focusedItemID = nil
        }

        if let anchorItemID, !itemIDs.contains(anchorItemID) {
            self.anchorItemID = nil
        }
    }

    func prune(to items: [ShelfItem]) {
        let validItemIDs = Set(items.map(\.id))
        itemIDs.formIntersection(validItemIDs)
        if let focusedItemID, !validItemIDs.contains(focusedItemID) {
            self.focusedItemID = nil
        }

        if let anchorItemID, !validItemIDs.contains(anchorItemID) {
            self.anchorItemID = items.first(where: {
                itemIDs.contains($0.id)
            })?.id
        }
    }

    func resolvedItems(
        for item: ShelfItem,
        in items: [ShelfItem]
    ) -> [ShelfItem] {
        guard itemIDs.contains(item.id) else {
            return [item]
        }

        let selectedItems = items.filter {
            itemIDs.contains($0.id)
        }

        return selectedItems.isEmpty ? [item] : selectedItems
    }
}
