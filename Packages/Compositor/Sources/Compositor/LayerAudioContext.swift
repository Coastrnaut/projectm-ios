// LayerAudioContext.swift — the music every layer receives, as plain values (CMP-001-R4; research
// CMP-001-D3; contracts/layer-source.md "Context").
//
// * `LayerAudioContext`: the latest ANL-016 analysis frame (metadata), its bands, and the events
//   delivered since the previous frame, oldest first. The buffers are views into a
//   `LayerAudioBuffer`'s storage, valid only during one `composite` call: a layer must not keep them.
//   Never the engine, the capture system or any audio source object (Constitution VI).
// * `LayerAudioBuffer`: preallocated storage (128 bands, 64 events). `update(from:)` reads an
//   `AnalysisMailbox` (an `AnalysisSubscription`) once per frame without allocating: the newest
//   frame if one arrived (otherwise the previous one stays) and every queued event; when more than
//   64 events arrived the newest 64 are kept and the rest counted in `droppedEvents`.
// Not Sendable: one thread (the compositor's) drives a buffer.
import AnalysisFeatures

public struct LayerAudioContext {
    /// The latest analysis frame's metadata (ANL-016-R2); nil before any analysis.
    public var frame: AnalysisFrame?
    /// Its bands, normalized 0…1, at most 128.
    public var bands: UnsafeBufferPointer<Float>
    /// Events since the previous frame (ANL-016-R3), oldest first, at most 64.
    public var events: UnsafeBufferPointer<AnalysisEvent>
    /// Events that arrived since the previous frame but are not in `events`.
    public var droppedEvents: Int

    public init(frame: AnalysisFrame?, bands: UnsafeBufferPointer<Float>, events: UnsafeBufferPointer<AnalysisEvent>,
                droppedEvents: Int) {
        self.frame = frame
        self.bands = bands
        self.events = events
        self.droppedEvents = droppedEvents
    }

    /// No analysis: no frame, no bands, no events.
    public static var empty: LayerAudioContext {
        LayerAudioContext(frame: nil, bands: UnsafeBufferPointer(start: nil, count: 0),
                          events: UnsafeBufferPointer(start: nil, count: 0), droppedEvents: 0)
    }
}

/// What `LayerAudioBuffer.update(from:)` reads: the two allocation-free subscriber calls of the
/// analysis bus.
public protocol AnalysisMailbox: AnyObject {
    func nextEvent() -> AnalysisEvent?
    func latestFrame(into destination: UnsafeMutablePointer<Float>, capacity: Int) -> AnalysisFrame?
}

extension AnalysisSubscription: AnalysisMailbox {}

public final class LayerAudioBuffer {
    public static let bandCapacity = 128
    public static let eventCapacity = 64

    private let bandStorage: UnsafeMutablePointer<Float>
    /// Ring while reading, then linearized into `events` oldest first.
    private let ring: UnsafeMutablePointer<AnalysisEvent>
    private let linear: UnsafeMutablePointer<AnalysisEvent>
    private var frame: AnalysisFrame?
    private var bandCount = 0
    private var eventCount = 0
    private var dropped = 0

    public init() {
        bandStorage = .allocate(capacity: Self.bandCapacity)
        bandStorage.initialize(repeating: 0, count: Self.bandCapacity)
        let placeholder = AnalysisEvent(id: 0, time: AnalysisTimestamp(session: 0, sessionSample: 0, timelineSample: 0, hostNanoseconds: 0),
                                        eventSample: 0, kind: .sessionEnded(.detached))
        ring = .allocate(capacity: Self.eventCapacity)
        ring.initialize(repeating: placeholder, count: Self.eventCapacity)
        linear = .allocate(capacity: Self.eventCapacity)
        linear.initialize(repeating: placeholder, count: Self.eventCapacity)
    }

    deinit {
        bandStorage.deinitialize(count: Self.bandCapacity)
        bandStorage.deallocate()
        ring.deinitialize(count: Self.eventCapacity)
        ring.deallocate()
        linear.deinitialize(count: Self.eventCapacity)
        linear.deallocate()
    }

    /// The values for this frame (valid until the next `update`, `set` or `clear`).
    public var context: LayerAudioContext {
        LayerAudioContext(frame: frame, bands: UnsafeBufferPointer(start: bandStorage, count: bandCount),
                          events: UnsafeBufferPointer(start: linear, count: eventCount), droppedEvents: dropped)
    }

    /// Reads the mailbox for a new frame: the newest analysis frame if one arrived (the previous one
    /// stays otherwise) and every event queued since the last read. Allocation-free.
    public func update(from mailbox: some AnalysisMailbox) {
        if let newer = mailbox.latestFrame(into: bandStorage, capacity: Self.bandCapacity) {
            frame = newer
            bandCount = min(max(newer.bandCount, 0), Self.bandCapacity)
        }
        var received = 0
        while let event = mailbox.nextEvent() {
            ring[received % Self.eventCapacity] = event
            received += 1
        }
        finishEvents(received: received)
    }

    /// Sets the values directly (tests, offline rendering). Allocation-free for the caller's buffers.
    public func set(frame: AnalysisFrame?, bands: some Collection<Float>, events: some Collection<AnalysisEvent>) {
        self.frame = frame
        var n = 0
        for value in bands where n < Self.bandCapacity {
            bandStorage[n] = value
            n += 1
        }
        bandCount = n
        var received = 0
        for event in events {
            ring[received % Self.eventCapacity] = event
            received += 1
        }
        finishEvents(received: received)
    }

    /// No frame, no bands, no events.
    public func clear() {
        frame = nil
        bandCount = 0
        eventCount = 0
        dropped = 0
    }

    /// `received` events went into the ring in order; keep the newest `eventCapacity`, oldest first.
    private func finishEvents(received: Int) {
        let kept = min(received, Self.eventCapacity)
        let first = received - kept   // index (in arrival order) of the oldest kept event
        for k in 0..<kept { linear[k] = ring[(first + k) % Self.eventCapacity] }
        eventCount = kept
        dropped = received - kept
    }
}
