import AppKit
import SwiftUI

struct ShelfRow: View {
    let item: ShelfItem
    let isSelected: Bool
    let insertionPlacement: ShelfInsertionPlacement?
    let dragItems: [ShelfItem]
    let onDragStarted: () -> Void
    let onDragCompleted: (NSDragOperation, [ShelfItem]) -> Void
    let onDragEnded: () -> Void
    let onClick: (NSEvent.ModifierFlags) -> Void
    let onReorderDropEntered: ([ShelfItem], ShelfItem) -> Void
    let onReorderDropEnded: () -> Void

    let onOpen: () -> Void
    let onQuickLook: () -> Void
    let onRevealInFinder: () -> Void
    let onCopyPath: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            draggableContent

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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
            .fill(rowBackgroundColor)
        }
        .overlay(alignment: .top) {
            if insertionPlacement == .above {
                insertionLine
                    .offset(y: -4)
            }
        }
        .overlay(alignment: .bottom) {
            if insertionPlacement == .below {
                insertionLine
                    .offset(y: 4)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
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

    private var draggableContent: some View {
        ZStack {
            HStack(spacing: 10) {
                FileIcon(url: item.url)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.url.lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(
                        item.url
                            .deletingLastPathComponent()
                            .path
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }

                Spacer(minLength: 8)
            }

            FileDragSource(
                item: item,
                dragItems: dragItems,
                onDragStarted: onDragStarted,
                onDragCompleted: onDragCompleted,
                onDragEnded: onDragEnded,
                onClick: onClick,
                onReorderDropEntered: onReorderDropEntered,
                onReorderDropEnded: onReorderDropEnded,
                onDoubleClick: onOpen
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle())
    }

    private var rowBackgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(isHovering ? 0.24 : 0.18)
        }

        if isHovering {
            return Color.secondary.opacity(0.10)
        }

        return Color.clear
    }

    private var insertionLine: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 7, height: 7)

            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 3)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 2)
        .shadow(
            color: Color.accentColor.opacity(0.45),
            radius: 3,
            x: 0,
            y: 0
        )
    }
}
