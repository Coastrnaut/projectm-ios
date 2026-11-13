// CacheCleanup.swift — FILE-010 safe cache cleanup: plans and clears the cache and intermediate folders
// FILE-009 measures, and nothing else. Contract: specs/072-file-010-safe-cache-cleanup/contracts/cache-cleanup.md.
//
// Allowlist (C1): only roots of the cleanable categories are planned; a root that is a link, is the
// container or outside it, overlaps a protected (user-data) root or repeats another is refused. The root
// folder itself is never removed. Links are never followed (C2): a link is removed as a link. Before each
// removal the item is checked again (C3): still inside its root, no folder above it became a link, not in
// use now. No file dates and no volume capacity are read (FILE-010-R7). The file system is a protocol so
// the logic is tested on the Mac host and on Linux with an injected tree (FILE-010-R8).
import Foundation

extension StorageCategory {
    /// The categories Clear Caches empties (FILE-010-R1).
    public static let cleanable: Set<StorageCategory> = [.recordings, .sharesAndExports, .caches]

    public var isCleanable: Bool { Self.cleanable.contains(self) }
}

/// FILE-009's directory reader plus removal of one item (a link is removed as a link).
public protocol CacheCleanupFileSystem: StorageDirectoryReading {
    func removeItem(atPath path: String) throws
}

/// The real file system.
public struct FileManagerCacheCleanupFileSystem: CacheCleanupFileSystem {
    private let reader = FileManagerStorageReader()

    public init() {}

    public func kind(atPath path: String) -> StorageEntry.Kind? { reader.kind(atPath: path) }
    public func entries(inDirectory path: String) throws -> [StorageEntry] { try reader.entries(inDirectory: path) }
    public func resolvedPath(_ path: String) -> String { reader.resolvedPath(path) }
    public func removeItem(atPath path: String) throws { try FileManager.default.removeItem(atPath: path) }
}

/// What to clean.
public struct CacheCleanupRequest: Sendable, Equatable {
    public var container: String
    /// Folders per category; only `StorageCategory.cleanable` categories are planned.
    public var cacheRoots: [StorageCategory: [String]]
    /// User-data folders: a cache root that equals, contains or lies inside one is refused.
    public var protectedRoots: [String]
    /// Absolute paths the running app must keep (a file, or a folder kept whole).
    public var inUse: Set<String>

    public init(container: String, cacheRoots: [StorageCategory: [String]], protectedRoots: [String], inUse: Set<String> = []) {
        self.container = container
        self.cacheRoots = cacheRoots
        self.protectedRoots = protectedRoots
        self.inUse = inUse
    }
}

public enum CacheCleanupRefusal: String, Sendable, Equatable {
    case notCleanable, symbolicLink, outsideContainer, overlapsProtected, duplicate
}

/// One item to remove: a direct or nested child of a vetted root.
public struct CacheCleanupItem: Sendable, Equatable {
    public let path: String
    public let root: String
    public let category: StorageCategory
    public let kind: StorageEntry.Kind
    /// The regular files it holds (a link or other item: zero).
    public let usage: StorageUsage
}

public struct CacheCleanupPlan: Sendable, Equatable {
    public let items: [CacheCleanupItem]
    /// Refused roots as requested, with the reason.
    public let refused: [String: CacheCleanupRefusal]
    /// Paths kept because they are in use.
    public let keptInUse: [String]
    /// False when a walk limit was reached or a folder could not be read: `bytesToFree` is a lower bound.
    public let isComplete: Bool

    public var isEmpty: Bool { items.isEmpty }

    /// The space the items take (what the confirmation states).
    public var bytesToFree: Int64 {
        items.reduce(Int64(0)) { (sum: Int64, item: CacheCleanupItem) -> Int64 in sum + item.usage.spaceUsed }
    }

    public func usage(_ category: StorageCategory) -> StorageUsage {
        var total = StorageUsage()
        for item in items where item.category == category { total.add(item.usage) }
        return total
    }
}

