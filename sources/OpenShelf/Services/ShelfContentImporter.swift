import AppKit
import Foundation
import UniformTypeIdentifiers

struct ImportedShelfContent {
    let url: URL
    let isManagedByShelf: Bool
}

final class ShelfContentImporter {
    private let fileManager: FileManager
    private let importDirectory: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        importDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("OpenShelf Imports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func canImport(itemProviders: [NSItemProvider]) -> Bool {
        itemProviders.contains(where: canImport(itemProvider:))
    }

    @discardableResult
    func importItemProviders(
        _ itemProviders: [NSItemProvider],
        completion: @escaping ([ImportedShelfContent]) -> Void
    ) -> Bool {
        let importableProviders = itemProviders.enumerated().filter {
            canImport(itemProvider: $0.element)
        }

        guard !importableProviders.isEmpty else {
            return false
        }

        var orderedResults: [Int: ImportedShelfContent] = [:]
        let group = DispatchGroup()

        for (index, provider) in importableProviders {
            group.enter()

            importItemProvider(provider) { content in
                DispatchQueue.main.async {
                    orderedResults[index] = content
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            let contents = orderedResults.keys.sorted().compactMap {
                orderedResults[$0]
            }
            completion(contents)
        }

        return true
    }

    @discardableResult
    func importDroppedPasteboard(
        _ pasteboard: NSPasteboard,
        completion: @escaping ([ImportedShelfContent]) -> Void
    ) -> Bool {
        let fileReferences = importedFileReferences(
            from: pasteboard,
            preservingTemporaryImages: true
        )

        if !fileReferences.isEmpty {
            completion(fileReferences)
            return true
        }

        // Some browsers and document apps do not place a file URL on the drag
        // pasteboard. They promise to create the file only after the drop is
        // accepted, so call in that promise while the drag session is alive.
        if receivePromisedFiles(from: pasteboard, completion: completion) {
            return true
        }

        let immediateContents = importedNonFileContents(from: pasteboard)

        if !immediateContents.isEmpty {
            completion(immediateContents)
            return true
        }

        // Fall back to item providers for apps that publish a concrete UTI but
        // cannot be read directly as NSURL, NSImage, or NSString.
        let providers = snapshottedItemProviders(from: pasteboard)

        guard !providers.isEmpty else {
            return false
        }

        return importItemProviders(providers, completion: completion)
    }

    func importPasteboard(
        _ pasteboard: NSPasteboard
    ) -> [ImportedShelfContent] {
        let fileReferences = importedFileReferences(
            from: pasteboard,
            preservingTemporaryImages: false
        )

        if !fileReferences.isEmpty {
            return fileReferences
        }

        return importedNonFileContents(from: pasteboard)
    }

    private func importedFileReferences(
        from pasteboard: NSPasteboard,
        preservingTemporaryImages: Bool
    ) -> [ImportedShelfContent] {
        let cocoaFileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL] ?? []

        let legacyFileURLs = (
            pasteboard.propertyList(
                forType: ShelfDropSupport.legacyFileNamesPasteboardType
            ) as? [String] ?? []
        ).map {
            NSURL(fileURLWithPath: $0)
        }

        var seenPaths: Set<String> = []
        let fileURLs = (cocoaFileURLs + legacyFileURLs).filter {
            seenPaths.insert(($0 as URL).standardizedFileURL.path).inserted
        }

        return fileURLs.compactMap { value in
            let url = (value as URL).standardizedFileURL

            guard fileManager.fileExists(atPath: url.path) else {
                return nil
            }

            if preservingTemporaryImages,
                pasteboardContainsImageRepresentation(pasteboard),
                isTemporaryFile(url),
                let copiedContent = materializeFile(at: url)
            {
                return copiedContent
            }

            return ImportedShelfContent(
                url: url,
                isManagedByShelf: false
            )
        }
    }

    private func importedNonFileContents(
        from pasteboard: NSPasteboard
    ) -> [ImportedShelfContent] {
        if let images = pasteboard.readObjects(
            forClasses: [NSImage.self],
            options: nil
        ) as? [NSImage],
            !images.isEmpty
        {
            let importedImages: [ImportedShelfContent] = images.compactMap {
                image in
                guard let data = pngData(for: image) else {
                    return nil
                }

                return materialize(
                    data: data,
                    suggestedBaseName: "Image Clip",
                    fileExtension: "png"
                )
            }

            if !importedImages.isEmpty {
                return importedImages
            }
        }

        // A dragged browser link normally includes public.url-name. Prefer a
        // .webloc in that case; selected browser text often includes the page
        // URL too, but no URL name, and should remain a text clipping.
        if let urlName = pasteboard.string(
            forType: ShelfDropSupport.urlNamePasteboardType
        ),
            !urlName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let webLocation = importedWebLocation(from: pasteboard)
        {
            return [webLocation]
        }

        if let attributedStrings = pasteboard.readObjects(
            forClasses: [NSAttributedString.self],
            options: nil
        ) as? [NSAttributedString],
            let text = attributedStrings.first?.string,
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let importedText = materializeText(text)
        {
            return [importedText]
        }

        if let text = pasteboard.string(forType: .string),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let importedText = materializeText(text)
        {
            return [importedText]
        }

        if let webLocation = importedWebLocation(from: pasteboard) {
            return [webLocation]
        }

        return []
    }

    private func pasteboardContainsImageRepresentation(
        _ pasteboard: NSPasteboard
    ) -> Bool {
        pasteboard.types?.contains { pasteboardType in
            UTType(pasteboardType.rawValue)?.conforms(to: .image) == true
        } == true
    }

    private func isTemporaryFile(_ url: URL) -> Bool {
        let filePath = url.resolvingSymlinksInPath().standardizedFileURL.path
        let temporaryRoots = [
            fileManager.temporaryDirectory,
            URL(fileURLWithPath: "/private/tmp", isDirectory: true),
            URL(fileURLWithPath: "/tmp", isDirectory: true),
        ]

        return temporaryRoots.contains { root in
            let rootPath = root.resolvingSymlinksInPath()
                .standardizedFileURL.path
            return filePath == rootPath || filePath.hasPrefix(rootPath + "/")
        }
    }

    private func importedWebLocation(
        from pasteboard: NSPasteboard
    ) -> ImportedShelfContent? {
        guard let rawURL = pasteboard.string(forType: .URL),
            let url = URL(string: rawURL),
            !url.isFileURL
        else {
            return nil
        }

        return materializeWebLocation(url)
    }

    private func receivePromisedFiles(
        from pasteboard: NSPasteboard,
        completion: @escaping ([ImportedShelfContent]) -> Void
    ) -> Bool {
        guard let receivers = pasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self],
            options: nil
        ) as? [NSFilePromiseReceiver],
            !receivers.isEmpty
        else {
            return false
        }

