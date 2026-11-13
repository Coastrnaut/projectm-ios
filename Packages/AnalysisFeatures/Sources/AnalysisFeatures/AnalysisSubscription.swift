// AnalysisSubscription.swift — one subscriber's mailbox on the analysis event bus (ANL-016-R10 to
// R12; research ANL-016-D3).
//
// * Frames: a latest-wins slot (metadata + 128 floats). A read returns the newest frame not read yet
//   and copies its bands; frames replaced before being read are counted in `overwrittenFrames`.
// * Events: a bounded ring (capacity 1…1,024, default 64). When full, the oldest event is dropped and
//   counted in `droppedEvents`, so the queue always holds the newest events in ID order.
//
// Thread safety: one `Mutex` guards every stored var below `lock`. The pipeline's worker takes it to
// copy one item in; the subscriber's thread takes it to copy items out. Each critical section is a
// constant-size copy (at most 128 floats or one event), never waits on anything else, and allocates
// nothing (storage is created in `init`), so a slow or absent reader cannot stall the worker beyond
// such a copy (Constitution VII). Subscriber code never runs on the worker: subscribers poll.
import Synchronization

public final class AnalysisSubscription: @unchecked Sendable {
    public static let defaultEventCapacity = 64
    public static let eventCapacityRange = 1...1_024
    /// Largest band vector (BandCount.b128).
    public static let maximumBands = BandCount.b128.rawValue

    public let eventCapacity: Int

    private let lock = Mutex(())
    // Guarded by `lock`:
    private let events: UnsafeMutablePointer<AnalysisEvent>
    private var head = 0
    private var count = 0
    private var dropped = 0
    private let bands: UnsafeMutablePointer<Float>
    private var frame: AnalysisFrame?
    private var fresh = false
    private var overwritten = 0
    private var cancelled = false

    init(eventCapacity: Int = AnalysisSubscription.defaultEventCapacity) throws(AnalysisBusError) {
        guard AnalysisSubscription.eventCapacityRange.contains(eventCapacity) else { throw .invalidEventCapacity(eventCapacity) }
        self.eventCapacity = eventCapacity
        let placeholder = AnalysisEvent(id: 0, time: AnalysisTimestamp(session: 0, sessionSample: 0, timelineSample: 0, hostNanoseconds: 0),
                                        eventSample: 0, kind: .sessionEnded(.detached))
        events = .allocate(capacity: eventCapacity)
        events.initialize(repeating: placeholder, count: eventCapacity)
        bands = .allocate(capacity: AnalysisSubscription.maximumBands)
        bands.initialize(repeating: 0, count: AnalysisSubscription.maximumBands)
    }

    deinit {
        events.deinitialize(count: eventCapacity); events.deallocate()
        bands.deinitialize(count: AnalysisSubscription.maximumBands); bands.deallocate()
    }

    // MARK: Worker side (the pipeline)

    /// Queues `event`, dropping the oldest when full. Allocation-free.
    func publish(_ event: AnalysisEvent) {
        lock.withLock { _ in
            guard !cancelled else { return }
            if count == eventCapacity {
                head = (head + 1) % eventCapacity
                count -= 1
                dropped += 1
            }
            events[(head + count) % eventCapacity] = event
            count += 1
        }
    }

    /// Replaces the frame slot with `frame` and its bands (at most 128 copied). Allocation-free.
    func publish(_ frame: AnalysisFrame, bands source: UnsafeBufferPointer<Float>) {
        lock.withLock { _ in
            guard !cancelled else { return }
            if fresh { overwritten += 1 }
            let n = min(source.count, AnalysisSubscription.maximumBands)
            if n > 0, let base = source.baseAddress { bands.update(from: base, count: n) }
            self.frame = frame
            fresh = true
        }
    }

    /// Empties the frame slot (a session start: no old-session frame is read afterwards).
    func clearFrame() {
        lock.withLock { _ in
            frame = nil
            fresh = false
        }
    }

    /// Final: empties the mailbox and refuses further items.
    func cancel() {
        lock.withLock { _ in
            cancelled = true
            head = 0
            count = 0
            frame = nil
            fresh = false
        }
    }

    // MARK: Subscriber side

    /// The oldest queued event, or nil. Allocation-free.
    public func nextEvent() -> AnalysisEvent? {
        lock.withLock { _ -> AnalysisEvent? in
            guard count > 0 else { return nil }
            let event = events[head]
            head = (head + 1) % eventCapacity
            count -= 1
            return event
        }
    }

    /// Every queued event, oldest first (allocates the array; for callers off the real-time path).
    public func drainEvents() -> [AnalysisEvent] {
        var result: [AnalysisEvent] = []
        while let event = nextEvent() { result.append(event) }
        return result
    }

    /// The newest frame not read yet, with min(bandCount, capacity) bands copied into `destination`;
    /// nil when no new frame arrived (the caller keeps its last values). Allocation-free.
    public func latestFrame(into destination: UnsafeMutablePointer<Float>, capacity: Int) -> AnalysisFrame? {
        lock.withLock { _ -> AnalysisFrame? in
            guard fresh, let frame else { return nil }
            fresh = false
            let n = min(frame.bandCount, max(capacity, 0), AnalysisSubscription.maximumBands)
            if n > 0 { destination.update(from: bands, count: n) }
            return frame
        }
    }

    /// Events dropped because the queue was full (drop-oldest).
    public var droppedEvents: Int { lock.withLock { _ in dropped } }
    /// Frames replaced before they were read (latest wins).
    public var overwrittenFrames: Int { lock.withLock { _ in overwritten } }
    /// Events waiting to be read.
    public var pendingEvents: Int { lock.withLock { _ in count } }
    public var isCancelled: Bool { lock.withLock { _ in cancelled } }
}