public struct CacheCleanupResult: Sendable, Equatable {
    public var removed: [String] = []
    public var failed: [String] = []
    public var vanished: [String] = []
    public var keptInUse: [String] = []
    public var bytesFreed: Int64 = 0

    public init() {}
}

public struct CacheCleaner: Sendable {
    public let fileSystem: any CacheCleanupFileSystem
    public let limits: StorageWalkLimits

    public init(fileSystem: any CacheCleanupFileSystem = FileManagerCacheCleanupFileSystem(), limits: StorageWalkLimits = .standard) {
        self.fileSystem = fileSystem
        self.limits = limits
    }

    // MARK: - Plan (C1, C2)

    public func plan(_ request: CacheCleanupRequest) throws -> CacheCleanupPlan {
        let container = fileSystem.resolvedPath(request.container)
        let protected = request.protectedRoots.map { (path: String) -> String in fileSystem.resolvedPath(path) }
        let inUse = resolvedInUse(request.inUse)
        var refused: [String: CacheCleanupRefusal] = [:]
        var vetted: [(StorageCategory, String)] = []

        for category in StorageCategory.allCases {
            for root in request.cacheRoots[category] ?? [] {
                guard category.isCleanable else { refused[root] = .notCleanable; continue }
                if fileSystem.kind(atPath: root) == .symbolicLink { refused[root] = .symbolicLink; continue }
                let resolved = fileSystem.resolvedPath(root)
                guard StorageUsageCalculator.isStrictlyInside(resolved, container) else { refused[root] = .outsideContainer; continue }
                if protected.contains(where: { (user: String) -> Bool in Self.overlaps(resolved, user) }) {
                    refused[root] = .overlapsProtected
                    continue
                }
                if vetted.contains(where: { (pair: (StorageCategory, String)) -> Bool in Self.overlaps(pair.1, resolved) }) {
                    refused[root] = .duplicate
                    continue
                }
                vetted.append((category, resolved))
            }
        }

        var items: [CacheCleanupItem] = []
        var kept: [String] = []
        var complete = true
        for (category, root) in vetted where fileSystem.kind(atPath: root) == .directory {
            if Task.isCancelled { throw CancellationError() }
            // Folders to list: the root, then any child folder that holds an in-use path.
            var stack: [(path: String, depth: Int)] = [(root, 0)]
            while let (directory, depth) = stack.popLast() {
                let children: [StorageEntry]
                do {
                    children = try fileSystem.entries(inDirectory: directory)
                } catch {
                    complete = false
                    continue
                }
                for child in children where Self.isPlainName(child.name) {
                    let path = Self.join(directory, child.name)
                    if Self.isInUse(path, inUse) {
                        kept.append(path)
                    } else if Self.holdsInUse(path, inUse) {
                        // Enter it to plan its other children; too deep: keep it whole.
                        if child.kind == .directory, depth < limits.maxDepth {
                            stack.append((path, depth + 1))
                        } else {
                            kept.append(path)
                            complete = false
                        }
                    } else {
                        let usage: StorageUsage
                        switch child.kind {
                        case .file: usage = StorageUsage(contentBytes: max(0, child.contentBytes), spaceUsed: max(0, child.spaceUsed), fileCount: 1)
                        case .directory: usage = try folderUsage(path, complete: &complete)
                        case .symbolicLink, .other: usage = StorageUsage()
                        }
                        items.append(CacheCleanupItem(path: path, root: root, category: category, kind: child.kind, usage: usage))
                    }
                }
            }
        }
        return CacheCleanupPlan(items: items, refused: refused, keptInUse: kept, isComplete: complete)
    }

    // MARK: - Execute (C3)

