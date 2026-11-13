// WaveformFrameBuffer.swift — wait-free hand-off of mono sample histories from the analysis worker to
// the frame loop (VIS-003-R2; research VIS-003-D1; contract C2).
//
// The same triple buffer as `BandFrameBuffer` (VIS-001-D6), with slots of 4,096 samples: three slots
// allocated in `init`; the writer fills its slot and exchanges it with the middle one (marked fresh);
// the reader exchanges its slot with the middle one only when it is fresh. One atomic exchange per
// side, no waiting, so the reader always sees a complete history: the newest written.
//
// Exactly one writer thread and one reader thread at a time.
import Synchronization

public final class WaveformFrameBuffer: @unchecked Sendable {
    /// Samples per history (≈ 93 ms at 44.1 kHz).
    public static let capacity = 4_096
    private static let freshBit = 4
    private static let indexMask = 3

    private let values: UnsafeMutablePointer<Float>
    /// Per slot: samples written in total when the slot was filled (owned by the side holding it).
    private let totals: UnsafeMutablePointer<UInt64>
    private let middle = Atomic<Int>(1)
    private var writerSlot = 0      // writer-owned
    private var readerSlot = 2      // reader-owned

    public init() {
        values = .allocate(capacity: 3 * Self.capacity)
        values.initialize(repeating: 0, count: 3 * Self.capacity)
        totals = .allocate(capacity: 3)
        totals.initialize(repeating: 0, count: 3)
    }

    deinit {
        values.deinitialize(count: 3 * Self.capacity); values.deallocate()
        totals.deinitialize(count: 3); totals.deallocate()
    }

    /// Writer side: publishes the newest `capacity` samples of `source` (oldest first; a shorter
    /// source fills the slot's tail and leaves zeros before it). Wait-free.
    public func write(_ source: UnsafeBufferPointer<Float>, totalWritten: UInt64) {
        let slot = values + writerSlot * Self.capacity
        let count = min(source.count, Self.capacity)
        if count < Self.capacity { slot.update(repeating: 0, count: Self.capacity - count) }
        if count > 0, let base = source.baseAddress {
            (slot + (Self.capacity - count)).update(from: base + (source.count - count), count: count)
        }
        totals[writerSlot] = totalWritten
        let previous = middle.exchange(writerSlot | Self.freshBit, ordering: .acquiringAndReleasing)
        writerSlot = previous & Self.indexMask
    }

    /// Reader side: copies the newest history's last `capacity` samples (all of it when the room
    /// allows) into `destination` when one arrived since the last read, and returns its total; nil
    /// otherwise (the caller keeps its last history). Wait-free.
    public func readLatest(into destination: UnsafeMutablePointer<Float>, capacity: Int) -> UInt64? {
        guard middle.load(ordering: .acquiring) & Self.freshBit != 0 else { return nil }
        let previous = middle.exchange(readerSlot, ordering: .acquiringAndReleasing)
        readerSlot = previous & Self.indexMask
        let count = min(max(capacity, 0), Self.capacity)
        if count > 0 {
            destination.update(from: values + readerSlot * Self.capacity + (Self.capacity - count), count: count)
        }
        return totals[readerSlot]
    }
}
