import AppKit
import UniformTypeIdentifiers

enum ShelfDropSupport {
    static let legacyFileNamesPasteboardType = NSPasteboard.PasteboardType(
        "NSFilenamesPboardType"
    )
    static let urlNamePasteboardType = NSPasteboard.PasteboardType(
        "public.url-name"
    )

    static let readableDraggedTypes: [NSPasteboard.PasteboardType] = {
        let dragPasteboard = NSPasteboard(name: .drag)
        let declaredTypes = [
            NSPasteboard.PasteboardType.fileURL,
            legacyFileNamesPasteboardType,
            .URL,
            .string,
            .png,
            .tiff,
            NSPasteboard.PasteboardType(UTType.image.identifier),
            NSPasteboard.PasteboardType(UTType.text.identifier),
            NSPasteboard.PasteboardType(UTType.plainText.identifier),
            NSPasteboard.PasteboardType(UTType.utf8PlainText.identifier),
        ]
        let cocoaReadableTypes =
            NSURL.readableTypes(for: dragPasteboard)
            + NSString.readableTypes(for: dragPasteboard)
            + NSAttributedString.readableTypes(for: dragPasteboard)
            + NSImage.readableTypes(for: dragPasteboard)
        let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map {
            NSPasteboard.PasteboardType($0)
        }

        var seen: Set<NSPasteboard.PasteboardType> = []

        return (declaredTypes + cocoaReadableTypes + promiseTypes).filter {
            seen.insert($0).inserted
        }
    }()

    static func canImport(_ pasteboard: NSPasteboard) -> Bool {
        guard !isShelfReorder(pasteboard) else {
            return false
        }

        if pasteboard.canReadObject(
            forClasses: [
                NSURL.self,
                NSImage.self,
                NSString.self,
                NSAttributedString.self,
            ],
            options: nil
        ) {
            return true
        }

        if pasteboard.canReadObject(
            forClasses: [NSFilePromiseReceiver.self],
            options: nil
        ) {
            return true
        }

        return pasteboard.types?.contains(where: isSupportedType) == true
    }

    static func isShelfReorder(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.types?.contains(
            NSPasteboard.PasteboardType(
                shelfReorderPasteboardTypeIdentifier
            )
        ) == true
    }

    private static func isSupportedType(
        _ pasteboardType: NSPasteboard.PasteboardType
    ) -> Bool {
        if readableDraggedTypes.contains(pasteboardType) {
            return true
        }

        guard let type = UTType(pasteboardType.rawValue) else {
            return false
        }

        return type.conforms(to: .fileURL)
            || type.conforms(to: .image)
            || type.conforms(to: .url)
            || type.conforms(to: .text)
    }
}
