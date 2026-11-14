// PresetLibrary+WarmStart.swift — PERF-009 (contracts/warm-cache.md W5; PERF-009-R5): the library load through the
// warm cache. The entry `preset-library` is keyed by the app identity, format `snapshotFormatVersion`, no GPU, and
// the SHA-256 of the index file followed by the packs file, so any change to the bundled library (or the app, the
// OS, the snapshot format) rebuilds it. A hit skips the decode, sort and search-key folding.
import Foundation
import LocalPortability

extension PresetLibrary {
    public static let warmCacheEntry = "preset-library"

    /// The library's warm-cache key for these input files.
    public static func warmCacheKey(index: Data, packs: Data, identity: WarmStartIdentity) -> WarmCacheKey {
        identity.key(gpuFamily: WarmCacheKey.noGPU, formatVersion: snapshotFormatVersion,
                     contentHash: WarmCacheHash.sha256Hex([index, packs]))
    }

    /// The library from `store` when its entry is valid, otherwise prepared from `index` and `packs` and stored.
    /// `store` nil prepares without a cache.
    public static func loadWarm(index: Data, packs: Data, store: WarmCacheStore?,
                                identity: WarmStartIdentity) throws -> WarmStartResult<PresetLibrary> {
        try WarmStartLoader.load(warmCacheEntry, key: warmCacheKey(index: index, packs: packs, identity: identity), store: store,
                                 decode: { (data: Data) throws -> PresetLibrary in try PresetLibrary(snapshot: data) },
                                 build: { () throws -> PresetLibrary in try PresetLibrary(index: index, packs: packs) },
                                 encode: { (library: PresetLibrary) throws -> Data in try library.snapshotData() })
    }

    /// `load(from:)` through the warm cache, off the main thread (SC-101).
    public static func load(from bundle: Bundle, store: WarmCacheStore?,
                            identity: WarmStartIdentity) async throws -> WarmStartResult<PresetLibrary> {
        try await Task.detached(priority: .userInitiated) { () throws -> WarmStartResult<PresetLibrary> in
            guard let index = bundle.url(forResource: "PresetIndex", withExtension: "json") else {
                throw PresetLibraryError.missingResource("PresetIndex.json")
            }
            guard let packs = bundle.url(forResource: "PresetPacks", withExtension: "json") else {
                throw PresetLibraryError.missingResource("PresetPacks.json")
            }
            return try loadWarm(index: Data(contentsOf: index, options: .mappedIfSafe), packs: Data(contentsOf: packs),
                                store: store, identity: identity)
        }.value
    }
}
