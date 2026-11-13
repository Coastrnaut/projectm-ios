// SceneAutosaveDebouncer.swift — when a pending scene edit is due (SCN-002-R2; research SCN-002-D3;
// data-model "SceneAutosaveDebouncer").
//
// A pure state machine on the caller's clock (seconds, monotonic): an edit is due `quiet` seconds
// after the last edit, and never later than `maximumLatency` seconds after the first edit not yet
// committed. Tests drive it with a fake clock; the coordinator with `ProcessInfo.systemUptime`.
import Foundation

struct SceneAutosaveDebouncer: Sendable, Equatable {
    static let defaultQuiet: Double = 1
    static let defaultMaximumLatency: Double = 5

    let quiet: Double
    let maximumLatency: Double
    /// The first edit since the last commit (nil: nothing pending).
    private(set) var firstPending: Double?
    private(set) var lastEdit: Double?

    init(quiet: Double = SceneAutosaveDebouncer.defaultQuiet, maximumLatency: Double = SceneAutosaveDebouncer.defaultMaximumLatency) {
        self.quiet = max(0, quiet)
        self.maximumLatency = max(self.quiet, maximumLatency)
    }

    var isPending: Bool { firstPending != nil }

    /// When the pending edit is due, or nil when nothing is pending.
    var deadline: Double? {
        guard let firstPending, let lastEdit else { return nil }
        return min(lastEdit + quiet, firstPending + maximumLatency)
    }

    /// Records an edit at `now`; returns the new deadline.
    @discardableResult
    mutating func edit(at now: Double) -> Double {
        if firstPending == nil { firstPending = now }
        lastEdit = now
        return deadline ?? now
    }

    func isDue(at now: Double) -> Bool {
        guard let deadline else { return false }
        return now >= deadline
    }

    /// The pending edit was captured for a commit.
    mutating func reset() {
        firstPending = nil
        lastEdit = nil
    }
}
