// MIDIClockLane.swift — the clock follower's own queue beside the shared ring (MIDI-010-R1; research MIDI-010-D2;
// specs/273-midi-010-midi-clock-receive/contracts/midi-clock.md C1).
//
// The shared ring counts Timing Clock and never stores it (MIDI-002-R4), so the monitor and the other clients never
// see 24–120 pulses a second. The clock follower needs every pulse's timestamp in order with Start, Continue, Stop and
// Song Position, so the ring's producer also copies exactly those kinds here, in arrival order.
// * Single producer (the ring's producer thread), single consumer (the main actor's drain).
// * Storage allocated once in `init`; after that `push` never allocates, locks, logs or dispatches.
// * Disabled (the default) the producer copies nothing; the consumer enables it while following and discards what
//   was left from an earlier run. Overflow drops the newest event and counts it.
import Synchronization

public final class MIDIClockLane: @unchecked Sendable {
    public static let defaultCapacity: Int = 256

    public let capacity: Int
    private let storage: UnsafeMutablePointer<MIDIEvent>
    private let writeIndex = Atomic<Int>(0)   // producer only
    private let readIndex = Atomic<Int>(0)    // consumer only
    private let droppedCount = Atomic<Int>(0)
    private let enabled = Atomic<Bool>(false)

    public init(capacity: Int = MIDIClockLane.defaultCapacity) {
        precondition(capacity > 0, "capacity must be positive")
        self.capacity = capacity
        storage = UnsafeMutablePointer<MIDIEvent>.allocate(capacity: capacity)
        storage.initialize(repeating: MIDIEvent(kind: .reset), count: capacity)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    /// The kinds the lane carries: Timing Clock, Start, Continue, Stop and Song Position.
    @inline(__always)
    public static func carries(_ kind: MIDIEventKind) -> Bool {
        switch kind {
        case .clock, .start, .continue, .stop, .songPosition: return true
        default: return false
        }
    }

    /// Whether the producer copies events (set by the consumer).
    public var isEnabled: Bool {
        get { enabled.load(ordering: .acquiring) }
        set { enabled.store(newValue, ordering: .releasing) }
    }

    // MARK: Producer (real-time safe)

    public func push(_ event: MIDIEvent) {
        guard enabled.load(ordering: .relaxed) else { return }
        let w: Int = writeIndex.load(ordering: .relaxed)
        let r: Int = readIndex.load(ordering: .acquiring)
        if w - r >= capacity {
            droppedCount.add(1, ordering: .relaxed)
            return
        }
        (storage + (w % capacity)).pointee = event
        writeIndex.store(w + 1, ordering: .releasing)
    }

    // MARK: Consumer

    /// Appends up to `maxCount` events, oldest first; returns how many.
    @discardableResult
    public func drain(into events: inout [MIDIEvent], maxCount: Int = MIDIClockLane.defaultCapacity) -> Int {
        let r: Int = readIndex.load(ordering: .relaxed)
        let w: Int = writeIndex.load(ordering: .acquiring)
        let n: Int = min(max(0, w - r), max(0, maxCount))
        guard n > 0 else { return 0 }
        events.reserveCapacity(events.count + n)
        for offset in 0..<n {
            events.append((storage + ((r + offset) % capacity)).pointee)
        }
        readIndex.store(r + n, ordering: .releasing)
        return n
    }

    /// Drops every unread event (consumer side).
    public func discardAll() {
        let w: Int = writeIndex.load(ordering: .acquiring)
        readIndex.store(w, ordering: .releasing)
    }

    public var dropped: Int { droppedCount.load(ordering: .relaxed) }
}
