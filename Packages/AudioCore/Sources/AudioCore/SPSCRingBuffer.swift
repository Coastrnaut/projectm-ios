// SPSCRingBuffer.swift — preallocated single-producer/single-consumer ring (task T024; research R-06).
//
// Real-time safety (Constitution VII): after init, `write` and `read` never allocate, lock,
// or log. Indices are monotonic `Int` counters held in `Synchronization.Atomic`.
//
// Overflow policy: drop-oldest. When the producer needs space, it advances the read index
// with compare-and-swap and counts the dropped samples. The consumer copies a region and
// then commits it with compare-and-swap; if the producer moved the read index meanwhile,
// the copied region may have been overwritten, so the consumer discards it and retries.
// The producer only ever writes into slots below the (new) read index, so a successful
// commit always means the copied data was intact.
import Synchronization

public final class SPSCRingBuffer: @unchecked Sendable {
    public let capacity: Int
    private let storage: UnsafeMutablePointer<Float>
    private let writeIndex = Atomic<Int>(0)   // modified by the producer only
    private let readIndex = Atomic<Int>(0)    // advanced by the consumer, or by the producer on overflow
    private let dropped = Atomic<Int>(0)

    public init(capacity: Int) {
        precondition(capacity > 0, "capacity must be positive")
        self.capacity = capacity
        storage = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    /// Samples dropped because the consumer fell behind (drop-oldest), plus any excess of a
    /// single write larger than the capacity.
    public var droppedSamples: Int { dropped.load(ordering: .relaxed) }

    /// Number of samples currently readable.
    public var availableToRead: Int {
        let w = writeIndex.load(ordering: .acquiring)
        let r = readIndex.load(ordering: .acquiring)
        return max(0, w - r)
    }

    /// Producer side. Real-time safe.
    public func write(_ source: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        var src = source
        var n = count
        if n > capacity {
            // Only the newest `capacity` samples can be kept.
            _ = dropped.add(n - capacity, ordering: .relaxed)
            src += n - capacity
            n = capacity
        }
        let w = writeIndex.load(ordering: .relaxed)
        while true {
            let r = readIndex.load(ordering: .acquiring)
            let free = capacity - (w - r)
            if free >= n { break }
            let need = n - free
            if readIndex.compareExchange(expected: r, desired: r + need,
                                         successOrdering: .acquiringAndReleasing,
                                         failureOrdering: .acquiring).exchanged {
                _ = dropped.add(need, ordering: .relaxed)
                break
            }
        }
        let start = w % capacity
        let first = min(n, capacity - start)
        (storage + start).update(from: src, count: first)
        if first < n {
            storage.update(from: src + first, count: n - first)
        }
        writeIndex.store(w + n, ordering: .releasing)
    }

    /// Consumer side. Copies up to `maxCount` samples into `destination`; returns the number
    /// copied, or 0 when empty (underrun). Never blocks.
    @discardableResult
    public func read(into destination: UnsafeMutablePointer<Float>, maxCount: Int) -> Int {
        guard maxCount > 0 else { return 0 }
        while true {
            let r = readIndex.load(ordering: .acquiring)
            let w = writeIndex.load(ordering: .acquiring)
            let n = min(maxCount, w - r)
            if n <= 0 { return 0 }
            let start = r % capacity
            let first = min(n, capacity - start)
            destination.update(from: storage + start, count: first)
            if first < n {
                (destination + first).update(from: storage, count: n - first)
            }
            if readIndex.compareExchange(expected: r, desired: r + n,
                                         successOrdering: .acquiringAndReleasing,
                                         failureOrdering: .acquiring).exchanged {
                return n
            }
            // The producer dropped old data while we copied; retry with the new read index.
        }
    }

    /// Discards everything currently readable. Consumer side.
    public func drain() {
        while true {
            let r = readIndex.load(ordering: .acquiring)
            let w = writeIndex.load(ordering: .acquiring)
            if r >= w { return }
            if readIndex.compareExchange(expected: r, desired: w,
                                         successOrdering: .acquiringAndReleasing,
                                         failureOrdering: .acquiring).exchanged { return }
        }
    }
}
