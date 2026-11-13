// ArchivePath.swift — the rules an entry name inside an archive must follow (PRE-014-R13;
// research D5). A name is only ever joined to a folder the app chose after it passed here, so an
// archive cannot name a file outside that folder.
import Foundation

public enum ArchivePathError: Error, Equatable, Sendable {
    case empty
    case tooLong
    case tooDeep
    case absolute
    case backslash
    case colon
    case controlCharacter
    case dotComponent
    case emptyComponent
    case trailingSlash

    public var message: String {
        switch self {
        case .empty: return "The name is empty."
        case .tooLong: return "The name is longer than \(ArchivePath.maxBytes) bytes."
        case .tooDeep: return "The name has more than \(ArchivePath.maxComponents) folder levels."
        case .absolute: return "The name starts at the root of the disk."
        case .backslash: return "The name contains a backslash."
        case .colon: return "The name contains a colon."
        case .controlCharacter: return "The name contains an invisible control character."
        case .dotComponent: return "The name contains “.” or “..”."
        case .emptyComponent: return "The name contains an empty folder name."
        case .trailingSlash: return "The name is a folder, not a file."
        }
    }
}

public enum ArchivePath {
    public static let maxBytes = 255
    public static let maxComponents = 8

    /// Returns `path` when it is a safe relative file path; throws the first rule it breaks.
    @discardableResult
    public static func validate(_ path: String) throws -> String {
        if path.isEmpty { throw ArchivePathError.empty }
        if path.utf8.count > maxBytes { throw ArchivePathError.tooLong }
        for scalar in path.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .privateUse:
                throw ArchivePathError.controlCharacter
            default:
                break
            }
            if scalar == "\\" { throw ArchivePathError.backslash }
            if scalar == ":" { throw ArchivePathError.colon }
        }
        if path.hasPrefix("/") { throw ArchivePathError.absolute }
        if path.hasSuffix("/") { throw ArchivePathError.trailingSlash }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        if components.count > maxComponents { throw ArchivePathError.tooDeep }
        for component in components {
            if component.isEmpty { throw ArchivePathError.emptyComponent }
            if component == "." || component == ".." { throw ArchivePathError.dotComponent }
        }
        return path
    }

    public static func isSafe(_ path: String) -> Bool { (try? validate(path)) != nil }

    /// Two names with equal keys would be the same file on a case-insensitive volume (the iOS and
    /// macOS default) or after Unicode normalization.
    public static func collisionKey(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.lowercased()
    }
}
