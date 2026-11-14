// FrameDropCounter.swift — frame drop counts per output (PERF-007-R1 to R9; specs/192-perf-007-frame-drop-telemetry,
// contracts/frame-drop-counter.md C1, C2; research PERF-007-D1 to D4).
// PERF-012: an optional `FrameIntervalRecorder` receives the interval since the previous accepted submit.
//
// * Local, in-memory counting only: nothing here leaves the device (PERF-007-R12).
// * `submit` (the frame thread, once per frame handed to the display) counts the frame and the refresh slots skipped
//   since the previous one, from display-link timestamps; a timestamp not later than the previous one is ignored.
// * `presented` (any thread: Metal's presented handler) counts the frame as presented (late when it was shown more than
//   half a refresh interval after its target) or discarded (never shown), at most once per frame ID.
// * Every event carries its session; a session begins with `beginSession`, which zeroes the counts. Lock-free: every
//   cell is a 64-bit atomic that packs the session generation (16 bits) with its value, and every change is a
//   compare-and-exchange that gives up when the generation is not the event's. An old session's report therefore
//   never changes a new session's counts, even when it races the reset (PERF-007-D2). Nothing allocates.
import Synchronization

/// Where frames are shown (PERF-007-R1).
public enum FrameDropOutput: String, CaseIterable, Sendable {
    case device
    case external
    case recording
}

/// One counting session of one counter.
public struct FrameDropSession: Sendable, Equatable {
    public let generation: UInt16

    public init(generation: UInt16) { self.generation = generation }
}

/// A submitted frame, to be reported presented (or discarded) once.
public struct FrameDropTicket: Sendable, Equatable {
    public let session: FrameDropSession
    /// 1, 2, 3 … within the session.
    public let frameID: UInt32
    /// The display-link target time of the frame (seconds, the display's host clock).
    public let targetTime: Double
    /// The refresh interval at submission (target − timestamp); 0 when not valid.
    public let refreshInterval: Double

    public init(session: FrameDropSession, frameID: UInt32, targetTime: Double, refreshInterval: Double) {
        self.session = session
        self.frameID = frameID
        self.targetTime = targetTime
        self.refreshInterval = refreshInterval
    }
}

/// The counts of one output; nil = unavailable on this path (PERF-007-R7), never 0.
public struct FrameDropCounts: Sendable, Equatable {
    public var submitted: Int?
    public var skipped: Int?
    public var presented: Int?
    public var late: Int?
    public var discarded: Int?
    /// Events of another session that were ignored (export only).
    public var stale: Int

    public init(submitted: Int? = nil, skipped: Int? = nil, presented: Int? = nil, late: Int? = nil, discarded: Int? = nil,
                stale: Int = 0) {
        self.submitted = submitted
        self.skipped = skipped
        self.presented = presented
        self.late = late
        self.discarded = discarded
        self.stale = stale
    }

    /// The recording (research PERF-007-D1): presented = frames written to the file, skipped = REC-006 dropped slots.
    public static func recording(written: Int, droppedSlots: Int) -> FrameDropCounts {
        FrameDropCounts(skipped: max(0, droppedSlots), presented: max(0, written))
    }

    public static let linePrefix = "frames "

    /// Contract C2: "frames device: presented 4, late 1, skipped 1, submitted 5, discarded 1"; the recording has no
    /// submitted and discarded parts.
    public func line(for output: FrameDropOutput) -> String {
        var parts: [String] = []
        parts.append("presented " + Self.text(presented))
        parts.append("late " + Self.text(late))
        parts.append("skipped " + Self.text(skipped))
        if output != .recording {
            parts.append("submitted " + Self.text(submitted))
            parts.append("discarded " + Self.text(discarded))
        }
        return Self.linePrefix + output.rawValue + ": " + parts.joined(separator: ", ")
    }

    static func text(_ value: Int?) -> String {
        guard let value else { return "unavailable" }
        return String(value)
    }
}

/// Lock-free frame drop counts for one display output (contract C1).
public final class FrameDropCounter: Sendable {
    private static let countBits: UInt64 = 48
    private static let countMask: UInt64 = (1 << 48) - 1
    /// Out-of-order presented reports accepted up to this many frames below the newest.
    public static let reorderWindow: UInt32 = 16

