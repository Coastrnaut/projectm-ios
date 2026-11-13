// GeneratorGraphImportError.swift — every reason an imported graph file is refused, each with one
// readable message (SHD-011-R7; data-model.md "GeneratorGraphImportError"). Plain Swift; builds on
// Linux.

import GeneratorGraph

/// What the first bytes of a refused file say it is.
public enum ExecutableKind: String, Sendable, Equatable, CaseIterable {
    case machO, universalBinary, elf, windowsExecutable, script, staticLibrary, metalLibrary, webAssembly

    public var description: String {
        switch self {
        case .machO: return "a Mach-O program or library"
        case .universalBinary: return "a universal binary"
        case .elf: return "an ELF program or library"
        case .windowsExecutable: return "a Windows program"
        case .script: return "a script"
        case .staticLibrary: return "a static library"
        case .metalLibrary: return "a compiled Metal library"
        case .webAssembly: return "a WebAssembly module"
        }
    }
}

public enum GeneratorGraphImportError: Error, Sendable, Equatable, CustomStringConvertible {
    case executableFileType(String)
    case unsupportedFileType(String)
    case empty
    case tooLarge(bytes: Int, limit: Int)
    case executableContent(ExecutableKind)
    case archive(codeEntry: String?)
    case notText
    case notGraphDocument
    case nestingTooDeep(limit: Int)
    case malformed(String)
    case invalidGraph([GeneratorGraphIssue])

    public var message: String {
        switch self {
        case let .executableFileType(ext):
            return "Files of type \".\(ext)\" can contain code and are never imported."
        case let .unsupportedFileType(ext):
            return "Files of type \".\(ext)\" are not generator graphs; use a .json graph file."
        case .empty:
            return "The file is empty."
        case let .tooLarge(bytes, limit):
            return "The file is \(bytes) bytes; graph files are at most \(limit) bytes."
        case let .executableContent(kind):
            return "The file is \(kind.description), not a graph; programs and libraries are never imported."
        case let .archive(entry):
            if let entry {
                return "The file is an archive containing code (\"\(entry)\"); archives are never imported."
            }
            return "The file is an archive; archives are never imported."
        case .notText:
            return "The file is not UTF-8 text."
        case .notGraphDocument:
            return "The file is not a generator graph document (expected a JSON object)."
        case let .nestingTooDeep(limit):
            return "The file nests brackets deeper than \(limit) levels."
        case let .malformed(reason):
            return "The graph document could not be read: \(reason)."
        case let .invalidGraph(issues):
            return issues.map { (i: GeneratorGraphIssue) -> String in i.message }.joined(separator: " ")
        }
    }

    public var description: String { message }
}
