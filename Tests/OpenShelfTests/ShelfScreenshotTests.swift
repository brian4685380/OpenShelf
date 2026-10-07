import AppKit
import SwiftUI
import XCTest
@testable import OpenShelf

/// Opt-in, reproducible README images of the real UI, using synthetic content.
@MainActor
final class ShelfScreenshotTests: XCTestCase {
    func testRenderDocumentationScreenshots() throws {
        guard let output = ProcessInfo.processInfo.environment["OPENSHELF_SCREENSHOTS"] else {
            throw XCTSkip("Set OPENSHELF_SCREENSHOTS to render documentation images.")
        }
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpenShelf Preview \(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        let store = ShelfStore()
        defer { store.clear() }
        for name in ["Project brief.pdf", "Moodboard.png", "Draft notes.txt"] {
            let url = directory.appendingPathComponent(name)
            try Data("Sample content for documentation".utf8).write(to: url)
            store.add(url: url, isManagedByShelf: true)
        }
        let selection = ShelfSelectionModel()
        selection.replace(with: Set(store.items.prefix(2).map(\.id)), anchorItemID: store.items.first?.id)
        let presentation = ShelfPresentationState()
        presentation.isPinned = true

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let view = ContentView(store: store, dropState: ShelfDropState(), selection: selection,
                presentation: presentation, onHoverChanged: { _ in }, onClose: {}, onEmpty: {}, onDragOutCompleted: {})
            try render(view, size: NSSize(width: 300, height: 200), appearance: appearance,
                       to: outputURL.appendingPathComponent("shelf-\(name).png"))
        }

        let secondStore = ShelfStore()
        defer { secondStore.clear() }
        for name in ["Release notes.md", "Demo.mov"] {
            let url = directory.appendingPathComponent(name)
            try Data("Sample content for documentation".utf8).write(to: url)
            secondStore.add(url: url, isManagedByShelf: true)
        }
        let multipleShelves = HStack(spacing: 16) {
            ContentView(store: store, dropState: ShelfDropState(), selection: selection,
                presentation: presentation, onHoverChanged: { _ in }, onClose: {}, onEmpty: {}, onDragOutCompleted: {})
            ContentView(store: secondStore, dropState: ShelfDropState(),
                onHoverChanged: { _ in }, onClose: {}, onEmpty: {}, onDragOutCompleted: {})
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        try render(multipleShelves, size: NSSize(width: 640, height: 224), appearance: .aqua,
                   to: outputURL.appendingPathComponent("multiple-shelves.png"))
    }

    private func render<Content: View>(_ view: Content, size: NSSize, appearance: NSAppearance.Name, to url: URL) throws {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }
}