    /// Removes the plan's items, re-checking each one; `inUse` is gathered again just before clearing.
    public func execute(_ plan: CacheCleanupPlan, inUse: Set<String> = []) -> CacheCleanupResult {
        let inUse = resolvedInUse(inUse)
        var result = CacheCleanupResult()
        var vettedRoots: [String: Bool] = [:]
        for item in plan.items {
            if Self.isInUse(item.path, inUse) || Self.holdsInUse(item.path, inUse) {
                result.keptInUse.append(item.path)
                continue
            }
            let rootIsSafe: Bool
            if let known = vettedRoots[item.root] {
                rootIsSafe = known
            } else {
                rootIsSafe = fileSystem.kind(atPath: item.root) == .directory && fileSystem.resolvedPath(item.root) == item.root
                vettedRoots[item.root] = rootIsSafe
            }
            let parent = Self.parent(of: item.path)
            guard rootIsSafe, StorageUsageCalculator.isStrictlyInside(item.path, item.root),
                  fileSystem.resolvedPath(parent) == parent else {
                result.failed.append(item.path)
                continue
            }
            guard fileSystem.kind(atPath: item.path) != nil else {
                result.vanished.append(item.path)
                continue
            }
            do {
                try fileSystem.removeItem(atPath: item.path)
                result.removed.append(item.path)
                result.bytesFreed += item.usage.spaceUsed
            } catch {
                result.failed.append(item.path)
            }
        }
        return result
    }

    // MARK: - Helpers

    private func resolvedInUse(_ paths: Set<String>) -> Set<String> {
        // Resolve the parent only: the item itself may be a link, which is kept as a link.
        Set(paths.map { (path: String) -> String in
            let parent = Self.parent(of: path)
            let name = (path as NSString).lastPathComponent
            return Self.join(fileSystem.resolvedPath(parent), name)
        })
    }

    /// The regular files below `folder`, with FILE-009's limits; links are never entered.
    private func folderUsage(_ folder: String, complete: inout Bool) throws -> StorageUsage {
        var usage = StorageUsage()
        var stack: [(path: String, depth: Int)] = [(folder, 0)]
        var listed = 0
        while let (directory, depth) = stack.popLast() {
            if Task.isCancelled { throw CancellationError() }
            let children: [StorageEntry]
            do {
                children = try fileSystem.entries(inDirectory: directory)
            } catch {
                complete = false
                continue
            }
            for child in children where Self.isPlainName(child.name) {
                if listed >= limits.maxEntriesPerWalk {
                    complete = false
                    return usage
                }
                listed += 1
                switch child.kind {
                case .file:
                    usage.add(StorageUsage(contentBytes: max(0, child.contentBytes), spaceUsed: max(0, child.spaceUsed), fileCount: 1))
                case .directory:
                    if depth + 1 > limits.maxDepth {
                        complete = false
                    } else {
                        stack.append((Self.join(directory, child.name), depth + 1))
                    }
                case .symbolicLink, .other:
                    continue
                }
            }
        }
        return usage
    }

    static func isPlainName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/")
    }

    static func join(_ directory: String, _ name: String) -> String {
        directory.hasSuffix("/") ? directory + name : directory + "/" + name
    }

    static func parent(of path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }

    /// Equal, or one inside the other.
    static func overlaps(_ a: String, _ b: String) -> Bool {
        a == b || StorageUsageCalculator.isStrictlyInside(a, b) || StorageUsageCalculator.isStrictlyInside(b, a)
    }

    /// `path` is an in-use path or lies inside one.
    static func isInUse(_ path: String, _ inUse: Set<String>) -> Bool {
        inUse.contains(path) || inUse.contains(where: { (used: String) -> Bool in StorageUsageCalculator.isStrictlyInside(path, used) })
    }

    /// An in-use path lies inside `path`.
    static func holdsInUse(_ path: String, _ inUse: Set<String>) -> Bool {
        inUse.contains(where: { (used: String) -> Bool in StorageUsageCalculator.isStrictlyInside(used, path) })
    }
}
