import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import OpenShelf

@MainActor
final class ShelfContentImporterTests: XCTestCase {
    func testClipboardTextBecomesManagedTextFile() throws {
        let pasteboard = makePasteboard()
        XCTAssertTrue(pasteboard.setString("A useful browser selection", forType: .string))

        let contents = ShelfContentImporter().importPasteboard(pasteboard)
        let content = try XCTUnwrap(contents.first)
        defer { removeImportDirectory(for: content) }

        XCTAssertEqual(contents.count, 1)
        XCTAssertTrue(content.isManagedByShelf)
        XCTAssertEqual(content.url.pathExtension, "txt")
        XCTAssertEqual(
            try String(contentsOf: content.url, encoding: .utf8),
            "A useful browser selection"
        )
    }

    func testClipboardImageBecomesManagedPNGFile() throws {
        let pasteboard = makePasteboard()
        let imageData = try XCTUnwrap(
            Data(base64Encoded: onePixelPNGBase64)
        )
        XCTAssertTrue(pasteboard.setData(imageData, forType: .png))

        let contents = ShelfContentImporter().importPasteboard(pasteboard)
        let content = try XCTUnwrap(contents.first)
        defer { removeImportDirectory(for: content) }

        XCTAssertEqual(contents.count, 1)
        XCTAssertTrue(content.isManagedByShelf)
        XCTAssertEqual(content.url.pathExtension, "png")
        XCTAssertNotNil(NSImage(contentsOf: content.url))
    }

    func testClipboardFileRemainsAReferenceToOriginal() throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenShelf Test \(UUID().uuidString).txt")
        try Data("original".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let pasteboard = makePasteboard()
        XCTAssertTrue(pasteboard.writeObjects([sourceURL as NSURL]))

        let contents = ShelfContentImporter().importPasteboard(pasteboard)
        let content = try XCTUnwrap(contents.first)

        XCTAssertEqual(contents.count, 1)
        XCTAssertFalse(content.isManagedByShelf)
        XCTAssertEqual(content.url, sourceURL.standardizedFileURL)
    }

    func testDroppedTextProviderBecomesManagedTextFile() async throws {
        let importer = ShelfContentImporter()
        let provider = NSItemProvider(
            object: NSString(string: "Dragged browser text")
        )

        let contents = await withCheckedContinuation { continuation in
            let accepted = importer.importItemProviders([provider]) {
                continuation.resume(returning: $0)
            }
            XCTAssertTrue(accepted)

            if !accepted {
                continuation.resume(returning: [])
            }
        }

        let content = try XCTUnwrap(contents.first)
        defer { removeImportDirectory(for: content) }

        XCTAssertTrue(content.isManagedByShelf)
        XCTAssertEqual(
            try String(contentsOf: content.url, encoding: .utf8),
            "Dragged browser text"
        )
    }

    func testDroppedImageProviderBecomesManagedImageFile() async throws {
        let importer = ShelfContentImporter()
        let imageData = try XCTUnwrap(
            Data(base64Encoded: onePixelPNGBase64)
        )
        let provider = NSItemProvider(
            item: imageData as NSData,
            typeIdentifier: UTType.png.identifier
        )

        let contents = await importContents(
            from: [provider],
            using: importer
        )
        let content = try XCTUnwrap(contents.first)
        defer { removeImportDirectory(for: content) }

        XCTAssertTrue(content.isManagedByShelf)
        XCTAssertEqual(content.url.pathExtension, "png")
        XCTAssertNotNil(NSImage(contentsOf: content.url))
    }

    func testDroppedFilePasteboardRemainsAReferenceToOriginal() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenShelf Drag \(UUID().uuidString).txt")
        try Data("original".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let pasteboard = makePasteboard()
        XCTAssertTrue(pasteboard.writeObjects([sourceURL as NSURL]))

        let contents = await importDroppedContents(from: pasteboard)
        let content = try XCTUnwrap(contents.first)

        XCTAssertEqual(contents.count, 1)
        XCTAssertFalse(content.isManagedByShelf)
        XCTAssertEqual(content.url, sourceURL.standardizedFileURL)
    }

