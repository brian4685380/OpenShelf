import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: ShelfStore
    let onHoverChanged: (Bool) -> Void

    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 12) {
            Text("OpenShelf")
                .font(.title2)
                .fontWeight(.semibold)

            Text(isDropTargeted ? "Release to add files" : "Drag files here")
                .foregroundStyle(.secondary)

            if store.items.isEmpty {
                Spacer()

                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)

                Text("Drop files into this floating shelf")
                    .foregroundStyle(.secondary)

                Spacer()
            } else {
                List {
                    ForEach(store.items) { item in
                        ShelfRow(
                            item: item,
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
                        .onDrag {
                            makeItemProvider(for: item.url)
                        }
                    }
                }
            }
        }
        .frame(width: 420, height: 320)
        .padding()
        .background(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.clear)

        // New:
        // Raise shelf level while mouse is hovering on it.
        .onHover { isHovering in
            onHoverChanged(isHovering)
        }

        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $isDropTargeted
        ) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { item, error in
                if let error {
                    print("Drop error:", error)
                    return
                }

                guard let data = item as? Data,
                    let url = URL(dataRepresentation: data, relativeTo: nil)
                else {
                    return
                }

                DispatchQueue.main.async {
                    store.add(url: url)
                }
            }
        }

        return true
    }

    private func makeItemProvider(for url: URL) -> NSItemProvider {
        let provider = NSItemProvider(object: url as NSURL)
        provider.suggestedName = url.lastPathComponent
        return provider
    }
}
