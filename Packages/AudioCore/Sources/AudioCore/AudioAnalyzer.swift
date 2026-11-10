// AudioAnalyzer.swift — the analysis work queue (research R-06; task T029 support).
//
// A serial, user-interactive-QoS queue drains the PCMSink ring every ≤ 10 ms, measures
// levels, runs the AudioStateClassifier, and publishes an `AnalyzerUpdate` at most 4 times
// per second (and at least once per second, FR-020). Nothing here runs on the audio thread
// or the main thread. All classifier access is confined to `queue`.
//
// Session time: 0 is the moment `apply(.started)` runs, which the manager does right after the
// source's `start` returned (so time spent in the system picker or a permission prompt is not
// session time; the sink's sample timestamps use the same zero, see `PCMSink.markSessionStart`).
// Between `beginAttempt()` and `.started`/`.startFailed` session time reads 0.
//
// Transitions: every transition of the current attempt is kept, in order, in a log that callers
// read synchronously with `transitions(from:)`. That log does not depend on the timer, so final
// transitions (stopped, endedBySystem, startFailed) applied after `stopTimer()` are not lost.
import Dispatch

public struct AnalyzerUpdate: Sendable, Equatable {
    public var state: AudioState
    public var reason: StopReason?
    public var prolongedSilenceHint: Bool
    public var hasVerifiedActiveAudio: Bool
    public var levels: LevelMeter.Levels
    public var statistics: PCMSinkStatistics
    /// Transitions since the previous update (published or returned by `apply`). Each transition
    /// appears in exactly one update. `AudioAnalyzer.transitions(from:)` is the ordered record.
    public var newTransitions: [StateTransition]
    /// Seconds since the session started.
    public var sessionSeconds: Double
    /// Monotonic per-analyzer sequence. Consumers ignore updates older than the newest seen,
    /// so a published update that arrives late never overwrites a newer synchronous result.
    public var sequence: UInt64
    /// Set once the Normalizer met an unconvertible format in this session (FR-017); the manager
    /// then stops the source with this reason. Normalization stays off until the next attempt.
    public var conversionFailure: StopReason? = nil
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
    /// Every transition of the current attempt, in order (at most `maxTransitions`).
    private var log: [StateTransition] = []
    private var sessionStart: Double
    /// True between `beginAttempt()` and the `.started`/`.startFailed` that ends it.
    private var attemptPending = false
    private var sequence: UInt64 = 0
    private var onUpdate: (@Sendable (AnalyzerUpdate) -> Void)?
    /// Normalized audio for the renderer (research R-05/R-06), filled on this queue.
    public let normalizedOutput = NormalizedPCMRing()
    private let normalizer: Normalizer
    private var conversionFailure: StopReason?
    private var signposts: (any AudioPipelineSignposts)?

    /// Maximum transitions recorded per session (export schema `maxItems`).
    public static let maxTransitions = 1000

    public init(sink: PCMSink, thresholds: ClassifierThresholds = .default,
                clock: @escaping @Sendable () -> Double = { MonotonicClock.nowSeconds() }) {
        self.sink = sink
        self.clock = clock
        sessionStart = clock()
        classifier = AudioStateClassifier(thresholds: thresholds)
        normalizer = Normalizer(output: normalizedOutput)
        scratchCount = PCMSink.maxSampleRate * PCMSink.maxChannels / 10   // up to 100 ms per drain
        scratch = UnsafeMutablePointer<Float>.allocate(capacity: scratchCount)
        scratch.initialize(repeating: 0, count: scratchCount)
        log.reserveCapacity(AudioAnalyzer.maxTransitions)
    }

    deinit {
        timer?.cancel()
        scratch.deinitialize(count: scratchCount)
        scratch.deallocate()
    }

    public func setUpdateHandler(_ handler: @escaping @Sendable (AnalyzerUpdate) -> Void) {
        queue.sync { onUpdate = handler }
    }

