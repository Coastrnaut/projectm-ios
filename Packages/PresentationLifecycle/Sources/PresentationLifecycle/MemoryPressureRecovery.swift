// MemoryPressureRecovery.swift — what the app frees on memory pressure, and when (PERF-006-R1 to R5,
// R14; research PERF-006-D2 to D4; specs/054-perf-006-memory-warning-recovery/contracts/
// memory-pressure-recovery.md).
//
// Owners register responders (held weakly) with a name, a tier and an estimate of what they can free:
//
// * cache: dropped on every signal, rebuilt lazily by the owner (idle pictures, a background engine's
//   context, decompressed data, a visual that is not shown);
// * optional: background work shed only when the signal escalates (critical, or a warning within
//   `repeatWindowSeconds` of the previous signal) and restored once when the cool-down ends
//   (`coolDownSeconds` after the last escalating signal).
//
// Cache responders run first, in registration order, then optional ones. A signal raised from inside
// a responder is queued and handled after the running one, never nested. Time is a monotonic value in
// seconds passed by the caller, so the policy never reads a clock. Nothing visible to the user and no
// stored setting belongs in a responder: the shown visual and the audio source are never freed.

/// How hard the system is pushing.
public enum MemoryPressureLevel: String, Sendable {
    case warning
    case critical
}

/// When a responder is asked to release.
public enum MemoryPressureTier: String, Sendable {
    /// On every signal.
    case cache
    /// Only on escalation; restored after the cool-down.
    case optional
}

/// What one release freed.
public struct MemoryPressureRelease: Equatable, Sendable {
    /// Bytes freed (0 when nothing was held).
    public var bytes: Int
    /// Objects freed (pictures, contexts, hosts, chunks).
    public var items: Int
    /// `bytes` is an estimate, not a measurement.
    public var bytesEstimated: Bool

    public init(bytes: Int, items: Int, bytesEstimated: Bool = false) {
        self.bytes = max(0, bytes)
        self.items = max(0, items)
        self.bytesEstimated = bytesEstimated
    }

    public static let none = MemoryPressureRelease(bytes: 0, items: 0)
}

/// Implemented by the owner of a resource that can be freed under memory pressure.
@MainActor
public protocol MemoryPressureResponder: AnyObject {
    /// A stable name for diagnostics. No user content.
    var memoryPressureName: String { get }
    /// Fixed for the responder's lifetime.
    var memoryPressureTier: MemoryPressureTier { get }
    /// What a release would free now (an estimate; ≥ 0).
    var reclaimableBytes: Int { get }
    /// Frees what it holds. Idempotent: with nothing held it returns `.none`.
    func releaseForMemoryPressure(_ level: MemoryPressureLevel) -> MemoryPressureRelease
    /// Optional tier: the cool-down ended; work may start again. Safe when not shed.
    func restoreAfterMemoryPressure()
}

public extension MemoryPressureResponder {
    func restoreAfterMemoryPressure() {}
}

/// One responder's part of a recovery.
public struct MemoryPressureStepResult: Equatable, Sendable {
    public var name: String
    public var tier: MemoryPressureTier
    public var release: MemoryPressureRelease

    public init(name: String, tier: MemoryPressureTier, release: MemoryPressureRelease) {
        self.name = name
        self.tier = tier
        self.release = release
    }
}

/// One recovery, for diagnostics. Names and counts only.
public struct MemoryPressureReport: Equatable, Sendable {
    public var level: MemoryPressureLevel
    /// Optional steps ran, or the cool-down was extended.
    public var escalated: Bool
    /// Cache steps in registration order, then the optional steps that ran.
    public var steps: [MemoryPressureStepResult]
    /// End of the cool-down (monotonic seconds), or nil when nothing is shed.
    public var shedUntil: Double?

    public init(level: MemoryPressureLevel, escalated: Bool, steps: [MemoryPressureStepResult], shedUntil: Double?) {
        self.level = level
        self.escalated = escalated
        self.steps = steps
        self.shedUntil = shedUntil
    }

    public var freedBytes: Int { steps.reduce(0) { $0 + $1.release.bytes } }
    public var freedItems: Int { steps.reduce(0) { $0 + $1.release.items } }

    /// For example "warning escalated=no freed 1048576 B 4 items [shared texture pool 1048576 B 4; preset
    /// warm-up context ~262144 B 1]". `~` marks an estimate.
    public var summary: String {
        let parts = steps.map { step in
            "\(step.name) \(step.release.bytesEstimated ? "~" : "")\(step.release.bytes) B \(step.release.items)"
        }
        return "\(level.rawValue) escalated=\(escalated ? "yes" : "no") freed \(freedBytes) B \(freedItems) items [\(parts.joined(separator: "; "))]"
    }
}

@MainActor
public final class MemoryPressureRecovery {
    @MainActor
    private final class Entry {
        weak var responder: (any MemoryPressureResponder)?
        let name: String
        let tier: MemoryPressureTier
        /// Optional tier: released by an escalation and not yet restored.
        var shed = false

