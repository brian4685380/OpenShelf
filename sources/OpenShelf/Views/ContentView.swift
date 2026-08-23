import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var dropState: ShelfDropState
    @StateObject private var selection: ShelfSelectionModel
    let onHoverChanged: (Bool) -> Void
    let onClose: () -> Void
    let onEmpty: () -> Void
    let onDragOutCompleted: () -> Void

    @State private var reorderedItemIDs: Set<ShelfItem.ID> = []
    @State private var insertionIndicator: ShelfInsertionIndicator?
    @State private var rowFrames: [ShelfItem.ID: CGRect] = [:]

    init(
        store: ShelfStore,
        dropState: ShelfDropState,
        selection: ShelfSelectionModel? = nil,
        onHoverChanged: @escaping (Bool) -> Void,
        onClose: @escaping () -> Void,
        onEmpty: @escaping () -> Void,
        onDragOutCompleted: @escaping () -> Void
    ) {
        self.store = store
        self.dropState = dropState
        _selection = StateObject(
            wrappedValue: selection ?? ShelfSelectionModel()
        )
        self.onHoverChanged = onHoverChanged
        self.onClose = onClose
        self.onEmpty = onEmpty
        self.onDragOutCompleted = onDragOutCompleted
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            // Divider()
            //     .opacity(0.45)

            if store.items.isEmpty {
                emptyState
            } else {
                itemList
            }
        }
        .frame(width: 300, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if dropState.isTargeted {
                dropTargetCue
            }
        }
        .overlay(alignment: .bottom) {
            if let feedback = dropState.feedback {
                dropFeedback(feedback)
                    .padding(.bottom, 10)
                    .transition(
                        .move(edge: .bottom).combined(with: .opacity)
                    )
            }
        }
        .animation(.easeOut(duration: 0.16), value: dropState.isTargeted)
        .animation(.easeOut(duration: 0.16), value: dropState.feedback)
        .onHover { isHovering in
            onHoverChanged(isHovering)
        }
        .onChange(of: store.items.isEmpty) { isEmpty in
            if isEmpty {
                onEmpty()
            }
        }
        .onChange(of: store.items.map(\.id)) { itemIDs in
            selection.prune(to: store.items)
            reorderedItemIDs.formIntersection(itemIDs)
        }
        .onChange(of: dropState.successfulDropGeneration) { _ in
            clearSelection()
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
            Color(nsColor: ShelfAppearance.backgroundColor)
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

            Text(dropState.isTargeted ? "Release to add content" : "Drop anything here")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Files, images, text, or press ⌘V")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                Color(nsColor: ShelfAppearance.backgroundColor)

                if dropState.isTargeted {
                    Color.accentColor.opacity(0.08)
                }
            }
        }
    }

    private var itemList: some View {
        ZStack(alignment: .topLeading) {
            Color(nsColor: ShelfAppearance.backgroundColor)

            if dropState.isTargeted {
                Color.accentColor.opacity(0.08)
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.items) { item in
                        ShelfRow(
                            item: item,
                            isSelected: selection.itemIDs.contains(item.id),
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

                                selection.subtract(
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
                            onReorderDropEntered: {
                                movingItems,
                                targetItem in

                                moveReorderedItems(
                                    movingItems,
                                    to: targetItem
                                )
                            },
                            onReorderDropEnded: {
                                endReorder()
                            },
                            onOpen: {
                                store.open(
                                    actionItems(for: item)
                                )
                            },
                            onQuickLook: {
                                store.quickLook(
                                    actionItems(for: item)
                                )
                            },
                            onRevealInFinder: {
                                store.revealInFinder(
                                    actionItems(for: item)
                                )
                            },
                            onCopyPath: {
                                store.copyPath(
                                    actionItems(for: item)
                                )
                            },
                            onRemove: {
                                let items = actionItems(for: item)

                                store.remove(items)

                                selection.subtract(
                                    items.map(\.id)
                                )
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
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .animation(
                    .easeInOut(duration: 0.12),
                    value: store.items.map(\.id)
                )
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .top
            )

            ShelfSelectionOverlay(
                rowFrames: rowFrames,
                rowOrder: store.items.map(\.id),
                selectedItemIDs: selection.itemIDs,
                onClearSelection: {
                    clearSelection()
                },
                onSelectionChanged: { itemIDs, lastItemID in
                    selection.replace(
                        with: itemIDs,
                        anchorItemID: lastItemID
                    )
                }
            )
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
        .coordinateSpace(name: "ShelfList")
        .onPreferenceChange(
            ShelfRowFramePreferenceKey.self
        ) { frames in
            rowFrames = frames
        }
    }

    private var dropTargetCue: some View {
        Label("Drop to add", systemImage: "plus.circle.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            .allowsHitTesting(false)
    }

    private func dropFeedback(
        _ feedback: ShelfDropState.Feedback
    ) -> some View {
        Label(feedback.message, systemImage: feedback.systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(
                feedback.isError ? Color.red : Color.primary
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.16), radius: 7, y: 3)
            .allowsHitTesting(false)
    }

    private func dragItems(for item: ShelfItem) -> [ShelfItem] {
        selection.resolvedItems(for: item, in: store.items)
    }

    private func actionItems(for item: ShelfItem) -> [ShelfItem] {
        selection.resolvedItems(for: item, in: store.items)
    }

    private func beginReorder(for item: ShelfItem) {
        insertionIndicator = nil

        let items = actionItems(for: item)
        reorderedItemIDs = Set(items.map(\.id))

        if !selection.itemIDs.contains(item.id) {
            selection.selectOnly(item)
        }
    }

    private func moveReorderedItems(
        _ movingItems: [ShelfItem],
        to targetItem: ShelfItem
    ) {
        let itemsToMove =
            movingItems.isEmpty
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
        selection.handleClick(
            on: item,
            in: store.items,
            modifiers: modifiers
        )
    }

    private func clearSelection() {
        selection.clear()
        endReorder()
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
