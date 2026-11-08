// AudioAnalyzer.swift — the analysis work queue (research R-06; task T029 support).
//
// A serial, user-interactive-QoS queue drains the PCMSink ring every ≤ 10 ms, measures
// levels, runs the AudioStateClassifier, and publishes an `AnalyzerUpdate` at most 4 times
// per second (and at least once per second, FR-020). Nothing here runs on the audio thread
// or the main thread. All classifier access is confined to `queue`.
import Dispatch

public struct AnalyzerUpdate: Sendable, Equatable {
    public var state: AudioState
    public var reason: StopReason?
    public var prolongedSilenceHint: Bool
    public var hasVerifiedActiveAudio: Bool
    public var levels: LevelMeter.Levels
    public var statistics: PCMSinkStatistics
    /// Transitions since the previous update.
    public var newTransitions: [StateTransition]
    /// Seconds since the session started.
    public var sessionSeconds: Double
    /// Monotonic per-analyzer sequence. Consumers ignore updates older than the newest seen,
    /// so a published update that arrives late never overwrites a newer synchronous result.
    public var sequence: UInt64
}

public final class AudioAnalyzer: @unchecked Sendable {
    public static let drainInterval: DispatchTimeInterval = .milliseconds(10)
    public static let publishInterval: Double = 0.25

    private let queue = DispatchQueue(label: "org.projectmios.audio-analysis", qos: .userInteractive)
    private let sink: PCMSink
    private let clock: @Sendable () -> Double
    private var classifier: AudioStateClassifier
    private var timer: DispatchSourceTimer?
    private let scratch: UnsafeMutablePointer<Float>
    private let scratchCount: Int
    private var lastPublish: Double = -.infinity
    private var lastLevels = LevelMeter.Levels.silent
    private var pending: [StateTransition] = []
    private var transitionCount = 0
    private var sessionStart: Double = 0
    private var sequence: UInt64 = 0
    private var onUpdate: (@Sendable (AnalyzerUpdate) -> Void)?

    /// Maximum transitions recorded per session (export schema `maxItems`).
    public static let maxTransitions = 1000

    public init(sink: PCMSink, thresholds: ClassifierThresholds = .default,
                clock: @escaping @Sendable () -> Double = { MonotonicClock.nowSeconds() }) {
        self.sink = sink
        self.clock = clock
        classifier = AudioStateClassifier(thresholds: thresholds)
        scratchCount = PCMSink.maxSampleRate * PCMSink.maxChannels / 10   // up to 100 ms per drain
        scratch = UnsafeMutablePointer<Float>.allocate(capacity: scratchCount)
        scratch.initialize(repeating: 0, count: scratchCount)
    }

    deinit {
        timer?.cancel()
        scratch.deinitialize(count: scratchCount)
        scratch.deallocate()
    }

    public func setUpdateHandler(_ handler: @escaping @Sendable (AnalyzerUpdate) -> Void) {
        queue.sync { onUpdate = handler }
    }

    /// Starts periodic draining (production). Tests call `step()` instead.
    public func startTimer() {
        queue.sync {
            guard timer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: AudioAnalyzer.drainInterval, leeway: .milliseconds(2))
            t.setEventHandler { [weak self] in self?.drainAndClassify(force: false) }
            timer = t
            t.resume()
        }
    }

    public func stopTimer() {
        queue.sync {
            timer?.cancel()
            timer = nil
        }
    }

    /// Applies a lifecycle event synchronously and returns the resulting update. The returned
    /// update's `newTransitions` are delivered again by the next published update, so callers
    /// should take transitions only from the update handler.
    @discardableResult
    public func apply(_ event: LifecycleEvent) -> AnalyzerUpdate {
        queue.sync {
            let now = clock()
            if event == .started {
                sessionStart = now
                transitionCount = 0
                pending.removeAll(keepingCapacity: true)
                lastLevels = .silent
            }
            let before = classifier.state
            classifier.lifecycle(event, at: now)
            recordIfChanged(from: before, at: now)
            return makeUpdate(at: now)
        }
    }

    /// One synchronous drain/classify pass, publishing immediately (tests and manual drive).
    @discardableResult
    public func step() -> AnalyzerUpdate {
        queue.sync { drainAndClassify(force: true) }
    }

    public var currentState: AudioState { queue.sync { classifier.state } }

    // MARK: - Queue-confined

    @discardableResult
    private func drainAndClassify(force: Bool) -> AnalyzerUpdate {
        let now = clock()
        let before = classifier.state
        let channels = max(1, sink.currentChannelCount)
        let sampleRate = sink.statistics().format?.sampleRate ?? 48_000
        var total = 0
        var peak: Float = LevelMeter.floorDBFS
        var rms: Float = LevelMeter.floorDBFS
        while true {
            let n = sink.ring.read(into: scratch, maxCount: scratchCount)
            if n == 0 { break }
            let levels = LevelMeter.measure(scratch, count: n)
            peak = max(peak, levels.peakDBFS)
            rms = max(rms, levels.rmsDBFS)
            total += n
            if n < scratchCount { break }
        }
        if total > 0 {
            let duration = Double(total / channels) / sampleRate
            classifier.dataArrived(at: now, peakDBFS: peak, duration: duration)
            lastLevels = LevelMeter.Levels(peakDBFS: peak, rmsDBFS: rms)
        } else {
            classifier.tick(at: now)
        }
        recordIfChanged(from: before, at: now)
        let update = makeUpdate(at: now)
        // At most 4 publishes per second (R-06); a state change is visible within 250 ms.
        if force || now - lastPublish >= AudioAnalyzer.publishInterval {
            lastPublish = now
            let toSend = update
            pending.removeAll(keepingCapacity: true)
            onUpdate?(toSend)
        }
        return update
    }

    private func recordIfChanged(from before: AudioState, at now: Double) {
        guard classifier.state != before, transitionCount < AudioAnalyzer.maxTransitions else { return }
        transitionCount += 1
        pending.append(StateTransition(atSeconds: max(0, now - sessionStart), state: classifier.state,
                                       reason: classifier.lastReason?.code))
    }

    private func makeUpdate(at now: Double) -> AnalyzerUpdate {
        sequence &+= 1
        return AnalyzerUpdate(state: classifier.state, reason: classifier.lastReason,
                       prolongedSilenceHint: classifier.prolongedSilenceHint,
                       hasVerifiedActiveAudio: classifier.hasVerifiedActiveAudio,
                       levels: lastLevels, statistics: sink.statistics(),
                       newTransitions: pending, sessionSeconds: max(0, now - sessionStart),
                       sequence: sequence)
    }
}