    private let generation = Atomic<UInt16>(0)
    private let measured = Atomic<Bool>(false)
    private let submittedCell = Atomic<UInt64>(0)
    private let skippedCell = Atomic<UInt64>(0)
    private let presentedCell = Atomic<UInt64>(0)
    private let lateCell = Atomic<UInt64>(0)
    private let discardedCell = Atomic<UInt64>(0)
    private let staleCell = Atomic<UInt64>(0)
    /// generation(16) | newest frame ID(32) | window(16): bit k = frame (newest − 1 − k) already counted.
    private let newestCell = Atomic<UInt64>(0)
    /// The frame thread's own state: the previous timestamp's bit pattern and the last issued frame ID.
    private let lastTimestamp = Atomic<UInt64>(0)
    private let nextFrameID = Atomic<UInt32>(0)
    /// PERF-012: the app session's frame intervals (not reset by `beginSession`); nil = not recorded.
    private let intervals: FrameIntervalRecorder?

    public init(intervals: FrameIntervalRecorder? = nil) {
        self.intervals = intervals
    }

    /// The current session (generation 0 before the first `beginSession`).
    public var session: FrameDropSession { FrameDropSession(generation: generation.load(ordering: .acquiring)) }

    /// Whether the current session measures presented, late and discarded frames.
    public var measuresPresentation: Bool { measured.load(ordering: .relaxed) }

    /// Starts a new session with every count at zero (PERF-007-R6). Call it on the frame thread.
    @discardableResult
    public func beginSession(measuresPresentation: Bool) -> FrameDropSession {
        let next: UInt16 = generation.load(ordering: .relaxed) &+ 1
        let base: UInt64 = UInt64(next) << Self.countBits
        // Cells first, then the generation: a stale event whose CAS sees the new cell value fails on the generation.
        resetCells(base)
        lastTimestamp.store(0, ordering: .relaxed)
        nextFrameID.store(0, ordering: .relaxed)
        measured.store(measuresPresentation, ordering: .relaxed)
        generation.store(next, ordering: .releasing)
        return FrameDropSession(generation: next)
    }

    // MARK: - Frame path

    /// Counts a frame handed to the display at a display-link tick (PERF-007-R3, R4). Nil when the session is not the
    /// current one (counted stale) or the timestamp is not later than the previous one (a duplicate: nothing counted).
    public func submit(_ session: FrameDropSession, timestamp: Double, targetTimestamp: Double) -> FrameDropTicket? {
        let gen: UInt16 = session.generation
        guard gen == generation.load(ordering: .acquiring), gen != 0 else {
            increment(staleCell, generation: generation.load(ordering: .acquiring))
            return nil
        }
        guard timestamp.isFinite else { return nil }
        let previous: Double = Double(bitPattern: lastTimestamp.load(ordering: .relaxed))
        let hasPrevious: Bool = previous != 0
        if hasPrevious && timestamp <= previous { return nil }
        lastTimestamp.store(timestamp.bitPattern, ordering: .relaxed)
        if hasPrevious { intervals?.record(seconds: timestamp - previous) }   // PERF-012-D1
        let interval: Double = targetTimestamp - timestamp
        let valid: Bool = interval.isFinite && interval > 0
        if hasPrevious && valid {
            let slots: Double = ((timestamp - previous) / interval).rounded()
            if slots > 1 { add(skippedCell, generation: gen, Int(min(slots - 1, Double(Int32.max)))) }
        }
        increment(submittedCell, generation: gen)
        let id: UInt32 = nextFrameID.load(ordering: .relaxed) &+ 1
        nextFrameID.store(id, ordering: .releasing)
        return FrameDropTicket(session: session, frameID: id, targetTime: targetTimestamp, refreshInterval: valid ? interval : 0)
    }

    /// Counts the display's report for a submitted frame, at most once (PERF-007-R2, R4, R5). Any thread.
    /// `presentedTime` ≤ 0 means the frame was never shown (discarded).
    public func presented(_ ticket: FrameDropTicket, presentedTime: Double) {
        let gen: UInt16 = ticket.session.generation
        // An ID this session never issued is not a report of one of its frames.
        let issued: Bool = gen == generation.load(ordering: .acquiring) && ticket.frameID <= nextFrameID.load(ordering: .acquiring)
        guard issued, firstReport(ticket.frameID, generation: gen) else {
            if !issued { increment(staleCell, generation: generation.load(ordering: .acquiring)) }
            return
        }
        guard presentedTime.isFinite, presentedTime > 0 else {
            increment(discardedCell, generation: gen)
            return
        }
        increment(presentedCell, generation: gen)
        let interval: Double = ticket.refreshInterval
        if interval > 0, presentedTime - ticket.targetTime > interval / 2 { increment(lateCell, generation: gen) }
    }

