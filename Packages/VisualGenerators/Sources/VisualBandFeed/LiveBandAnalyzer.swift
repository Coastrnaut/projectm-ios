// LiveBandAnalyzer.swift — the native visual's analysis worker (VIS-001-R14, R15; research
// VIS-001-D5).
//
// A serial queue (`org.projectmios.visual-analysis`, user-interactive QoS) runs a 10 ms timer only
// while started. Each tick pulls the analysis tap through `SpectrumBandFeed` and, when a new spectrum
// was reduced, publishes the band vector into `output`, a wait-free triple buffer the frame loop
// reads. Nothing runs on the audio callback or the main thread. `start`/`stop` are idempotent and
// synchronous: when `stop` returns, the timer is cancelled and no further frame is published. The
// analysis event bus (ANL-016) will replace the timer.
import AudioCore
import Dispatch
import VisualGenerators

public final class LiveBandAnalyzer: @unchecked Sendable {
    public static let interval: DispatchTimeInterval = .milliseconds(10)

    /// Newest band frames, for the frame loop.
    public let output = BandFrameBuffer()

    // Everything below is touched only on `queue`.
    private let queue = DispatchQueue(label: "org.projectmios.visual-analysis", qos: .userInteractive)
    private let feed: SpectrumBandFeed
    private var timer: DispatchSourceTimer?
    private var reader: (any NormalizedPCMReader)?

    public init(barCount: SpectrumBarCount) throws {
        feed = try SpectrumBandFeed(barCount: barCount)
    }

    deinit {
        timer?.cancel()
    }

    /// Starts pulling `reader` (an analysis tap: one consumer only, never projectM's ring).
    public func start(reader: any NormalizedPCMReader) {
        queue.sync {
            guard timer == nil else { return }
            self.reader = reader
            feed.reset()
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: Self.interval, leeway: .milliseconds(2))
            t.setEventHandler { [weak self] in self?.tick() }
            timer = t
            t.resume()
        }
    }

    /// Stops; returns after the timer is cancelled on the queue.
    public func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
            reader = nil
        }
    }

    public var isRunning: Bool { queue.sync { timer != nil } }

    /// Takes effect at the next tick.
    public func setBarCount(_ barCount: SpectrumBarCount) {
        queue.async { [feed] in feed.setBarCount(barCount) }
    }

    private func tick() {
        guard timer != nil, let reader else { return }
        if feed.pull(from: reader) {
            output.write(feed.bands, timestampNanoseconds: feed.timestampNanoseconds)
        }
    }
}
