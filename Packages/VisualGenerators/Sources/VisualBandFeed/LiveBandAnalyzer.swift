// LiveBandAnalyzer.swift — the native visual's analysis, on the analysis event bus (VIS-001-R14,
// R15; ANL-016-R16; research ANL-016-D6).
//
// The analyzer owns an `AnalysisPipeline` (ANL-016: one serial worker with a 10 ms timer, 2,048-point
// spectra at hop 512, mid channel, bands = the bar count, −80 dB floor) and one subscription. The
// frame loop reads the newest band vector through `output.readLatest(into:capacity:)` without
// waiting for analysis (the subscription's lock guards only a 128-float copy). Nothing runs on the
// audio callback or the main thread. `start`/`stop` are idempotent and synchronous: when `stop`
// returns, the worker's timer is cancelled, the session ended and no further frame is published.
// A capture restart (the normalized ring's reset) starts a new bus session by itself.
//
// Nothing computed here reaches projectM (Constitution VIII, ADR-0008 decision 5).
import AnalysisFeatures
import AudioCore
import Dispatch
import VisualGenerators

/// What `LiveBandOutput.readLatest` returns besides the values.
public struct LiveBandFrameInfo: Sendable, Equatable {
    /// Values copied (at most the reader's capacity and 128).
    public var count: Int
    /// The bus's host time of the frame (monotonic nanoseconds).
    public var timestampNanoseconds: UInt64
    /// The bus item ID of the frame (strictly increasing).
    public var sequence: UInt64
    /// The frame's capture-session generation (ANL-016 `AnalysisTimestamp.session`); ANL-003's
    /// smoother restarts when it changes.
    public var session: UInt64 = 0
    /// ANL-007's kick envelope (0…1) of the frame, for MOD-002's Kick source.
    public var kickEnvelope: Float = 0
    /// ANL-010's normalized spectral centroid (0…1) of the frame, for MOD-002's Centroid source.
    public var centroid: Float = 0
}

/// The frame loop's view of the analyzer's bus subscription.
public final class LiveBandOutput: Sendable {
    private let subscription: AnalysisSubscription

    init(subscription: AnalysisSubscription) { self.subscription = subscription }

    /// Copies the newest band vector into `destination` (room for `capacity` values) when one arrived
    /// since the last read; nil otherwise (the caller keeps its last values). Allocation-free.
    public func readLatest(into destination: UnsafeMutablePointer<Float>, capacity: Int) -> LiveBandFrameInfo? {
        guard let frame = subscription.latestFrame(into: destination, capacity: capacity) else { return nil }
        return LiveBandFrameInfo(count: min(frame.bandCount, max(capacity, 0)), timestampNanoseconds: frame.time.hostNanoseconds,
                                 sequence: frame.id, session: frame.time.session, kickEnvelope: frame.kickEnvelope,
                                 centroid: frame.centroid)
    }
}

public final class LiveBandAnalyzer: Sendable {
    public static let interval: DispatchTimeInterval = AnalysisPipeline.workerInterval

    /// Newest band frames, for the frame loop.
    public let output: LiveBandOutput
    private let pipeline: AnalysisPipeline

    public init(barCount: SpectrumBarCount) throws {
        let configuration = try AnalysisPipelineConfiguration(spectrum: AnalysisPipelineConfiguration.defaultSpectrum,
                                                              bandCount: BandCount(rawValue: barCount.rawValue)!,
                                                              bandFloorDecibels: SpectrumBandFeed.floorDecibels)
        pipeline = AnalysisPipeline(configuration: configuration)
        output = LiveBandOutput(subscription: try pipeline.subscribe())
    }

    deinit {
        pipeline.stop()
    }

    /// Starts analysing `reader` (an analysis tap: one consumer only, never projectM's ring).
    public func start(reader: any NormalizedPCMReader) {
        pipeline.start(reader: reader)
    }

    /// Stops; returns after the worker's timer is cancelled and the session ended.
    public func stop() {
        pipeline.stop()
    }

    public var isRunning: Bool { pipeline.isRunning }

    /// Takes effect at the next spectrum.
    public func setBarCount(_ barCount: SpectrumBarCount) {
        pipeline.setBandCount(BandCount(rawValue: barCount.rawValue)!)
    }

    // SHOW-011 hook (research SHOW-011-D3): while this visual is shown its pipeline is the analysis
    // tap's only reader, so other consumers (the tap tempo's estimate) subscribe to it here.

    /// Another subscription on this analyzer's pipeline (ANL-016-R10).
    public func subscribe(eventCapacity: Int = AnalysisSubscription.defaultEventCapacity) throws(AnalysisBusError) -> AnalysisSubscription {
        try pipeline.subscribe(eventCapacity: eventCapacity)
    }

    public func unsubscribe(_ subscription: AnalysisSubscription) {
        pipeline.unsubscribe(subscription)
    }

    /// The pipeline's sample rate (for converting beat samples to time).
    public var sampleRate: Double { pipeline.configuration.spectrum.sampleRate }
}