        do {
            try fileManager.createDirectory(
                at: importDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            print("Unable to prepare promised-file destination:", error)
            completion([])
            return true
        }

        for receiver in receivers {
            receiver.receivePromisedFiles(
                atDestination: importDirectory,
                options: [:],
                operationQueue: .main
            ) { [weak self] fileURL, error in
                guard let self else {
                    completion([])
                    return
                }

                guard error == nil,
                    self.fileManager.fileExists(atPath: fileURL.path)
                else {
                    if let error {
                        print("Unable to receive promised file:", error)
                    }
                    completion([])
                    return
                }

                let normalizedURL = fileURL.standardizedFileURL
                let managedDirectoryPath = self.importDirectory
                    .standardizedFileURL.path + "/"

                if normalizedURL.path.hasPrefix(managedDirectoryPath) {
                    completion([
                        ImportedShelfContent(
                            url: normalizedURL,
                            isManagedByShelf: true
                        )
                    ])
                } else if let copiedContent = self.materializeFile(
                    at: normalizedURL
                ) {
                    completion([copiedContent])
                } else {
                    completion([])
                }
            }
        }

        return true
    }

    private func snapshottedItemProviders(
        from pasteboard: NSPasteboard
    ) -> [NSItemProvider] {
        let pasteboardItems: [NSPasteboardItem]

        if let items = pasteboard.pasteboardItems, !items.isEmpty {
            pasteboardItems = items
        } else {
            let item = NSPasteboardItem()

            for type in pasteboard.types ?? [] {
                if let data = pasteboard.data(forType: type) {
                    item.setData(data, forType: type)
                }
            }

            pasteboardItems = item.types.isEmpty ? [] : [item]
        }

        return pasteboardItems.compactMap { pasteboardItem in
            let representations = pasteboardItem.types.compactMap {
                type -> (String, Data)? in
                guard let data = pasteboardItem.data(forType: type) else {
                    return nil
                }

                return (type.rawValue, data)
            }

            guard !representations.isEmpty else {
                return nil
            }

            let provider = NSItemProvider()
            provider.suggestedName = pasteboardItem.string(
                forType: ShelfDropSupport.urlNamePasteboardType
            )

            for (typeIdentifier, data) in representations {
                provider.registerDataRepresentation(
                    forTypeIdentifier: typeIdentifier,
                    visibility: .all
                ) { completionHandler in
                    completionHandler(data, nil)
                    return nil
                }
            }

            return provider
        }
    }

