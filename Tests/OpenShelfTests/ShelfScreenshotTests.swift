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
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = hosting
            window.isOpaque = false
            window.backgroundColor = .clear
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: outputURL.appendingPathComponent("shelf-\(name).png"))
            window.orderOut(nil)
        }
    }
}
