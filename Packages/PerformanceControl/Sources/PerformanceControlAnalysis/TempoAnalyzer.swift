// TempoAnalyzer.swift — tempo estimates from an ANL-016 pipeline (SHOW-011-R14; research
// SHOW-011-D3, D5; contracts/tempo-source.md).
//
// * `TempoSubscriptionReader` reads one bus subscription: `poll()` drains its events and reads the
//   newest frame into a preallocated 128-float scratch, then returns the estimate. One owner
//   calls it (the app's main actor); it never runs on the pipeline's worker.
// * `TempoAnalyzer` owns its own pipeline for when no other pipeline reads the analysis tap (the
//   app's projectM case; the circular spectrum's pipeline serves the other case). `start`/`stop`
//   are idempotent and synchronous; `stop` also clears the reader's estimate.
// Nothing here reaches projectM (Constitution VIII, ADR-0008 decision 5).
import AnalysisFeatures
import AudioCore
import PerformanceControl

public final class TempoSubscriptionReader: @unchecked Sendable {
    public let subscription: AnalysisSubscription
    private var tracker: TempoEstimateTracker
    private let scratch: UnsafeMutablePointer<Float>

    public init(subscription: AnalysisSubscription, sampleRate: Double) {
        self.subscription = subscription
        tracker = TempoEstimateTracker(sampleRate: sampleRate)
        scratch = .allocate(capacity: AnalysisSubscription.maximumBands)
        scratch.initialize(repeating: 0, count: AnalysisSubscription.maximumBands)
    }

    deinit {
        scratch.deinitialize(count: AnalysisSubscription.maximumBands)
        scratch.deallocate()
    }

    /// Takes everything published since the last poll; returns the current estimate.
    public func poll() -> TempoEstimate? {
        // Items apply in ID order, so a frame read before a session marker cannot bring back the
        // tempo the marker cleared (IDs are the bus's publication order, ANL-016-R4).
        var frame = subscription.latestFrame(into: scratch, capacity: AnalysisSubscription.maximumBands)
        while let event = subscription.nextEvent() {
            if let pending = frame, pending.id < event.id {
                tracker.observe(pending)
                frame = nil
            }
            tracker.observe(event)
        }
        if let frame { tracker.observe(frame) }
        return tracker.estimate
    }

    /// Forgets the estimate (the analysis stopped).
    public func clear() {
        tracker.clear()
    }
}

public final class TempoAnalyzer: @unchecked Sendable {
    public let reader: TempoSubscriptionReader
    private let pipeline: AnalysisPipeline

    /// A pipeline with the standard configuration (16 bands; only tempo is read).
    public init() throws {
        let configuration = try AnalysisPipelineConfiguration(spectrum: AnalysisPipelineConfiguration.defaultSpectrum,
                                                              bandCount: .b16)
        pipeline = AnalysisPipeline(configuration: configuration)
        reader = TempoSubscriptionReader(subscription: try pipeline.subscribe(),
                                         sampleRate: configuration.spectrum.sampleRate)
    }

    deinit {
        pipeline.stop()
    }

    /// Starts analysing `reader` (an analysis tap: one consumer only). Idempotent.
    public func start(reader tap: any NormalizedPCMReader) {
        pipeline.start(reader: tap)
    }

    /// Stops; when this returns no further item is published and the estimate is cleared.
    public func stop() {
        pipeline.stop()
        while reader.subscription.nextEvent() != nil {}
        reader.clear()
    }

    public var isRunning: Bool { pipeline.isRunning }
}
