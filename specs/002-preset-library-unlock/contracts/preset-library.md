# Contract: PresetLibrary package (feature 002)

Foundation only; no UIKit, StoreKit or engine imports (Constitution VI). Runs on Linux.

```swift
public struct IndexedPreset: Sendable, Hashable, Identifiable, Codable {
    public let id: String, name: String, author: String, source: String
    public let folder: [String], path: String, hash: String
}

public struct PresetPackInfo: Sendable, Codable, Identifiable {
    public let id: String, title: String, sourceURL: String, commit: String, license: String
    public let presetCount: Int, authors: [String], locked: Bool
}

public enum PresetScope: Sendable, Hashable {
    case included, pack(String), folder(String, [String]), favorites, search(String), all
    public var storageValue: String { get }            // data-model.md: search stores "all"
    public init?(storageValue: String)
}

public struct PresetNode: Sendable, Identifiable {        // a pack or folder in the browser
    public let id: String, title: String, scope: PresetScope
    public let children: [PresetNode], presetCount: Int, locked: Bool
}

public final class PresetLibrary: Sendable {
    public init(index: Data, packs: Data) throws          // decodes and builds the tree
    public static func load(from bundle: Bundle) async throws -> PresetLibrary   // off the main thread
    public var presets: [IndexedPreset] { get }
    public var packs: [PresetPackInfo] { get }
    public var home: [PresetNode] { get }                 // Included, packs, All (FR-111)
    public func preset(id: String) -> IndexedPreset?
    public func isLocked(_ preset: IndexedPreset, unlocked: Bool) -> Bool
    /// Scope members, alphabetical, playable only (FR-115, FR-118).
    public func members(of scope: PresetScope, unlocked: Bool, favorites: Set<String>,
                        excluded: Set<String>) -> [IndexedPreset]
    /// Name/author search, case- and diacritic-insensitive; grouped by source; at most `limit`.
    public func search(_ query: String, limit: Int) -> (groups: [(source: String, presets: [IndexedPreset])], truncated: Bool)
}

public enum ScopeStepper {
    /// FR-117: alphabetical step with wrap; nil for an empty scope.
    public static func step(_ members: [IndexedPreset], from current: IndexedPreset?, by delta: Int) -> IndexedPreset?
    /// FR-117: uniform, never the current preset when members.count > 1.
    public static func random<G: RandomNumberGenerator>(_ members: [IndexedPreset], excluding current: IndexedPreset?,
                                                         using generator: inout G) -> IndexedPreset?
}
```

Guarantees: `home` counts equal the number of presets per node (FR-111: the app shows total with a
lock before purchase, playable after); `members` never contains a locked or excluded preset;
`search` never returns more than `limit` and sets `truncated` when more matched (FR-113).
