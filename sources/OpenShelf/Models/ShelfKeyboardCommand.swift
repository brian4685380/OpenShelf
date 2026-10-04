import AppKit

enum ShelfKeyboardCommand: Equatable {
    case selectAll, copy, copyPaths, paste, remove, open, preview, escape, togglePin
    case navigate(direction: Int, extending: Bool)

    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == .command {
            switch key {
            case "a": self = .selectAll
            case "c": self = .copy
            case "v": self = .paste
            case "o": self = .open
            case "p": self = .togglePin
            default: return nil
            }
        } else if modifiers == [.command, .option], key == "c" {
            self = .copyPaths
        } else if modifiers.isEmpty || modifiers == .shift {
            switch event.keyCode {
            case 125: self = .navigate(direction: 1, extending: modifiers == .shift)
            case 126: self = .navigate(direction: -1, extending: modifiers == .shift)
            default:
                guard modifiers.isEmpty else { return nil }
                switch event.keyCode {
                case 51, 117: self = .remove
                case 36, 76: self = .open
                case 49: self = .preview
                case 53: self = .escape
                default: return nil
                }
            }
        } else {
            return nil
        }
    }
}