    private func canImport(itemProvider: NSItemProvider) -> Bool {
        itemProvider.hasItemConformingToTypeIdentifier(
            UTType.fileURL.identifier
        )
            || itemProvider.hasItemConformingToTypeIdentifier(
                UTType.image.identifier
            )
            || itemProvider.hasItemConformingToTypeIdentifier(
                UTType.url.identifier
            )
            || itemProvider.hasItemConformingToTypeIdentifier(
                UTType.plainText.identifier
            )
            || itemProvider.hasItemConformingToTypeIdentifier(
                UTType.utf8PlainText.identifier
            )
            || itemProvider.hasItemConformingToTypeIdentifier(
                UTType.text.identifier
            )
    }

    private func importItemProvider(
        _ provider: NSItemProvider,
        completion: @escaping (ImportedShelfContent?) -> Void
    ) {
        loadFileURL(from: provider) { [weak self] fileContent in
            guard let self else {
                completion(nil)
                return
            }

            if let fileContent {
                completion(fileContent)
                return
            }

            self.loadImage(from: provider) { imageContent in
                if let imageContent {
                    completion(imageContent)
                    return
                }

                self.loadText(from: provider) { textContent in
                    if let textContent {
                        completion(textContent)
                        return
                    }

                    self.loadWebURL(from: provider, completion: completion)
                }
            }
        }
    }

    private func loadFileURL(
        from provider: NSItemProvider,
        completion: @escaping (ImportedShelfContent?) -> Void
    ) {
        guard provider.hasItemConformingToTypeIdentifier(
            UTType.fileURL.identifier
        ) else {
            completion(nil)
            return
        }

        provider.loadItem(
            forTypeIdentifier: UTType.fileURL.identifier,
            options: nil
        ) { [weak self] item, error in
            guard let self else {
                completion(nil)
                return
            }

            if let error {
                print("Unable to read dropped file URL:", error)
                completion(nil)
                return
            }

            guard let url = self.url(from: item),
                url.isFileURL,
                self.fileManager.fileExists(atPath: url.path)
            else {
                completion(nil)
                return
            }

            // Browsers commonly expose dragged images through a temporary
            // file URL. Preserve those before the drag session releases them.
            if provider.hasItemConformingToTypeIdentifier(
                UTType.image.identifier
            ),
                let copiedContent = self.materializeFile(at: url)
            {
                completion(copiedContent)
                return
            }

            completion(
                ImportedShelfContent(
                    url: url.standardizedFileURL,
                    isManagedByShelf: false
                )
            )
        }
    }

