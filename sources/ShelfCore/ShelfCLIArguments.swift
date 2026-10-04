import Foundation

public enum OpenShelfVersion {
    public static let current = "0.7.0"
}

public enum ShelfCLIArguments: Equatable {
    case help, version, files([String])

    public init(_ arguments: [String]) throws {
        guard !arguments.isEmpty else { throw ArgumentError.missingFiles }
        if arguments == ["--help"] || arguments == ["-h"] { self = .help; return }
        if arguments == ["--version"] || arguments == ["-v"] { self = .version; return }
        var paths: [String] = []
        var optionsEnded = false
        for argument in arguments {
            if !optionsEnded, argument == "--" { optionsEnded = true; continue }
            if !optionsEnded, argument.hasPrefix("-") { throw ArgumentError.unknownOption(argument) }
            paths.append(argument)
        }
        guard !paths.isEmpty else { throw ArgumentError.missingFiles }
        self = .files(paths)
    }

    public enum ArgumentError: Error, CustomStringConvertible {
        case missingFiles, unknownOption(String)
        public var description: String {
            switch self {
            case .missingFiles: return "provide at least one file or folder"
            case .unknownOption(let option): return "unknown option: \(option) (use -- before a filename beginning with -)"
            }
        }
    }

    public static let usage = """
    Usage: shelf [--] <file-or-folder> [...]
           shelf --help
           shelf --version

    Add files and folders to OpenShelf, launching the app if needed.
    Relative paths and multiple files are supported. Quote paths with spaces.
    Success is reported only after the app acknowledges the request.

    Examples:
      shelf ~/Desktop/report.pdf ~/Downloads/photos
      shelf "Design notes.txt"
      shelf -- -draft.txt

    Exit codes: 0 received, 64 usage, 66 missing file, 69 app unavailable,
                75 acknowledgment timed out.
    """
}

public enum ShelfCommandProtocol {
    public static let addFiles = Notification.Name("com.brianyuan.OpenShelf.cli.addFiles")
    public static let acknowledged = Notification.Name("com.brianyuan.OpenShelf.cli.acknowledged")
}
