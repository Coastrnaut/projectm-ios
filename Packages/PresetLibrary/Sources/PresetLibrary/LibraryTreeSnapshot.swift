// LibraryTreeSnapshot.swift — FILE-003 (specs/105-file-003-import-dry-run; research FILE-003-D2): what
// "byte-for-byte unchanged" means for a library on disk. For each root: whether it exists, every
// directory below it, and every file's relative path with the SHA-256 of its bytes. Two snapshots
// are equal exactly when no byte, file or folder was added, changed or removed. Symbolic links are
// recorded by their target path, never followed. Reads only.
import Foundation

public struct LibraryTreeSnapshot: Sendable, Equatable, CustomStringConvertible {
    /// "<root index>/<relative path>" → SHA-256 hex of the file's bytes.
    public let files: [String: String]
    /// "<root index>/<relative path>" of every directory, and "<root index>/" for each existing root.
    public let directories: Set<String>

    public init(files: [String: String], directories: Set<String>) {
        self.files = files
        self.directories = directories
    }

    /// Walks every root (a missing root is recorded as absent).
    public static func take(_ roots: [URL]) -> LibraryTreeSnapshot {
        var files: [String: String] = [:]
        var directories: Set<String> = []
        let manager = FileManager.default
        for (index, root) in roots.enumerated() {
            let prefix = "\(index)/"
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory) else { continue }
            guard isDirectory.boolValue else {
                files[prefix] = hash(of: root)
                continue
            }
            directories.insert(prefix)
            let base = root.standardizedFileURL.resolvingSymlinksInPath().path
            guard let enumerator = manager.enumerator(atPath: base) else { continue }
            while let next = enumerator.nextObject() as? String {
                let full = (base as NSString).appendingPathComponent(next)
                let key = prefix + next
                let attributes = try? manager.attributesOfItem(atPath: full)
                let type = attributes?[.type] as? FileAttributeType
                if type == .typeDirectory {
                    directories.insert(key)
                } else if type == .typeSymbolicLink {
                    files[key] = "link:" + ((try? manager.destinationOfSymbolicLink(atPath: full)) ?? "?")
                } else {
                    files[key] = hash(of: URL(fileURLWithPath: full))
                }
            }
        }
        return LibraryTreeSnapshot(files: files, directories: directories)
    }

    private static func hash(of url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "unreadable" }
        return ContentHash.sha256Hex([UInt8](data))
    }

    /// SHA-256 of the sorted listing: one short value for UI probes.
    public var digest: String {
        var lines: [String] = []
        lines.reserveCapacity(files.count + directories.count)
        for path in directories.sorted() { lines.append("d " + path) }
        for path in files.keys.sorted() { lines.append("f " + path + " " + (files[path] ?? "")) }
        return ContentHash.sha256Hex(Array(lines.joined(separator: "\n").utf8))
    }

    public var description: String { "\(directories.count) directories, \(files.count) files, digest \(digest.prefix(12))" }

    /// The paths that differ from `other` (tests print them on failure).
    public func differences(from other: LibraryTreeSnapshot) -> [String] {
        var result: [String] = []
        for path in directories.symmetricDifference(other.directories).sorted() { result.append("directory " + path) }
        let allFiles = Set(files.keys).union(other.files.keys)
        for path in allFiles.sorted() where files[path] != other.files[path] { result.append("file " + path) }
        return result
    }
}