    private func loadImage(
        from provider: NSItemProvider,
        completion: @escaping (ImportedShelfContent?) -> Void
    ) {
        guard provider.hasItemConformingToTypeIdentifier(
            UTType.image.identifier
        ) else {
            completion(nil)
            return
        }

        if let typeIdentifier = preferredImageTypeIdentifier(for: provider) {
            provider.loadDataRepresentation(
                forTypeIdentifier: typeIdentifier
            ) { [weak self] data, error in
                guard let self else {
                    completion(nil)
                    return
                }

                if let data, !data.isEmpty {
                    let type = UTType(typeIdentifier)
                    let fileExtension = type?.preferredFilenameExtension
                        ?? "png"

                    completion(
                        self.materialize(
                            data: data,
                            suggestedBaseName: "Image Clip",
                            fileExtension: fileExtension
                        )
                    )
                    return
                }

                if let error {
                    print("Unable to read dropped image data:", error)
                }

                self.loadImageObject(from: provider, completion: completion)
            }
            return
        }

        loadImageObject(from: provider, completion: completion)
    }

    private func loadImageObject(
        from provider: NSItemProvider,
        completion: @escaping (ImportedShelfContent?) -> Void
    ) {
        guard provider.canLoadObject(ofClass: NSImage.self) else {
            completion(nil)
            return
        }

        provider.loadObject(ofClass: NSImage.self) { [weak self] value, error in
            guard let self else {
                completion(nil)
                return
            }

            guard let image = value as? NSImage,
                let data = self.pngData(for: image)
            else {
                if let error {
                    print("Unable to read dropped image:", error)
                }
                completion(nil)
                return
            }

            completion(
                self.materialize(
                    data: data,
                    suggestedBaseName: "Image Clip",
                    fileExtension: "png"
                )
            )
        }
    }

    private func loadWebURL(
        from provider: NSItemProvider,
        completion: @escaping (ImportedShelfContent?) -> Void
    ) {
        guard provider.hasItemConformingToTypeIdentifier(
            UTType.url.identifier
        ) else {
            completion(nil)
            return
        }

        provider.loadItem(
            forTypeIdentifier: UTType.url.identifier,
            options: nil
        ) { [weak self] item, error in
            guard let self else {
                completion(nil)
                return
            }

            guard error == nil, let url = self.url(from: item) else {
                if let error {
                    print("Unable to read dropped URL:", error)
                }
                completion(nil)
                return
            }

            if url.isFileURL,
                self.fileManager.fileExists(atPath: url.path)
            {
                completion(
                    ImportedShelfContent(
                        url: url.standardizedFileURL,
                        isManagedByShelf: false
                    )
                )
                return
            }

            completion(self.materializeWebLocation(url))
        }
    }

