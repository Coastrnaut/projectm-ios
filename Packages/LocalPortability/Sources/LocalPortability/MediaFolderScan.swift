// MediaFolderScan.swift — MED-013 (contract specs/146-med-013-media-relinking/contracts/media-relink.md
// L2; research MED-013-D3): a bounded, read-only search of a user-picked folder for files whose SHA-256 is
// wanted (the payloads of missing media).
//
// * Depth-first in name order (deterministic); hidden files, package contents and symbolic links are
//   skipped (links are never followed, so a folder cannot point the walk anywhere else).
// * Bounds: entries visited, depth, files hashed, bytes per file, bytes hashed in total. Reaching one stops
//   the walk (or skips that file for the per-file size) and `limitReached` says the folder was not fully
//   searched. The walk also stops as soon as every wanted hash was found.
// * Only files with one of `extensions` (lowercased) are hashed. Nothing is written; no file dates or
//   volume capacity are read (privacy manifest).
// The caller holds the folder's security scope. Foundation only (Linux).
import Foundation

public struct MediaFolderScanLimits: Sendable, Equatable {
    public var maxEntries: Int
    public var maxDepth: Int
    public var maxHashedFiles: Int
    public var maxFileBytes: Int64
    public var maxTotalBytes: Int64

    public init(maxEntries: Int = 5_000, maxDepth: Int = 4, maxHashedFiles: Int = 1_000, maxFileBytes: Int64,
                maxTotalBytes: Int64 = 4 << 30) {
        self.maxEntries = maxEntries
        self.maxDepth = maxDepth
        self.maxHashedFiles = maxHashedFiles
        self.maxFileBytes = maxFileBytes
        self.maxTotalBytes = maxTotalBytes
    }
}

public struct MediaFolderScanResult: Sendable, Equatable {
    /// Wanted SHA-256 (lowercase hex) → the first file found with it.
    public var matches: [String: URL] = [:]
    /// Directory entries looked at.
    public var visited: Int = 0
    /// Files hashed.
    public var hashed: Int = 0
    /// A bound stopped the walk or skipped a file: the folder was not fully searched.
    public var limitReached: Bool = false

    public init() {}
}

public enum MediaFolderScan {
    public static func scan(root: URL, wanted: Set<String>, extensions: Set<String>, limits: MediaFolderScanLimits) -> MediaFolderScanResult {
        var state = State(wanted: wanted, extensions: Set(extensions.map { (e: String) -> String in e.lowercased() }), limits: limits)
        guard !wanted.isEmpty else { return state.result }
        state.walk(root, depth: 1)
        return state.result
    }

    private struct State {
        let wanted: Set<String>
        let extensions: Set<String>
        let limits: MediaFolderScanLimits
        var result = MediaFolderScanResult()
        var totalBytes: Int64 = 0
        var stopped = false

        init(wanted: Set<String>, extensions: Set<String>, limits: MediaFolderScanLimits) {
            self.wanted = wanted
            self.extensions = extensions
            self.limits = limits
        }

        #if canImport(Darwin)
        static let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey, .isPackageKey]
        #else
        static let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
        #endif

        static func isPackage(_ values: URLResourceValues?) -> Bool {
            #if canImport(Darwin)
            return values?.isPackage == true
            #else
            return false   // no packages on Linux
            #endif
        }

        mutating func walk(_ folder: URL, depth: Int) {
            let names: [URL] = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Self.keys,
                                                                               options: [.skipsHiddenFiles])) ?? [])
                .sorted { (a: URL, b: URL) -> Bool in a.lastPathComponent < b.lastPathComponent }
            for url in names {
                if stopped { return }
                guard result.visited < limits.maxEntries else {
                    result.limitReached = true
                    stopped = true
                    return
                }
                result.visited += 1
                guard !url.lastPathComponent.hasPrefix(".") else { continue }
                let values = try? url.resourceValues(forKeys: Set(Self.keys))
                if values?.isSymbolicLink == true { continue }
                if values?.isDirectory == true {
                    if Self.isPackage(values) { continue }
                    if depth < limits.maxDepth {
                        walk(url, depth: depth + 1)
                    } else {
                        result.limitReached = true
                    }
                    continue
                }
                guard values?.isRegularFile == true, extensions.contains(url.pathExtension.lowercased()) else { continue }
                consider(url, size: Int64(values?.fileSize ?? 0))
            }
        }

        mutating func consider(_ url: URL, size: Int64) {
            guard size <= limits.maxFileBytes else {
                result.limitReached = true
                return
            }
            guard result.hashed < limits.maxHashedFiles, totalBytes + size <= limits.maxTotalBytes else {
                result.limitReached = true
                stopped = true
                return
            }
            result.hashed += 1
            totalBytes += size
            guard let digest = try? MediaContentHash.digest(ofFileAt: url) else { return }
            if wanted.contains(digest.sha256), result.matches[digest.sha256] == nil {
                result.matches[digest.sha256] = url
                if result.matches.count == wanted.count { stopped = true }
            }
        }
    }
}
