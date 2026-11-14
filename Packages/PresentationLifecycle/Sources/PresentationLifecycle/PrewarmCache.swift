// PrewarmCache.swift — the budgeted store of prewarmed assets (PERF-005-R3, R4; research PERF-005-D4).
//
// * Σ bytes of the entries never exceeds `budgetBytes`.
// * Admission: an item larger than the budget is refused. Otherwise, while it does not fit, entries are
//   evicted: never a live key, only entries whose rank is ≥ the incoming rank (a next-cue entry is never
//   evicted for a later cue's item), least recently used first. If those candidates cannot free enough,
//   the incoming item is refused and nothing is evicted.
// * `take` removes an entry for the live scene (its bytes leave the accounting).
// * Released payloads are returned to the caller, which drops them outside its lock.
// A value type with no clock: recency is a counter bumped by every admit and touch.

/// A loaded asset. `payload` is whatever the loader produced (a texture in the app, a fake buffer in tests).
public final class PrewarmedAsset: @unchecked Sendable {
    public let key: PrewarmKey
    public let bytes: Int
    public let payload: AnyObject

    public init(key: PrewarmKey, bytes: Int, payload: AnyObject) {
        self.key = key
        self.bytes = max(0, bytes)
        self.payload = payload
    }
}

public struct PrewarmCache {
    public struct Entry {
        public let asset: PrewarmedAsset
        public var rank: Int
        public var lastUse: UInt64
    }

    /// Why an admission was refused.
    public enum Refusal: Error, Equatable, Sendable {
        case largerThanBudget
        case cannotFit
    }

    public let budgetBytes: Int
    public private(set) var entries: [PrewarmKey: Entry] = [:]
    public private(set) var heldBytes = 0
    /// The most bytes ever held at once.
    public private(set) var peakBytes = 0
    /// Entries evicted to make room so far.
    public private(set) var evictions = 0
    private var tick: UInt64 = 0

    public init(budgetBytes: Int) {
        self.budgetBytes = max(0, budgetBytes)
    }

    public var keys: Set<PrewarmKey> { Set(entries.keys) }
    public func contains(_ key: PrewarmKey) -> Bool { entries[key] != nil }

    /// Marks `key` as used now with `rank` (a plan names it again).
    public mutating func touch(_ key: PrewarmKey, rank: Int) {
        guard var entry = entries[key] else { return }
        tick &+= 1
        entry.lastUse = tick
        entry.rank = rank
        entries[key] = entry
    }

    /// Admits `asset` at `rank`. Returns the evicted assets, or the refusal (nothing changed then).
    public mutating func admit(_ asset: PrewarmedAsset, rank: Int, live: Set<PrewarmKey>) -> Result<[PrewarmedAsset], Refusal> {
        if asset.bytes > budgetBytes { return .failure(.largerThanBudget) }
        var released: [PrewarmedAsset] = []
        if let existing = entries.removeValue(forKey: asset.key) {   // a reload replaces the old copy
            heldBytes -= existing.asset.bytes
            released.append(existing.asset)
        }
        let needed: Int = heldBytes + asset.bytes - budgetBytes
        var victims: [PrewarmKey] = []
        if needed > 0 {
            let candidates: [(key: PrewarmKey, entry: Entry)] = entries
                .filter { (pair: (key: PrewarmKey, value: Entry)) -> Bool in !live.contains(pair.key) && pair.value.rank >= rank }
                .map { (pair: (key: PrewarmKey, value: Entry)) -> (key: PrewarmKey, entry: Entry) in (pair.key, pair.value) }
                .sorted { (a: (key: PrewarmKey, entry: Entry), b: (key: PrewarmKey, entry: Entry)) -> Bool in a.entry.lastUse < b.entry.lastUse }
            var freed = 0
            for candidate in candidates where freed < needed {
                victims.append(candidate.key)
                freed += candidate.entry.asset.bytes
            }
            if freed < needed {
                if let replaced = released.first {   // put the replaced copy back: nothing changes on a refusal
                    entries[replaced.key] = Entry(asset: replaced, rank: rank, lastUse: tick)
                    heldBytes += replaced.bytes
                }
                return .failure(.cannotFit)
            }
        }
        for key in victims {
            if let entry = entries.removeValue(forKey: key) {
                heldBytes -= entry.asset.bytes
                released.append(entry.asset)
                evictions += 1
            }
        }
        tick &+= 1
        entries[asset.key] = Entry(asset: asset, rank: rank, lastUse: tick)
        heldBytes += asset.bytes
        peakBytes = max(peakBytes, heldBytes)
        return .success(released)
    }

    /// Removes and returns the entry for `key` (the live scene adopts it).
    public mutating func take(_ key: PrewarmKey) -> PrewarmedAsset? {
        guard let entry = entries.removeValue(forKey: key) else { return nil }
        heldBytes -= entry.asset.bytes
        return entry.asset
    }

    /// Removes every entry whose key is neither in `keep` nor live; returns them.
    public mutating func release(keeping keep: Set<PrewarmKey>, live: Set<PrewarmKey>) -> [PrewarmedAsset] {
        var released: [PrewarmedAsset] = []
        for key in entries.keys where !keep.contains(key) && !live.contains(key) {
            if let entry = entries.removeValue(forKey: key) {
                heldBytes -= entry.asset.bytes
                released.append(entry.asset)
            }
        }
        return released
    }
}
