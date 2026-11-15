// OfflineAnalysisDriver.swift — REC-013 the live analysis, stepped once per export frame
// (specs/240-rec-013-deterministic-offline-export; R4; research REC-013-D2). Builds on Linux.
//
// One ANL-016 `AnalysisPipeline` (the live configuration: the bar count, `SpectrumBandFeed`'s floor) with a clock that
// always reads 0, attached to a VIS-003/004 `WaveformTap` around an `OfflinePCMSource`. The worker timer is never
// started: `advance(toSample:)` moves the source's readable end and calls `step()`, which analyses everything up to it
// on the calling thread's behalf (synchronously). It then copies the newest bus frame (kept when no new spectrum
// completed, as the live frame loop keeps its last bands), the waveform histories, and drains this frame's events.
// No thread timing or real clock enters the result, so the same audio gives the same frames on every run.
import AnalysisFeatures
import AudioCore
import VisualGenerators

/// What one export frame reads from the analysis.
public struct OfflineAnalysisFrame: Sendable {
    /// Bands of the newest spectrum (count = the bar count; zeros before the first spectrum).
    public var bands: [Float]
    /// The newest 4,096 mono samples (oldest first).
    public var mono: [Float]
    /// The newest 2,048 stereo frames, interleaved (oldest first).
    public var stereo: [Float]
    /// ANL-007's kick envelope of the newest frame.
    public var kickEnvelope: Float
    /// The bus session of the newest frame (ANL-003's smoother generation).
    public var session: UInt64
    /// Events published since the previous frame, in bus order.
    public var events: [AnalysisEvent]
}

public final class OfflineAnalysisDriver: @unchecked Sendable {
    public let source: OfflinePCMSource
    private let tap: WaveformTap
    private let pipeline: AnalysisPipeline
    private let frames: AnalysisSubscription
    private let eventMailbox: AnalysisSubscription
    private var current: OfflineAnalysisFrame

    public init(interleaved: [Float], barCount: SpectrumBarCount) throws {
        let configuration = try AnalysisPipelineConfiguration(spectrum: AnalysisPipelineConfiguration.defaultSpectrum,
                                                              bandCount: BandCount(rawValue: barCount.rawValue)!,
                                                              bandFloorDecibels: SpectrumBandFeed.floorDecibels)
        pipeline = AnalysisPipeline(configuration: configuration, clock: { () -> UInt64 in 0 })
        source = OfflinePCMSource(interleaved: interleaved)
        tap = WaveformTap(source)
        frames = try pipeline.subscribe()
        eventMailbox = try pipeline.subscribe(eventCapacity: AnalysisSubscription.eventCapacityRange.upperBound)
        current = OfflineAnalysisFrame(bands: [Float](repeating: 0, count: barCount.rawValue),
                                       mono: [Float](repeating: 0, count: WaveformFrameBuffer.capacity),
                                       stereo: [Float](repeating: 0, count: WaveformFrameBuffer.capacity),
                                       kickEnvelope: 0, session: 0, events: [])
        pipeline.attach(tap)
    }

    deinit {
        pipeline.detach()
    }

    /// Analyses the audio up to `sample` (exclusive, stereo frames from the start) and returns what a frame drawn
    /// there sees. `sample` should not decrease.
    public func advance(toSample sample: Int) -> OfflineAnalysisFrame {
        source.expose(upTo: sample)
        // `step` reads until the source is empty; a chunk that does not fit the stream is analysed on the next pass.
        while pipeline.step() > 0 {}
        let count = current.bands.count
        var bands: [Float] = current.bands
        let latest: AnalysisFrame? = bands.withUnsafeMutableBufferPointer { (out: inout UnsafeMutableBufferPointer<Float>) -> AnalysisFrame? in
            frames.latestFrame(into: out.baseAddress!, capacity: count)
        }
        if let latest {
            current.bands = bands
            current.kickEnvelope = latest.kickEnvelope
            current.session = latest.time.session
        }
        current.mono.withUnsafeMutableBufferPointer { (out: inout UnsafeMutableBufferPointer<Float>) -> Void in
            _ = tap.output.readLatest(into: out.baseAddress!, capacity: WaveformFrameBuffer.capacity)
        }
        current.stereo.withUnsafeMutableBufferPointer { (out: inout UnsafeMutableBufferPointer<Float>) -> Void in
            _ = tap.stereoOutput.readLatest(into: out.baseAddress!, capacity: WaveformFrameBuffer.capacity)
        }
        current.events = eventMailbox.drainEvents()
        return current
    }

    /// Events the mailbox had to drop (should stay 0: it holds 1,024 and is drained every frame).
    public var droppedEvents: Int { eventMailbox.droppedEvents }
}
