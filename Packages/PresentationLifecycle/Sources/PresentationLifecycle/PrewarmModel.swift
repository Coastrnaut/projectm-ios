// PrewarmModel.swift — what the PERF-005 prewarm scheduler works on (specs/179-perf-005-prewarm-scheduler,
// data-model.md; research PERF-005-D3).
//
// * `PrewarmKey` names an asset (kind + identifier; a photo's identifier is its stored file's path).
// * `PrewarmItem` is one entry of a plan: the key, its rank (0 = the next cue, 1 = the cue after it) and the
//   source the loader reads.
// * `PrewarmLookahead` lists the cue indices to look ahead to: the next cue and the one after it, no wrap
//   (SHOW-001), standby → cue 1.
// * `PrewarmBudget` sizes the bytes the prewarm cache may hold by device class (physical memory).
// Plain Swift: builds and is tested on Linux.
import Foundation

/// The kinds of media a scene can name. Only photos are loaded by the app today (spec Clarifications).
public enum PrewarmAssetKind: String, Sendable, Hashable {
    case photo
    case video
    case logo
}

/// One asset's identity.
public struct PrewarmKey: Hashable, Sendable, CustomStringConvertible {
    public var kind: PrewarmAssetKind
    public var id: String

    public init(kind: PrewarmAssetKind, id: String) {
        self.kind = kind
        self.id = id
    }

    /// A photo stored at `url` (the file path is its identity).
    public static func photo(_ url: URL) -> PrewarmKey { PrewarmKey(kind: .photo, id: url.standardizedFileURL.path) }

    public var description: String { "\(kind.rawValue):\(id)" }
}

/// One item of a plan.
public struct PrewarmItem: Equatable, Sendable {
    public var key: PrewarmKey
    /// 0 = the next cue (most important), 1 = the cue after it.
    public var rank: Int
    /// What the loader reads (a stored file for a photo).
    public var source: URL?

    public init(key: PrewarmKey, rank: Int, source: URL?) {
        self.key = key
        self.rank = max(0, rank)
        self.source = source
    }

    /// A photo item for the stored file at `url`.
    public static func photo(_ url: URL, rank: Int) -> PrewarmItem { PrewarmItem(key: .photo(url), rank: rank, source: url) }

    /// Orders by rank (stable) and keeps the first (most important) occurrence of each key.
    public static func normalized(_ items: [PrewarmItem]) -> [PrewarmItem] {
        let sorted: [PrewarmItem] = items.enumerated().sorted { (a: (offset: Int, element: PrewarmItem), b: (offset: Int, element: PrewarmItem)) -> Bool in
            a.element.rank != b.element.rank ? a.element.rank < b.element.rank : a.offset < b.offset
        }.map(\.element)
        var seen: Set<PrewarmKey> = []
        var out: [PrewarmItem] = []
        for item in sorted where seen.insert(item.key).inserted { out.append(item) }
        return out
    }
}

/// Which cues to look ahead to.
public enum PrewarmLookahead {
    /// The default look-ahead: the next cue and the one after it.
    public static let defaultDepth = 2

    /// Indices of the cues after `activeIndex` (nil: standby, so cue 1 comes next), at most `depth`, no wrap.
    public static func upcoming(activeIndex: Int?, count: Int, depth: Int = defaultDepth) -> [Int] {
        guard count > 0, depth > 0 else { return [] }
        let first: Int = activeIndex.map { (i: Int) -> Int in i + 1 } ?? 0
        guard first >= 0, first < count else { return [] }
        let last: Int = min(count, first + depth)
        return Array(first..<last)
    }
}

/// The prewarm cache's byte budget by device class (research PERF-005-D3).
public enum PrewarmBudget {
    public static let megabyte = 1024 * 1024

    /// Under 4 GB → 48 MB; under 8 GB → 96 MB; otherwise 192 MB.
    public static func bytes(physicalMemory: UInt64) -> Int {
        let gigabyte: UInt64 = 1024 * 1024 * 1024
        if physicalMemory < 4 * gigabyte { return 48 * megabyte }
        if physicalMemory < 8 * gigabyte { return 96 * megabyte }
        return 192 * megabyte
    }

    /// The budget of this device.
    public static var current: Int { bytes(physicalMemory: ProcessInfo.processInfo.physicalMemory) }
}
