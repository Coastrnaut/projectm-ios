// MIDIEventRing.swift — the bounded queue between the MIDI callback and the screen (MIDI-002-R4, R5; research
// MIDI-002-D3; contracts/midi-input.md C2).
//
// Single producer (the system's receive block for one input port, called one at a time on its own thread; or
// the scripted provider), single consumer (the main actor's display-rate drain).
// * Storage: `capacity` events allocated once in `init`; indices are monotonic `Int` counters in
//   `Synchronization.Atomic`. After `init`, `push` never allocates, locks, logs or dispatches.
// * Overflow: drop newest. When full, the pushed event is dropped and `dropped` is incremented; the producer
//   never touches the read index, so the consumer's copy is always intact.
// * Timing clock and active sensing increment their own counters and are never stored (MIDI-002-R4).
import Synchronization

public final class MIDIEventRing: MIDIEventSink, @unchecked Sendable {
    public static let defaultCapacity: Int = 512

    public let capacity: Int
    private let storage: UnsafeMutablePointer<MIDIEvent>
    private let writeIndex = Atomic<Int>(0)   // producer only
    private let readIndex = Atomic<Int>(0)    // consumer only
    private let droppedCount = Atomic<Int>(0)
    private let clocks = Atomic<Int>(0)
    private let sensing = Atomic<Int>(0)

    public init(capacity: Int = MIDIEventRing.defaultCapacity) {
        precondition(capacity > 0, "capacity must be positive")
        self.capacity = capacity
        storage = UnsafeMutablePointer<MIDIEvent>.allocate(capacity: capacity)
        storage.initialize(repeating: MIDIEvent(kind: .reset), count: capacity)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    // MARK: Producer (real-time safe)

    public func receive(_ event: MIDIEvent) { push(event) }

    public func push(_ event: MIDIEvent) {
        switch event.kind {
        case .clock:
            clocks.add(1, ordering: .relaxed)
            return
        case .activeSensing:
            sensing.add(1, ordering: .relaxed)
            return
        default:
            break
        }
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
    public func drain(into events: inout [MIDIEvent], maxCount: Int) -> Int {
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

    /// Drops every unread event (consumer side; used when receiving stops).
    public func discardAll() {
        let w: Int = writeIndex.load(ordering: .acquiring)
        readIndex.store(w, ordering: .releasing)
    }

    // MARK: Counters (monotonic since init; readers keep their own baselines)

    public var availableToRead: Int {
        let w: Int = writeIndex.load(ordering: .acquiring)
        let r: Int = readIndex.load(ordering: .acquiring)
        return max(0, w - r)
    }

    public var dropped: Int { droppedCount.load(ordering: .relaxed) }
    public var clockCount: Int { clocks.load(ordering: .relaxed) }
    public var activeSensingCount: Int { sensing.load(ordering: .relaxed) }

    /// The storage's address (tests: unchanged after any number of pushes, so the path never reallocates).
    public var storageAddress: UInt { UInt(bitPattern: storage) }
}
