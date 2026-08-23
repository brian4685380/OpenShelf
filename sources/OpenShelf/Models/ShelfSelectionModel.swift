import AppKit

@MainActor
final class ShelfSelectionModel: ObservableObject {
    @Published private(set) var itemIDs: Set<ShelfItem.ID>
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
    }

    func replace(
        with itemIDs: Set<ShelfItem.ID>,
        anchorItemID: ShelfItem.ID?
    ) {
        self.itemIDs = itemIDs
        if let anchorItemID, itemIDs.contains(anchorItemID) {
            self.anchorItemID = anchorItemID
        } else {
            self.anchorItemID = nil
        }
    }

    func clear() {
        itemIDs = []
        anchorItemID = nil
    }

    func subtract(_ removedItemIDs: [ShelfItem.ID]) {
        itemIDs.subtract(removedItemIDs)

        if let anchorItemID, !itemIDs.contains(anchorItemID) {
            self.anchorItemID = nil
        }
    }

    func prune(to items: [ShelfItem]) {
        let validItemIDs = Set(items.map(\.id))
        itemIDs.formIntersection(validItemIDs)

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