    /// Latency-stage signposts (task T062); nil turns them off.
    public func setSignposts(_ signposts: (any AudioPipelineSignposts)?) {
        queue.sync { self.signposts = signposts }
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

    /// Begins a new start attempt, before the source's `start` (which may show the system picker
    /// or a permission prompt). Forgets everything about the previous session: the classifier
    /// returns to Not started with no verified audio and no reason, the transition log is
    /// emptied, and levels are silent. Stop the timer and reset the sink first. Every update
    /// published before this one belongs to the previous session; callers drop updates whose
    /// `sequence` is not greater than the returned update's.
    @discardableResult
    public func beginAttempt() -> AnalyzerUpdate {
        queue.sync {
            let now = clock()
            classifier = AudioStateClassifier(thresholds: classifier.thresholds)
            resetSession(at: now)
            attemptPending = true
            return makeUpdate(at: now)
        }
    }

    /// Applies a lifecycle event synchronously and returns the resulting update. Its
    /// `newTransitions` hold every transition not yet delivered (including this event's), and
    /// they are not delivered again; `transitions(from:)` also has them immediately.
    ///
    /// `.startFailed` always records a transition (to Not started, with its reason), even when
    /// the state does not change, so a failed attempt shows in the export.
    @discardableResult
    public func apply(_ event: LifecycleEvent) -> AnalyzerUpdate {
        queue.sync {
            let now = clock()
            var forceRecord = false
            switch event {
            case .started:
                if !attemptPending { resetSession(at: now) }
                sessionStart = now
                attemptPending = false
            case .startFailed:
                attemptPending = false
                forceRecord = true
            default:
                break
            }
            let before = classifier.state
            classifier.lifecycle(event, at: now)
            if forceRecord { record(at: now) } else { recordIfChanged(from: before, at: now) }
            let update = makeUpdate(at: now)
            pending.removeAll(keepingCapacity: true)
            return update
        }
    }

    /// The current attempt's transitions from index `start` on, in order. Safe from any thread.
    public func transitions(from start: Int) -> [StateTransition] {
        queue.sync { start < log.count ? Array(log[max(0, start)...]) : [] }
    }

    /// Session time now (see the header), for stamping events handled outside the analyzer such as
    /// app lifecycle notifications. Keeps advancing after the source stops; 0 while a start
    /// attempt is pending.
    public func currentSessionSeconds() -> Double {
        queue.sync { attemptPending ? 0 : max(0, clock() - sessionStart) }
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
        let format = sink.statistics().format
        let sampleRate = format?.sampleRate ?? 48_000
        // The ring holds interleaved Float32 with `channels` channels (PCMSink keeps at most 8).
        let normalizedInput = format.map {
            AudioFormat(sampleRate: $0.sampleRate, channelCount: channels, isInterleaved: true, sampleType: .float32)
        }
        let layout = sink.currentLayout
        var total = 0
        var peak: Float = LevelMeter.floorDBFS
        var rms: Float = LevelMeter.floorDBFS
        func drainRing() {
            while true {
                let n = sink.ring.read(into: scratch, maxCount: scratchCount)
                if n == 0 { break }
                let levels = LevelMeter.measure(scratch, count: n)
                peak = max(peak, levels.peakDBFS)
                rms = max(rms, levels.rmsDBFS)
                if conversionFailure == nil, let normalizedInput,
                   case .failed(let reason) = normalizer.process(scratch, frames: n / channels,
                                                                 format: normalizedInput, layout: layout) {
                    conversionFailure = reason
                }
                total += n
                if n < scratchCount { break }
            }
        }
        // Signposted only when there is audio, so idle 10 ms ticks add no intervals.
        if let signposts, sink.ring.availableToRead > 0 {
            signposts.ringAndConversion(drainRing)
        } else {
            drainRing()
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
            reportLatencies()
            let toSend = update
            pending.removeAll(keepingCapacity: true)
            onUpdate?(toSend)
        }
        return update
    }

    /// Capture delivery and normalized residency, at most 4 times per second (task T062).
    private func reportLatencies() {
        guard let signposts else { return }
        let deliveryNs = sink.takeCaptureDeliveryMaxNs()
        if deliveryNs > 0 { signposts.captureDelivery(milliseconds: Double(deliveryNs) / 1_000_000) }
        let backlog = normalizedOutput.lastReadBacklogFrames
        if backlog > 0 {
            let waited = min(backlog, NormalizedPCMRing.freshnessFrames)   // older frames were skipped
            signposts.normalizedResidency(milliseconds: Double(waited) * 1000 / NormalizedPCMRing.sampleRate)
        }
    }

    private func resetSession(at now: Double) {
        sessionStart = now
        log.removeAll(keepingCapacity: true)
        pending.removeAll(keepingCapacity: true)
        lastLevels = .silent
        lastPublish = -.infinity
        normalizer.reset()
        normalizedOutput.reset()
        conversionFailure = nil
    }

    private func recordIfChanged(from before: AudioState, at now: Double) {
        guard classifier.state != before else { return }
        record(at: now)
    }

    private func record(at now: Double) {
        guard log.count < AudioAnalyzer.maxTransitions else { return }
        let transition = StateTransition(atSeconds: sessionSeconds(at: now), state: classifier.state,
                                         reason: classifier.lastReason?.code)
        log.append(transition)
        pending.append(transition)
    }

    private func sessionSeconds(at now: Double) -> Double {
        attemptPending ? 0 : max(0, now - sessionStart)
    }

    private func makeUpdate(at now: Double) -> AnalyzerUpdate {
        sequence &+= 1
        return AnalyzerUpdate(state: classifier.state, reason: classifier.lastReason,
                       prolongedSilenceHint: classifier.prolongedSilenceHint,
                       hasVerifiedActiveAudio: classifier.hasVerifiedActiveAudio,
                       levels: lastLevels, statistics: sink.statistics(),
                       newTransitions: pending, sessionSeconds: sessionSeconds(at: now),
                       sequence: sequence, conversionFailure: conversionFailure)
    }
}
