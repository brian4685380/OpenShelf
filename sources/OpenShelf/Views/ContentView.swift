import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: ShelfStore
    let onHoverChanged: (Bool) -> Void
    let onClose: () -> Void
    let onEmpty: () -> Void
    let onDragOutCompleted: () -> Void
    let onDropTargetChanged: (Bool) -> Void

    @State private var isDropTargeted = false
    @State private var selectedItemIDs: Set<ShelfItem.ID> = []
    @State private var lastSelectedItemID: ShelfItem.ID?
    @State private var reorderedItemIDs: Set<ShelfItem.ID> = []
    @State private var insertionIndicator: ShelfInsertionIndicator?
    @State private var rowFrames: [ShelfItem.ID: CGRect] = [:]

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .opacity(0.45)

            if store.items.isEmpty {
                emptyState
            } else {
                itemList
            }
        }
        .frame(width: 300, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { isHovering in
            onHoverChanged(isHovering)
        }
        .onChange(of: isDropTargeted) { isTargeted in
            onDropTargetChanged(isTargeted)
        }
        .onChange(of: store.items.isEmpty) { isEmpty in
            if isEmpty {
                onEmpty()
            }
        }
        .onChange(of: store.items.map(\.id)) { itemIDs in
            pruneSelection(validItemIDs: Set(itemIDs))
        }
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $isDropTargeted
        ) { providers in
            handleDrop(providers)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                HStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text("OpenShelf")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()
                }
                .allowsHitTesting(false)

                // Covers only the title region.
                WindowDragArea()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 20)

            if !store.items.isEmpty {
                Text("\(store.items.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background {
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                    }

                Button {
                    clearSelection()
                    store.clear()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear shelf")
            }

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .background {
                        Circle()
                            .fill(Color.secondary.opacity(0.10))
                    }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close shelf")
        }
        .frame(height: 20)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Color(nsColor: .windowBackgroundColor)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 58, height: 58)

                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 25, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Text(isDropTargeted ? "Release to add files" : "Drop files here")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Drag files to the screen edge")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)

                if isDropTargeted {
                    Color.accentColor.opacity(0.08)
                }
            }
        }
    }

    private var itemList: some View {
        ZStack {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.items) { item in
                        ShelfRow(
                            item: item,
                            isSelected: selectedItemIDs.contains(item.id),
                            insertionPlacement: insertionPlacement(for: item),
                            dragItems: dragItems(for: item),
                            onDragStarted: {
                                beginReorder(for: item)
                            },
                            onDragCompleted: { operation, draggedItems in
                                if operation.contains(.move) {
                                    print(
                                        "Moved \(draggedItems.count) shelf item(s)."
                                    )
                                } else if operation.contains(.copy) {
                                    print(
                                        "Copied \(draggedItems.count) shelf item(s)."
                                    )
                                }

                                store.remove(draggedItems)
                                selectedItemIDs.subtract(
                                    draggedItems.map(\.id)
                                )
                                onDragOutCompleted()
                            },
                            onDragEnded: {
                                endReorder()
                            },
                            onClick: { modifiers in
                                updateSelection(
                                    for: item,
                                    modifiers: modifiers
                                )
                            },
                            onReorderDropEntered: { movingItems, targetItem in
                                moveReorderedItems(
                                    movingItems,
                                    to: targetItem
                                )
                            },
                            onReorderDropEnded: {
                                endReorder()
                            },
                            onOpen: {
                                store.open(actionItems(for: item))
                            },
                            onQuickLook: {
                                store.quickLook(actionItems(for: item))
                            },
                            onRevealInFinder: {
                                store.revealInFinder(actionItems(for: item))
                            },
                            onCopyPath: {
                                store.copyPath(actionItems(for: item))
                            },
                            onRemove: {
                                let items = actionItems(for: item)
                                store.remove(items)
                                selectedItemIDs.subtract(items.map(\.id))
                            }
                        )
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: ShelfRowFramePreferenceKey.self,
                                    value: [
                                        item.id: proxy.frame(
                                            in: .named("ShelfList")
                                        )
                                    ]
                                )
                            }
                        }
                    }
                }
                .padding(10)
                .animation(
                    .easeInOut(duration: 0.12),
                    value: store.items.map(\.id)
                )
            }

            ShelfSelectionOverlay(
                rowFrames: rowFrames,
                rowOrder: store.items.map(\.id),
                selectedItemIDs: selectedItemIDs,
                onClearSelection: {
                    clearSelection()
                },
                onSelectionChanged: { itemIDs, lastItemID in
                    selectedItemIDs = itemIDs
                    lastSelectedItemID = lastItemID
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .coordinateSpace(name: "ShelfList")
        .onPreferenceChange(ShelfRowFramePreferenceKey.self) { frames in
            rowFrames = frames
        }
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)

                if isDropTargeted {
                    Color.accentColor.opacity(0.08)
                }
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        if providers.contains(where: {
            $0.hasItemConformingToTypeIdentifier(
                shelfReorderPasteboardTypeIdentifier
            )
        }) {
            endReorder()
            return true
        }

        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(
                UTType.fileURL.identifier
            )
        }

        guard !fileProviders.isEmpty else {
            return false
        }

        clearSelection()

        for provider in fileProviders {
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { item, error in
                if let error {
                    print("Drop error:", error)
                    return
                }

                let url: URL?

                switch item {
                case let value as URL:
                    url = value

                case let value as NSURL:
                    url = value as URL

                case let value as Data:
                    url = URL(
                        dataRepresentation: value,
                        relativeTo: nil
                    )

                case let value as String:
                    url = URL(string: value)

                default:
                    url = nil
                }

                guard let url else {
                    print(
                        "Unsupported dropped file representation:",
                        String(describing: type(of: item))
                    )
                    return
                }

                let normalizedURL = url.standardizedFileURL

                DispatchQueue.main.async {
                    store.add(url: normalizedURL)

                    print(
                        "Added file to shelf:",
                        normalizedURL.path
                    )
                }
            }
        }

        return true
    }

    private func dragItems(for item: ShelfItem) -> [ShelfItem] {
        guard selectedItemIDs.contains(item.id) else {
            return [item]
        }

        let selectedItems = store.items.filter {
            selectedItemIDs.contains($0.id)
        }

        return selectedItems.isEmpty ? [item] : selectedItems
    }

    private func actionItems(for item: ShelfItem) -> [ShelfItem] {
        guard selectedItemIDs.contains(item.id) else {
            return [item]
        }

        let selectedItems = store.items.filter {
            selectedItemIDs.contains($0.id)
        }

        return selectedItems.isEmpty ? [item] : selectedItems
    }

    private func beginReorder(for item: ShelfItem) {
        insertionIndicator = nil

        let items = actionItems(for: item)
        reorderedItemIDs = Set(items.map(\.id))

        if !selectedItemIDs.contains(item.id) {
            selectedItemIDs = [item.id]
            lastSelectedItemID = item.id
        }
    }

    private func moveReorderedItems(
        _ movingItems: [ShelfItem],
        to targetItem: ShelfItem
    ) {
        let itemsToMove = movingItems.isEmpty
            ? store.items.filter {
                reorderedItemIDs.contains($0.id)
            }
            : movingItems

        updateInsertionIndicator(
            movingItems: itemsToMove,
            targetItem: targetItem
        )

        withAnimation(.easeInOut(duration: 0.12)) {
            store.move(itemsToMove, to: targetItem)
        }
    }

    private func endReorder() {
        reorderedItemIDs = []
        insertionIndicator = nil
    }

    private func updateInsertionIndicator(
        movingItems: [ShelfItem],
        targetItem: ShelfItem
    ) {
        let movingItemIDs = Set(movingItems.map(\.id))

        guard
            let firstMovingIndex = store.items.firstIndex(where: {
                movingItemIDs.contains($0.id)
            }),
            let targetIndex = store.items.firstIndex(of: targetItem)
        else {
            insertionIndicator = nil
            return
        }

        insertionIndicator = ShelfInsertionIndicator(
            itemID: targetItem.id,
            placement: firstMovingIndex < targetIndex ? .below : .above
        )
    }

    private func insertionPlacement(
        for item: ShelfItem
    ) -> ShelfInsertionPlacement? {
        guard insertionIndicator?.itemID == item.id else {
            return nil
        }

        return insertionIndicator?.placement
    }

    private func updateSelection(
        for item: ShelfItem,
        modifiers: NSEvent.ModifierFlags
    ) {
        if modifiers.contains(.shift),
            let lastSelectedItemID,
            let anchorIndex = store.items.firstIndex(where: {
                $0.id == lastSelectedItemID
            }),
            let currentIndex = store.items.firstIndex(of: item)
        {
            let range = anchorIndex <= currentIndex
                ? anchorIndex...currentIndex
                : currentIndex...anchorIndex
            let rangeIDs = Set(store.items[range].map(\.id))

            if modifiers.contains(.command) {
                selectedItemIDs.formUnion(rangeIDs)
            } else {
                selectedItemIDs = rangeIDs
            }

            return
        }

        if modifiers.contains(.command) {
            if selectedItemIDs.contains(item.id) {
                selectedItemIDs.remove(item.id)

                if lastSelectedItemID == item.id {
                    lastSelectedItemID = selectedItemIDs.first
                }
            } else {
                selectedItemIDs.insert(item.id)
                lastSelectedItemID = item.id
            }

            return
        }

        if selectedItemIDs.contains(item.id),
            selectedItemIDs.count > 1
        {
            lastSelectedItemID = item.id
            return
        }

        selectedItemIDs = [item.id]
        lastSelectedItemID = item.id
    }

    private func clearSelection() {
        selectedItemIDs = []
        lastSelectedItemID = nil
        endReorder()
    }

    private func pruneSelection(validItemIDs: Set<ShelfItem.ID>) {
        selectedItemIDs.formIntersection(validItemIDs)
        reorderedItemIDs.formIntersection(validItemIDs)

        if let lastSelectedItemID,
            !validItemIDs.contains(lastSelectedItemID)
        {
            self.lastSelectedItemID = selectedItemIDs.first
        }
    }

}

private struct ShelfRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [ShelfItem.ID: CGRect] = [:]

    static func reduce(
        value: inout [ShelfItem.ID: CGRect],
        nextValue: () -> [ShelfItem.ID: CGRect]
    ) {
        value.merge(nextValue()) { _, new in
            new
        }
    }
}

private struct ShelfInsertionIndicator {
    let itemID: ShelfItem.ID
    let placement: ShelfInsertionPlacement
}
