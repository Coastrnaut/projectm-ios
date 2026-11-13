// StorageUsage.swift — FILE-009 storage usage explorer: how much space the app's own data takes, per
// category. Contract: specs/071-file-009-storage-usage-explorer/contracts/storage-usage.md.
//
// The walk is iterative (an explicit stack, no recursion), counts regular files only, never enters a
// symbolic link, never walks a root outside the container, and stops at a depth and an entry limit
// (FILE-009-R3, R4). It reads file lengths and allocated sizes only: no file dates (privacy manifest
// FileTimestamp) and no volume capacity (DiskSpace) (FILE-009-R8). The directory reader is a protocol
// so the logic is tested on the Mac host and on Linux with an injected tree (FILE-009-R9).
import Foundation

/// The Storage screen's categories, in display order (FILE-009-R1).
public enum StorageCategory: String, CaseIterable, Sendable, Hashable {
    case photos, videos, scenes, presets, importedAudio, recordings, sharesAndExports, caches, otherAppData

    public var title: String {
        switch self {
        case .photos: "Photos"
        case .videos: "Videos"
        case .scenes: "Scenes"
        case .presets: "Presets"
        case .importedAudio: "Imported audio"
        case .recordings: "Recordings"
        case .sharesAndExports: "Shares and exports"
        case .caches: "Caches"
        case .otherAppData: "Other app data"
        }
    }
}

/// One item of a directory listing.
public struct StorageEntry: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case file, directory, symbolicLink, other }

    public var name: String
    public var kind: Kind
    /// The file's length in bytes (regular files; 0 otherwise).
    public var contentBytes: Int64
    /// The bytes the file system allocated for it (equal to `contentBytes` where not reported).
    public var spaceUsed: Int64

    public init(name: String, kind: Kind, contentBytes: Int64 = 0, spaceUsed: Int64? = nil) {
        self.name = name
        self.kind = kind
        self.contentBytes = contentBytes
        self.spaceUsed = spaceUsed ?? contentBytes
    }
}

/// Lists one directory level at a time. The real reader is `FileManagerStorageReader`.
public protocol StorageDirectoryReading: Sendable {
    /// The kind of the item at `path` without following a link at its end; nil when it does not exist.
    func kind(atPath path: String) -> StorageEntry.Kind?
    /// The items directly inside `path`.
    func entries(inDirectory path: String) throws -> [StorageEntry]
    /// `path` with links in the path itself resolved and `.`/`..` removed (roots only, never walked items).
    func resolvedPath(_ path: String) -> String
}

/// Walk limits (FILE-009-R4).
public struct StorageWalkLimits: Sendable, Equatable {
    /// Folders deeper than this below a root are not entered.
    public var maxDepth: Int
    /// Items listed per walk (one walk per category root and one for other app data).
    public var maxEntriesPerWalk: Int

    public static let standard = StorageWalkLimits(maxDepth: 32, maxEntriesPerWalk: 100_000)

    public init(maxDepth: Int, maxEntriesPerWalk: Int) {
        self.maxDepth = max(0, maxDepth)
        self.maxEntriesPerWalk = max(0, maxEntriesPerWalk)
    }
}

/// The regular files counted in one category.
public struct StorageUsage: Sendable, Equatable {
    public var contentBytes: Int64 = 0
    public var spaceUsed: Int64 = 0
    public var fileCount: Int = 0

    public init(contentBytes: Int64 = 0, spaceUsed: Int64 = 0, fileCount: Int = 0) {
        self.contentBytes = contentBytes
        self.spaceUsed = spaceUsed
        self.fileCount = fileCount
    }

    mutating func add(_ other: StorageUsage) {
        contentBytes += other.contentBytes
        spaceUsed += other.spaceUsed
        fileCount += other.fileCount
    }
}

/// What to measure: the app container and each category's folders inside it.
public struct StorageRequest: Sendable, Equatable {
    public var container: String
    /// Folders per category; `otherAppData` is ignored (it is the rest of the container).
    public var roots: [StorageCategory: [String]]

    public init(container: String, roots: [StorageCategory: [String]]) {
        self.container = container
        self.roots = roots
    }
}

/// The result of one measurement.
public struct StorageReport: Sendable, Equatable {
    public let usages: [StorageCategory: StorageUsage]
    /// False when a limit was reached or a folder could not be read: sizes may be higher.
    public let isComplete: Bool
    /// Roots not walked: links, or outside the container.
    public let skippedRoots: [String]

    public init(usages: [StorageCategory: StorageUsage], isComplete: Bool, skippedRoots: [String]) {
        self.usages = usages
        self.isComplete = isComplete
        self.skippedRoots = skippedRoots
    }

    public func usage(_ category: StorageCategory) -> StorageUsage { usages[category] ?? StorageUsage() }

    /// The sum of every category.
    public var total: StorageUsage {
        var sum = StorageUsage()
        for category in StorageCategory.allCases { sum.add(usage(category)) }
        return sum
    }
}

public struct StorageUsageCalculator: Sendable {
    /// Cancellation is checked once per this many listed items (and once per folder).
    public static let cancellationStride = 256

    public let reader: any StorageDirectoryReading
    public let limits: StorageWalkLimits