        init(_ responder: any MemoryPressureResponder) {
            self.responder = responder
            name = responder.memoryPressureName
            tier = responder.memoryPressureTier
        }
    }

    public let repeatWindowSeconds: Double
    public let coolDownSeconds: Double

    private var entries: [Entry] = []
    private var lastSignal: Double?
    private var running = false
    private var queued: [(MemoryPressureLevel, Double)] = []

    /// End of the cool-down while optional work is shed.
    public private(set) var shedUntil: Double?
    public var isShedding: Bool { shedUntil != nil }
    public private(set) var lastReport: MemoryPressureReport?
    public private(set) var recoveries = 0
    public private(set) var escalations = 0
    public private(set) var restores = 0
    public private(set) var totalFreedBytes = 0
    /// Called after every recovery (including queued ones).
    public var onReport: ((MemoryPressureReport) -> Void)?

    public init(repeatWindowSeconds: Double = 30, coolDownSeconds: Double = 60) {
        self.repeatWindowSeconds = max(0, repeatWindowSeconds)
        self.coolDownSeconds = max(0, coolDownSeconds)
    }

    // MARK: - Registration

    /// Adds a responder at the end of its tier's order; a repeat is ignored. An optional responder
    /// registered while work is shed is released at once and restored with the others.
    public func register(_ responder: any MemoryPressureResponder) {
        prune()
        guard !entries.contains(where: { $0.responder === responder }) else { return }
        let entry = Entry(responder)
        entries.append(entry)
        if entry.tier == .optional, isShedding {
            entry.shed = true
            _ = responder.releaseForMemoryPressure(.warning)
        }
    }

    /// Removes a responder. It is not restored.
    public func unregister(_ responder: any MemoryPressureResponder) {
        entries.removeAll { $0.responder === responder || $0.responder == nil }
    }

    // MARK: - Signals

    /// Runs a recovery for `level` at monotonic time `now` (seconds). Returns its report, or nil when
    /// called from inside a responder (the signal is then handled right after the running recovery).
    @discardableResult
    public func handle(_ level: MemoryPressureLevel, at now: Double) -> MemoryPressureReport? {
        queued.append((level, now))
        guard !running else { return nil }
        running = true
        defer { running = false }
        var report: MemoryPressureReport?
        while !queued.isEmpty {
            let (nextLevel, time) = queued.removeFirst()
            report = recover(nextLevel, at: time)
        }
        return report
    }

    private func recover(_ level: MemoryPressureLevel, at now: Double) -> MemoryPressureReport {
        prune()
        let escalate = level == .critical || lastSignal.map { now - $0 <= repeatWindowSeconds } == true
        lastSignal = now
        var steps: [MemoryPressureStepResult] = []
        // A copy: responders may register or unregister. Membership is checked before each call.
        for entry in entries where entry.tier == .cache {
            guard let responder = entry.responder, entries.contains(where: { $0 === entry }) else { continue }
            steps.append(MemoryPressureStepResult(name: entry.name, tier: .cache,
                                                  release: responder.releaseForMemoryPressure(level)))
        }
        if escalate {
            escalations += 1
            shedUntil = now + coolDownSeconds
            for entry in entries where entry.tier == .optional && !entry.shed {
                guard let responder = entry.responder, entries.contains(where: { $0 === entry }) else { continue }
                entry.shed = true
                steps.append(MemoryPressureStepResult(name: entry.name, tier: .optional,
                                                      release: responder.releaseForMemoryPressure(level)))
            }
        }
        let report = MemoryPressureReport(level: level, escalated: escalate, steps: steps, shedUntil: shedUntil)
        recoveries += 1
        totalFreedBytes += report.freedBytes
        lastReport = report
        onReport?(report)
        return report
    }

    /// When the cool-down has ended at `now`, restores every shed responder once and returns their
    /// names; otherwise returns [].
    @discardableResult
    public func restoreIfDue(at now: Double) -> [String] {
        guard let until = shedUntil, now >= until else { return [] }
        shedUntil = nil
        prune()
        var names: [String] = []
        for entry in entries where entry.shed {
            entry.shed = false
            guard let responder = entry.responder else { continue }
            responder.restoreAfterMemoryPressure()
            names.append(entry.name)
        }
        restores += 1
        return names
    }

    private func prune() {
        entries.removeAll { $0.responder == nil }
    }

    // MARK: - State

    /// Live responders in order (diagnostics and tests).
    public var snapshot: [(name: String, tier: MemoryPressureTier, reclaimableBytes: Int)] {
        entries.compactMap { entry in
            entry.responder.map { (entry.name, entry.tier, max(0, $0.reclaimableBytes)) }
        }
    }

    /// Bytes the live responders estimate they could free now.
    public var reclaimableBytes: Int { snapshot.reduce(0) { $0 + $1.reclaimableBytes } }
}