    func testLegacyFinderFileListRemainsAReferenceToOriginal() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "OpenShelf Legacy Finder \(UUID().uuidString).txt"
            )
        try Data("legacy".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let pasteboard = makePasteboard()
        XCTAssertTrue(
            pasteboard.setPropertyList(
                [sourceURL.path],
                forType: ShelfDropSupport.legacyFileNamesPasteboardType
            )
        )

        let contents = await importDroppedContents(from: pasteboard)
        let content = try XCTUnwrap(contents.first)

        XCTAssertEqual(contents.count, 1)
        XCTAssertFalse(content.isManagedByShelf)
        XCTAssertEqual(content.url, sourceURL.standardizedFileURL)
    }

    func testDroppedImagePasteboardBecomesManagedImageFile() async throws {
        let pasteboard = makePasteboard()
        let imageData = try XCTUnwrap(Data(base64Encoded: onePixelPNGBase64))
        XCTAssertTrue(pasteboard.setData(imageData, forType: .png))

        let contents = await importDroppedContents(from: pasteboard)
        let content = try XCTUnwrap(contents.first)
        defer { removeImportDirectory(for: content) }

        XCTAssertTrue(content.isManagedByShelf)
        XCTAssertEqual(content.url.pathExtension, "png")
        XCTAssertNotNil(NSImage(contentsOf: content.url))
    }

    func testDroppedTemporaryBrowserImageIsPreserved() async throws {
        let imageData = try XCTUnwrap(Data(base64Encoded: onePixelPNGBase64))
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Browser Image \(UUID().uuidString).png")
        try imageData.write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let pasteboard = makePasteboard()
        let item = NSPasteboardItem()
        item.setString(sourceURL.absoluteString, forType: .fileURL)
        item.setData(imageData, forType: .png)
        XCTAssertTrue(pasteboard.writeObjects([item]))

        let contents = await importDroppedContents(from: pasteboard)
        let content = try XCTUnwrap(contents.first)
        defer { removeImportDirectory(for: content) }

        XCTAssertTrue(content.isManagedByShelf)
        XCTAssertNotEqual(content.url, sourceURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: content.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    func testDroppedTextPasteboardBecomesManagedTextFile() async throws {
        let pasteboard = makePasteboard()
        XCTAssertTrue(
            pasteboard.setString("Dragged from another app", forType: .string)
        )

        let contents = await importDroppedContents(from: pasteboard)
        let content = try XCTUnwrap(contents.first)
        defer { removeImportDirectory(for: content) }

        XCTAssertTrue(content.isManagedByShelf)
        XCTAssertEqual(
            try String(contentsOf: content.url, encoding: .utf8),
            "Dragged from another app"
        )
    }

    func testDraggedBrowserLinkBecomesWebLocation() async throws {
        let pasteboard = makePasteboard()
        XCTAssertTrue(
            pasteboard.setString("https://example.com/story", forType: .URL)
        )
        XCTAssertTrue(
            pasteboard.setString(
                "Example Story",
                forType: ShelfDropSupport.urlNamePasteboardType
            )
        )
        XCTAssertTrue(
            pasteboard.setString("https://example.com/story", forType: .string)
        )

        let contents = await importDroppedContents(from: pasteboard)
        let content = try XCTUnwrap(contents.first)
        defer { removeImportDirectory(for: content) }

        XCTAssertTrue(content.isManagedByShelf)
        XCTAssertEqual(content.url.pathExtension, "webloc")
    }

    func testCommandVPastesThroughShelfPanel() throws {
        let panel = ShelfPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        var didPaste = false
        panel.onPaste = {
            didPaste = true
            return true
        }

        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: 0,
                windowNumber: panel.windowNumber,
                context: nil,
                characters: "v",
                charactersIgnoringModifiers: "v",
                isARepeat: false,
                keyCode: 9
            )
        )

        XCTAssertTrue(panel.performKeyEquivalent(with: event))
        XCTAssertTrue(didPaste)
    }

    func testCommandVIsHandledAtShelfWindowEventBoundary() throws {
        let panel = ShelfPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        var pasteCount = 0
        panel.onPaste = {
            pasteCount += 1
            return true
        }

        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: 0,
                windowNumber: panel.windowNumber,
                context: nil,
                characters: "v",
                charactersIgnoringModifiers: "v",
                isARepeat: false,
                keyCode: 9
            )
        )

        panel.sendEvent(event)

        XCTAssertEqual(pasteCount, 1)
    }

    private func importContents(
        from providers: [NSItemProvider],
        using importer: ShelfContentImporter
    ) async -> [ImportedShelfContent] {
        await withCheckedContinuation { continuation in
            let accepted = importer.importItemProviders(providers) {
                continuation.resume(returning: $0)
            }

            if !accepted {
                continuation.resume(returning: [])
            }
        }
    }

    private func importDroppedContents(
        from pasteboard: NSPasteboard
    ) async -> [ImportedShelfContent] {
        let importer = ShelfContentImporter()

        return await withCheckedContinuation { continuation in
            let accepted = importer.importDroppedPasteboard(pasteboard) {
                continuation.resume(returning: $0)
            }

            if !accepted {
                continuation.resume(returning: [])
            }
        }
    }

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        return pasteboard
    }

    private func removeImportDirectory(for content: ImportedShelfContent) {
        try? FileManager.default.removeItem(
            at: content.url.deletingLastPathComponent()
        )
    }

    private var onePixelPNGBase64: String {
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    }
}
