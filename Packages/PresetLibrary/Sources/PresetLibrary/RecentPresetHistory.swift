// RecentPresetHistory.swift — roadmap PRE-006 (specs/159-pre-006-recent-history; research PRE-006-D1-D3):
// the recently played list's rules, Foundation only so they are tested on Linux.
//
// * `RecentPresetHistory`: preset IDs only, most recent first, no empty or duplicate IDs, at most 50
//   (R1). Recording an ID already listed moves it to the front. Reading a stored value is lenient (R8).
// * `RecentPresetDwell`: what counts as played (R2). The preset loaded last is the candidate; it is due
//   once `threshold` seconds have passed on the caller's monotonic clock. A newer load replaces it;
//   turning history off or clearing cancels it. Tests drive the clock explicitly.
import Foundation

public struct RecentPresetHistory: Sendable, Equatable {
    /// The most IDs kept (PRE-006-R1).
    public static let capacity = 50

    /// Most recent first.
    public private(set) var ids: [String]

    public init(ids: [String] = []) {
        var seen: Set<String> = []
        var kept: [String] = []
        for id in ids where !id.isEmpty && !seen.contains(id) {
            seen.insert(id)
            kept.append(id)
            if kept.count == Self.capacity { break }
        }
        self.ids = kept
    }

    /// PRE-006-R8: a stored value read leniently. Anything but an array is empty; entries that are not
    /// strings, empty IDs and later duplicates are dropped; the rest is trimmed to `capacity`.
    public init(storedValue: Any?) {
        guard let values = storedValue as? [Any] else {
            self.init()
            return
        }
        let strings: [String] = values.compactMap { (value: Any) -> String? in value as? String }
        self.init(ids: strings)
    }

    public var isEmpty: Bool { ids.isEmpty }

    /// Moves `id` to the front (inserting it when new) and drops entries past `capacity`.
    public mutating func record(_ id: String) {
        guard !id.isEmpty else { return }
        ids.removeAll { (existing: String) -> Bool in existing == id }
        ids.insert(id, at: 0)
        if ids.count > Self.capacity { ids.removeLast(ids.count - Self.capacity) }
    }

    public mutating func clear() { ids = [] }

    /// PRE-018-R9: the list without `removed`, order kept.
    public func removing(_ removed: Set<String>) -> RecentPresetHistory {
        RecentPresetHistory(ids: ids.filter { (id: String) -> Bool in !removed.contains(id) })
    }
}

public struct RecentPresetDwell: Sendable, Equatable {
    /// Seconds a preset must stay on screen to count as played (PRE-006-R2).
    public static let threshold: Double = 3

    public struct Candidate: Sendable, Equatable {
        public let id: String
        public let since: Double
    }

    public private(set) var candidate: Candidate?

    public init() {}

    /// `id` loaded successfully at `now` (monotonic seconds): it replaces any earlier candidate.
    public mutating func shown(_ id: String, at now: Double) {
        candidate = Candidate(id: id, since: now)
    }

    /// When the candidate becomes due, or nil.
    public var deadline: Double? { candidate.map { (value: Candidate) -> Double in value.since + Self.threshold } }

    /// The candidate's ID once its dwell has passed at `now` (the candidate is then cleared), else nil.
    public mutating func due(at now: Double) -> String? {
        guard let candidate, let deadline, now >= deadline else { return nil }
        self.candidate = nil
        return candidate.id
    }

    public mutating func cancel() { candidate = nil }
}