    // MARK: - Reading (any thread)

    public func counts() -> FrameDropCounts {
        let gen: UInt16 = generation.load(ordering: .acquiring)
        let presentation: Bool = measured.load(ordering: .relaxed)
        return FrameDropCounts(submitted: value(submittedCell, gen), skipped: value(skippedCell, gen),
                               presented: presentation ? value(presentedCell, gen) : nil,
                               late: presentation ? value(lateCell, gen) : nil,
                               discarded: presentation ? value(discardedCell, gen) : nil,
                               stale: value(staleCell, gen))
    }

    // MARK: - Private

    private func resetCells(_ base: UInt64) {
        submittedCell.store(base, ordering: .releasing)
        skippedCell.store(base, ordering: .releasing)
        presentedCell.store(base, ordering: .releasing)
        lateCell.store(base, ordering: .releasing)
        discardedCell.store(base, ordering: .releasing)
        staleCell.store(base, ordering: .releasing)
        newestCell.store(base, ordering: .releasing)
    }

    private func value(_ cell: borrowing Atomic<UInt64>, _ gen: UInt16) -> Int {
        let raw: UInt64 = cell.load(ordering: .acquiring)
        guard UInt16(truncatingIfNeeded: raw >> Self.countBits) == gen else { return 0 }
        return Int(raw & Self.countMask)
    }

    private func increment(_ cell: borrowing Atomic<UInt64>, generation gen: UInt16) { add(cell, generation: gen, 1) }

    /// Adds `amount` when the cell still belongs to `gen`; otherwise nothing (the session ended).
    private func add(_ cell: borrowing Atomic<UInt64>, generation gen: UInt16, _ amount: Int) {
        guard amount > 0, gen != 0 else { return }
        var current: UInt64 = cell.load(ordering: .relaxed)
        while true {
            guard UInt16(truncatingIfNeeded: current >> Self.countBits) == gen else { return }
            let count: UInt64 = min((current & Self.countMask) + UInt64(amount), Self.countMask)
            let next: UInt64 = (UInt64(gen) << Self.countBits) | count
            let (exchanged, original) = cell.compareExchange(expected: current, desired: next,
                                                             successOrdering: .acquiringAndReleasing, failureOrdering: .relaxed)
            if exchanged { return }
            current = original
        }
    }

    /// True exactly once per frame ID of the cell's session: newer than the newest moves the window, within the window
    /// below the newest sets its bit; repeated, too old or another session's IDs are refused.
    private func firstReport(_ id: UInt32, generation gen: UInt16) -> Bool {
        guard id != 0, gen != 0 else { return false }
        var current: UInt64 = newestCell.load(ordering: .relaxed)
        while true {
            guard UInt16(truncatingIfNeeded: current >> Self.countBits) == gen else { return false }
            let newest = UInt32(truncatingIfNeeded: current >> 16)
            var window = UInt16(truncatingIfNeeded: current)
            if id > newest {
                let shift: UInt32 = id - newest
                // The old newest becomes bit (shift − 1); everything moves up by `shift`.
                if shift > UInt32(Self.reorderWindow) {
                    window = 0
                } else {
                    let moved: UInt32 = (UInt32(window) << shift) | (newest != 0 ? UInt32(1) << (shift - 1) : 0)
                    window = UInt16(truncatingIfNeeded: moved)
                }
                let next: UInt64 = (UInt64(gen) << Self.countBits) | (UInt64(id) << 16) | UInt64(window)
                let (exchanged, original) = newestCell.compareExchange(expected: current, desired: next,
                                                                       successOrdering: .acquiringAndReleasing, failureOrdering: .relaxed)
                if exchanged { return true }
                current = original
                continue
            }
            let back: UInt32 = newest - id   // 0 = the newest itself (a repeat)
            guard back >= 1, back <= Self.reorderWindow else { return false }
            let bit = UInt16(1) << UInt16(back - 1)
            guard window & bit == 0 else { return false }
            let next: UInt64 = current | UInt64(bit)
            let (exchanged, original) = newestCell.compareExchange(expected: current, desired: next,
                                                                   successOrdering: .acquiringAndReleasing, failureOrdering: .relaxed)
            if exchanged { return true }
            current = original
        }
    }
}
