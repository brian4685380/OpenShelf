import SwiftUI

struct ShelfRow<DragHandle: View>: View {
    let item: ShelfItem
    let dragHandle: DragHandle

    let onOpen: () -> Void
    let onQuickLook: () -> Void
    let onRevealInFinder: () -> Void
    let onCopyPath: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    init(
        item: ShelfItem,
        @ViewBuilder dragHandle: () -> DragHandle,
        onOpen: @escaping () -> Void,
        onQuickLook: @escaping () -> Void,
        onRevealInFinder: @escaping () -> Void,
        onCopyPath: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.item = item
        self.dragHandle = dragHandle()
        self.onOpen = onOpen
        self.onQuickLook = onQuickLook
        self.onRevealInFinder = onRevealInFinder
        self.onCopyPath = onCopyPath
        self.onRemove = onRemove
    }

    var body: some View {
        HStack(spacing: 10) {
            dragHandle
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.url.lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(item.url.deletingLastPathComponent().path)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background {
                        Circle()
                            .fill(
                                Color.secondary.opacity(
                                    isHovering ? 0.14 : 0
                                )
                            )
                    }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isHovering ? 1 : 0)
            .help("Remove from shelf")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
            .fill(
                isHovering
                    ? Color.secondary.opacity(0.10)
                    : Color.clear
            )
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture(count: 2) {
            onOpen()
        }
        .contextMenu {
            Button {
                onOpen()
            } label: {
                Label(
                    "Open",
                    systemImage: "arrow.up.right.square"
                )
            }

            Button {
                onQuickLook()
            } label: {
                Label(
                    "Quick Look",
                    systemImage: "eye"
                )
            }

            Button {
                onRevealInFinder()
            } label: {
                Label(
                    "Reveal in Finder",
                    systemImage: "folder"
                )
            }

            Button {
                onCopyPath()
            } label: {
                Label(
                    "Copy Path",
                    systemImage: "doc.on.doc"
                )
            }

            Divider()

            Button {
                onRemove()
            } label: {
                Label(
                    "Remove from Shelf",
                    systemImage: "trash"
                )
            }
        }
    }
}
