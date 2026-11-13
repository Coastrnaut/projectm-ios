// BandFrameBuffer.swift — wait-free hand-off of band frames from the analysis queue to the frame
// loop (VIS-001-R14; research VIS-001-D6).
//
// A triple buffer: three slots of 128 Floats allocated in `init`. The writer owns one slot, the
// reader owns one, and the third is "in the middle". `write` fills the writer's slot and exchanges
// it with the middle one, marking it fresh; `readLatest` exchanges the reader's slot with the middle
// one only when it is fresh. Each side does one atomic exchange and never waits, so neither the
// analysis queue nor the render thread can block the other (Constitution VII), and the reader always
// sees a complete frame: the newest one written.
//
// Exactly one writer thread and one reader thread at a time.
import Synchronization

/// What `readLatest` returns besides the values.
public struct BandFrameInfo: Sendable, Equatable {
    /// Values copied (at most the reader's capacity and 128).
    public var count: Int
    /// The writer's clock when the frame was produced (monotonic nanoseconds).
    public var timestampNanoseconds: UInt64
    /// 1 for the first frame written, then +1 per write.
    public var sequence: UInt64
}

public final class BandFrameBuffer: @unchecked Sendable {
    public static let capacity = SpectrumBarCount.maximum
    private static let freshBit = 4
    private static let indexMask = 3

    private let values: UnsafeMutablePointer<Float>
    /// Per-slot metadata. A slot's fields are touched only by the side that currently owns it; the
    /// atomic exchange (acquire-release) publishes them with the values.
    private let counts: UnsafeMutablePointer<Int>
    private let times: UnsafeMutablePointer<UInt64>
    private let sequences: UnsafeMutablePointer<UInt64>
    private let middle = Atomic<Int>(1)
    private var writerSlot = 0      // writer-owned
    private var readerSlot = 2      // reader-owned
    private var written: UInt64 = 0 // writer-owned

    public init() {
        values = .allocate(capacity: 3 * Self.capacity)
        values.initialize(repeating: 0, count: 3 * Self.capacity)
        counts = .allocate(capacity: 3)
        counts.initialize(repeating: 0, count: 3)
        times = .allocate(capacity: 3)
        times.initialize(repeating: 0, count: 3)
        sequences = .allocate(capacity: 3)
        sequences.initialize(repeating: 0, count: 3)
    }

    deinit {
        values.deinitialize(count: 3 * Self.capacity); values.deallocate()
        counts.deinitialize(count: 3); counts.deallocate()
        times.deinitialize(count: 3); times.deallocate()
        sequences.deinitialize(count: 3); sequences.deallocate()
    }

    /// Writer side: publishes `source` (at most 128 values) as the newest frame. Wait-free.
    public func write(_ source: UnsafeBufferPointer<Float>, timestampNanoseconds: UInt64) {
        let slot = writerSlot
        let count = min(source.count, Self.capacity)
        if count > 0, let base = source.baseAddress {
            (values + slot * Self.capacity).update(from: base, count: count)
        }
        written &+= 1
        counts[slot] = count
        times[slot] = timestampNanoseconds
        sequences[slot] = written
        let previous = middle.exchange(slot | Self.freshBit, ordering: .acquiringAndReleasing)
        writerSlot = previous & Self.indexMask
    }

    /// Reader side: copies the newest frame into `destination` (room for `capacity` values) when one
    /// arrived since the last read; nil otherwise (the caller keeps its last values). Wait-free.
    public func readLatest(into destination: UnsafeMutablePointer<Float>, capacity: Int) -> BandFrameInfo? {
        guard middle.load(ordering: .acquiring) & Self.freshBit != 0 else { return nil }
        let previous = middle.exchange(readerSlot, ordering: .acquiringAndReleasing)
        readerSlot = previous & Self.indexMask
        let slot = readerSlot
        let count = min(counts[slot], max(capacity, 0))
        if count > 0 { destination.update(from: values + slot * Self.capacity, count: count) }
        return BandFrameInfo(count: count, timestampNanoseconds: times[slot], sequence: sequences[slot])
    }
}
