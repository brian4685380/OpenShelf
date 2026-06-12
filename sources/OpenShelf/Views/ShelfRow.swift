import SwiftUI

struct ShelfRow: View {
    let item: ShelfItem

    let onOpen: () -> Void
    let onQuickLook: () -> Void
    let onRevealInFinder: () -> Void
    let onCopyPath: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            FileIcon(url: item.url)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent)
                    .lineLimit(1)

                Text(item.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove from shelf")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onOpen()
        }
        .contextMenu {
            Button {
                onOpen()
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }

            Button {
                onQuickLook()
            } label: {
                Label("Quick Look", systemImage: "eye")
            }

            Button {
                onRevealInFinder()
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }

            Button {
                onCopyPath()
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }

            Divider()

            Button {
                onRemove()
            } label: {
                Label("Remove from Shelf", systemImage: "trash")
            }
        }
    }
}