    private func loadText(
        from provider: NSItemProvider,
        completion: @escaping (ImportedShelfContent?) -> Void
    ) {
        let typeIdentifier = preferredTextTypeIdentifier(for: provider)

        guard let typeIdentifier else {
            completion(nil)
            return
        }

        provider.loadItem(
            forTypeIdentifier: typeIdentifier,
            options: nil
        ) { [weak self] item, error in
            guard let self else {
                completion(nil)
                return
            }

            guard let text = self.text(from: item),
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                if let error {
                    print("Unable to read dropped text:", error)
                }
                completion(nil)
                return
            }

            completion(self.materializeText(text))
        }
    }

    private func preferredImageTypeIdentifier(
        for provider: NSItemProvider
    ) -> String? {
        let concreteImageTypes = provider.registeredTypeIdentifiers.filter {
            identifier in
            guard identifier != UTType.image.identifier,
                let type = UTType(identifier)
            else {
                return false
            }

            return type.conforms(to: .image)
        }

        let preferredTypes = [
            UTType.png.identifier,
            UTType.jpeg.identifier,
            UTType.gif.identifier,
            UTType.tiff.identifier,
        ]

        return preferredTypes.first(where: concreteImageTypes.contains)
            ?? concreteImageTypes.first
    }

    private func preferredTextTypeIdentifier(
        for provider: NSItemProvider
    ) -> String? {
        if provider.hasItemConformingToTypeIdentifier(
            UTType.utf8PlainText.identifier
        ) {
            return UTType.utf8PlainText.identifier
        }

        if provider.hasItemConformingToTypeIdentifier(
            UTType.plainText.identifier
        ) {
            return provider.registeredTypeIdentifiers.first { identifier in
                UTType(identifier)?.conforms(to: .plainText) == true
            } ?? UTType.plainText.identifier
        }

        return provider.registeredTypeIdentifiers.first { identifier in
            UTType(identifier)?.conforms(to: .text) == true
        }
    }

    private func materializeText(
        _ text: String
    ) -> ImportedShelfContent? {
        materialize(
            data: Data(text.utf8),
            suggestedBaseName: suggestedTextName(for: text),
            fileExtension: "txt"
        )
    }

    private func materializeWebLocation(
        _ url: URL
    ) -> ImportedShelfContent? {
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: ["URL": url.absoluteString],
            format: .xml,
            options: 0
        ) else {
            return nil
        }

        let suggestedName = url.host ?? url.lastPathComponent

        return materialize(
            data: data,
            suggestedBaseName: suggestedName.isEmpty ? "Web Link" : suggestedName,
            fileExtension: "webloc"
        )
    }

    private func materialize(
        data: Data,
        suggestedBaseName: String,
        fileExtension: String
    ) -> ImportedShelfContent? {
        do {
            try fileManager.createDirectory(
                at: importDirectory,
                withIntermediateDirectories: true
            )

            let baseName = sanitizedFileName(suggestedBaseName)
            let uniqueSuffix = String(UUID().uuidString.prefix(8))
            let fileName = "\(baseName) \(uniqueSuffix).\(fileExtension)"
            let url = importDirectory.appendingPathComponent(fileName)

            try data.write(to: url, options: .atomic)

            return ImportedShelfContent(
                url: url,
                isManagedByShelf: true
            )
        } catch {
            print("Unable to save imported shelf content:", error)
            return nil
        }
    }

    private func materializeFile(
        at sourceURL: URL
    ) -> ImportedShelfContent? {
        do {
            try fileManager.createDirectory(
                at: importDirectory,
                withIntermediateDirectories: true
            )

            let sourceExtension = sourceURL.pathExtension
            let sourceBaseName = sourceURL
                .deletingPathExtension()
                .lastPathComponent
            let baseName = sanitizedFileName(
                sourceBaseName.isEmpty ? "Image Clip" : sourceBaseName
            )
            let uniqueSuffix = String(UUID().uuidString.prefix(8))
            var fileName = "\(baseName) \(uniqueSuffix)"

            if !sourceExtension.isEmpty {
                fileName += ".\(sourceExtension)"
            }

            let destinationURL = importDirectory
                .appendingPathComponent(fileName)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)

            return ImportedShelfContent(
                url: destinationURL,
                isManagedByShelf: true
            )
        } catch {
            print("Unable to preserve dropped temporary file:", error)
            return nil
        }
    }

    private func suggestedTextName(for text: String) -> String {
        let firstLine = text
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        guard !firstLine.isEmpty else {
            return "Text Clip"
        }

        return String(firstLine.prefix(42))
    }

    private func sanitizedFileName(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\")
            .union(.controlCharacters)
        let components = value.components(separatedBy: invalidCharacters)
        let sanitized = components
            .joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return sanitized.isEmpty ? "Shelf Clip" : String(sanitized.prefix(60))
    }

    private func pngData(for image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    private func url(from item: NSSecureCoding?) -> URL? {
        switch item {
        case let value as URL:
            return value

        case let value as NSURL:
            return value as URL

        case let value as Data:
            return URL(dataRepresentation: value, relativeTo: nil)
                ?? String(data: value, encoding: .utf8).flatMap(URL.init(string:))

        case let value as String:
            return URL(string: value)

        case let value as NSString:
            return URL(string: value as String)

        default:
            return nil
        }
    }

    private func text(from item: NSSecureCoding?) -> String? {
        switch item {
        case let value as String:
            return value

        case let value as NSString:
            return value as String

        case let value as Data:
            return String(data: value, encoding: .utf8)

        default:
            return nil
        }
    }
}
