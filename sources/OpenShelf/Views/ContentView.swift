import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: ShelfStore
    let onHoverChanged: (Bool) -> Void
    let onClose: () -> Void
    let onDragOutCompleted: () -> Void
    let onDropTargetChanged: (Bool) -> Void

    @State private var isDropTargeted = false

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
                Color.black.opacity(0.5)

                if isDropTargeted {
                    Color.accentColor.opacity(0.08)
                }
            }
        }
    }

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(store.items) { item in
                    ShelfRow(
                        item: item,
                        onDragCompleted: { operation in
                            if operation.contains(.move) {
                                print("Moved:", item.url.path)
                            } else if operation.contains(.copy) {
                                print("Copied:", item.url.path)
                            }

                            store.remove(item)
                            onDragOutCompleted()
                        },
                        onOpen: {
                            store.open(item)
                        },
                        onQuickLook: {
                            store.quickLook(item)
                        },
                        onRevealInFinder: {
                            store.revealInFinder(item)
                        },
                        onCopyPath: {
                            store.copyPath(item)
                        },
                        onRemove: {
                            store.remove(item)
                        }
                    )
                }
            }
            .padding(10)
        }
        .background {
            ZStack {
                Color.black.opacity(0.5)

                if isDropTargeted {
                    Color.accentColor.opacity(0.08)
                }
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(
                UTType.fileURL.identifier
            )
        }

        guard !fileProviders.isEmpty else {
            return false
        }

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

}
