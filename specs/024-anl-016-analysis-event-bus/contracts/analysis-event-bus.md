# Contract: Analysis event bus (ANL-016)

Module `AnalysisFeatures`. Nothing here is ever passed to projectM (ADR-0008 decision 5).

## AudioCore delta

```swift
public protocol AnalysisSessionReporting: Sendable {
    /// Increases when the ring is reset for a new capture session (after the tap is emptied).
    var analysisSessionGeneration: UInt64 { get }
}
// NormalizedPCMRing: `public var analysisSessionGeneration: UInt64`; its analysis tap reader
// conforms to AnalysisSessionReporting. `reset()` increments it; `discardBuffered()` does not.
```

## AnalysisPipeline

```swift
public final class AnalysisPipeline: @unchecked Sendable {
    public static let maximumSubscribers = 16
    public static let workerInterval: DispatchTimeInterval   // 10 ms
    public init(configuration: AnalysisPipelineConfiguration = .standard,
                backend: SpectrumBackend = .automatic,
                clock: @escaping @Sendable () -> UInt64 = { MonotonicClock.nowNanoseconds() })
    public func attach(_ reader: any NormalizedPCMReader)   // ends a current session, starts one (.attached)
    public func detach()                                     // ends the session (.detached); idempotent
    public func restartSession()                             // explicit restart (.restarted); no-op when detached
    @discardableResult public func step() -> Int             // reads everything available; returns frames read
    public func startWorker(); public func stopWorker()      // idempotent, synchronous
    public func start(reader:)                               // attach + startWorker (no-op if running)
    public func stop()                                       // stopWorker + detach
    public func setBandCount(_ count: BandCount)             // next frame
    public func subscribe(eventCapacity: Int = 64) throws(AnalysisBusError) -> AnalysisSubscription
    public func unsubscribe(_ subscription: AnalysisSubscription)   // idempotent
    public var isAttached: Bool; public var isRunning: Bool; public var currentSession: UInt64
    public var lastItemID: UInt64
}
```

Threading: all methods may be called from any thread except the pipeline's own worker (none of
the caller's code runs there). `step()` and the timer are serialized on the worker.

## AnalysisSubscription

```swift
public final class AnalysisSubscription: @unchecked Sendable {
    public let eventCapacity: Int
    /// Newest frame not yet read; copies min(bandCount, capacity) bands. Nil when nothing new.
    public func latestFrame(into bands: UnsafeMutablePointer<Float>, capacity: Int) -> AnalysisFrame?
    public func nextEvent() -> AnalysisEvent?                       // oldest queued, allocation-free
    public func drainEvents() -> [AnalysisEvent]                    // convenience (allocates)
    public var droppedEvents: Int; public var overwrittenFrames: Int; public var isCancelled: Bool
}
```

## Guarantees

1. IDs: start at 1, +1 per published item, never reused for the pipeline's lifetime.
2. Order: items are published in ID order; `time.timelineSample` and `time.hostNanoseconds` never
   decrease in ID order. Per frame: frame, onset?, beat?.
3. Sessions: every session start publishes `sessionStarted` (preceded by `sessionEnded` of the old
   one if any); afterwards no item of the old session is published, and every subscription's frame
   slot is empty until the new session's first frame.
4. Overflow: events drop-oldest per subscription (counted); frames latest-wins (counted).
   `received + dropped + pending = published since subscribe` (until cancel).
5. Unsubscribe: when it returns, the subscription is cancelled, emptied, and receives nothing more.
6. Determinism: same input + configuration + clock -> identical items.
7. Real time: after `init`, `step` allocates nothing; locks guard constant-size copies only.