    public init(reader: any StorageDirectoryReading = FileManagerStorageReader(), limits: StorageWalkLimits = .standard) {
        self.reader = reader
        self.limits = limits
    }

    /// Measures every category. Throws `CancellationError` when the current task is cancelled.
    public func measure(_ request: StorageRequest) throws -> StorageReport {
        let container = reader.resolvedPath(request.container)
        var usages: [StorageCategory: StorageUsage] = [:]
        var complete = true
        var skipped: [String] = []

        // Resolve and vet every category root first, so each walk can exclude the others.
        var vetted: [(StorageCategory, String)] = []
        for category in StorageCategory.allCases where category != .otherAppData {
            for root in request.roots[category] ?? [] {
                if reader.kind(atPath: root) == .symbolicLink {
                    skipped.append(root)
                    continue
                }
                let resolved = reader.resolvedPath(root)
                guard Self.isStrictlyInside(resolved, container) else {
                    skipped.append(root)
                    continue
                }
                if !vetted.contains(where: { (pair: (StorageCategory, String)) -> Bool in pair.1 == resolved }) {
                    vetted.append((category, resolved))
                }
            }
        }
        let allRoots = Set(vetted.map { (pair: (StorageCategory, String)) -> String in pair.1 })

        for (category, root) in vetted {
            var usage = usages[category] ?? StorageUsage()
            try walk(root: root, excluding: allRoots.subtracting([root]), into: &usage, complete: &complete)
            usages[category] = usage
        }
        if reader.kind(atPath: container) == .directory {
            var other = StorageUsage()
            try walk(root: container, excluding: allRoots, into: &other, complete: &complete)
            usages[.otherAppData] = other
        }
        return StorageReport(usages: usages, isComplete: complete, skippedRoots: skipped)
    }

    private func walk(root: String, excluding excluded: Set<String>, into usage: inout StorageUsage,
                      complete: inout Bool) throws {
        switch reader.kind(atPath: root) {
        case nil, .symbolicLink, .other, .file:
            // Missing (zero), a link (never entered) or not a folder.
            return
        case .directory:
            break
        }
        var stack: [(path: String, depth: Int)] = [(root, 0)]
        var listed = 0
        while let (directory, depth) = stack.popLast() {
            if Task.isCancelled { throw CancellationError() }
            let children: [StorageEntry]
            do {
                children = try reader.entries(inDirectory: directory)
            } catch {
                complete = false
                continue
            }
            for child in children {
                if listed >= limits.maxEntriesPerWalk {
                    complete = false
                    return
                }
                listed += 1
                if listed % Self.cancellationStride == 0, Task.isCancelled { throw CancellationError() }
                // A hostile or broken listing never steers the walk out of its folder.
                if child.name.isEmpty || child.name == "." || child.name == ".." || child.name.contains("/") { continue }
                switch child.kind {
                case .file:
                    usage.add(Self.usage(of: child))
                case .directory:
                    let path = directory.hasSuffix("/") ? directory + child.name : directory + "/" + child.name
                    if excluded.contains(path) { continue }
                    if depth + 1 > limits.maxDepth {
                        complete = false
                    } else {
                        stack.append((path, depth + 1))
                    }
                case .symbolicLink, .other:
                    continue
                }
            }
        }
    }

    private static func usage(of entry: StorageEntry) -> StorageUsage {
        StorageUsage(contentBytes: max(0, entry.contentBytes), spaceUsed: max(0, entry.spaceUsed), fileCount: 1)
    }

    static func isStrictlyInside(_ path: String, _ container: String) -> Bool {
        let base = container.hasSuffix("/") ? container : container + "/"
        return path.hasPrefix(base) && path.count > base.count
    }
}

/// The real file system. Requests only length, allocation and type keys (no dates, no volume keys).
public struct FileManagerStorageReader: StorageDirectoryReading {
    static let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
                                         .fileSizeKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]

    public init() {}

    public func kind(atPath path: String) -> StorageEntry.Kind? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: Set(Self.keys)) else { return nil }
        return Self.kind(values)
    }

    public func entries(inDirectory path: String) throws -> [StorageEntry] {
        let url = URL(fileURLWithPath: path)
        let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Self.keys, options: [])
        return children.map { (child: URL) -> StorageEntry in
            guard let values = try? child.resourceValues(forKeys: Set(Self.keys)) else {
                return StorageEntry(name: child.lastPathComponent, kind: .other)
            }
            return Self.entry(named: child.lastPathComponent, values)
        }
    }

    public func resolvedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func kind(_ values: URLResourceValues) -> StorageEntry.Kind {
        if values.isSymbolicLink == true { return .symbolicLink }
        if values.isRegularFile == true { return .file }
        if values.isDirectory == true { return .directory }
        return .other
    }

    static func entry(named name: String, _ values: URLResourceValues) -> StorageEntry {
        let kind = kind(values)
        guard kind == .file else { return StorageEntry(name: name, kind: kind) }
        let content = Int64(values.fileSize ?? 0)
        let allocated: Int64? = (values.totalFileAllocatedSize ?? values.fileAllocatedSize).map { (n: Int) -> Int64 in Int64(n) }
        return StorageEntry(name: name, kind: .file, contentBytes: content, spaceUsed: allocated)
    }
}
