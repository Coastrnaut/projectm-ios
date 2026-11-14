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
//
// Discontinuities (AUD-006): `discardBufferedAudio()` runs on the queue, so it is ordered against
// every drain pass: audio a pass had already read is in the normalized ring before that ring is
// emptied. The analyzer registers it as its sink's discard handler.
//
// Source switch (AUD-012, contracts/source-handoff.md): `beginHandoffFadeOut()` makes the normalized
// ring fade the old source's audio to silence as drain passes write it; `completeHandoffFadeOut()`
// finishes it from the last sample when the source did not deliver enough; `beginAttempt(handoff:
// true)` starts the new session with `NormalizedPCMRing.resetForHandoff` and arms the fade-in, and
// its first drain pass with audio publishes at once so the switching label clears without waiting
// for the 250 ms cadence. Every drain pass first replaces non-finite samples (counted) so they never
// reach the level meter, the classifier or the Normalizer's converter (AUD-012-R9).
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
    /// Normalized audio for the renderer (research R-05/R-06), filled on this queue. Its analysis tap
    /// (ANL-001-R9) exists only when `init` gets a positive `analysisTapCapacityFrames` (VIS-001-R14).
    public let normalizedOutput: NormalizedPCMRing
    private let normalizer: Normalizer
    private var conversionFailure: StopReason?
    private var signposts: (any AudioPipelineSignposts)?
    /// AUD-012: the current attempt is a source switch whose first audio has not been published yet.
    private var handoffAwaitingFirstAudio = false

    /// Maximum transitions recorded per session (export schema `maxItems`).
    public static let maxTransitions = 1000

    /// - Parameter analysisTapCapacityFrames: > 0 gives the normalized ring an analysis tap of that
    ///   many stereo frames (VIS-001-R14); 0, the default, keeps the ring without one.
    public init(sink: PCMSink, thresholds: ClassifierThresholds = .default,
                clock: @escaping @Sendable () -> Double = { MonotonicClock.nowSeconds() },
                analysisTapCapacityFrames: Int = 0) {
        self.sink = sink
        normalizedOutput = NormalizedPCMRing(analysisTapCapacityFrames: analysisTapCapacityFrames,
                                             sampleBound: PCMSanitizer.bound)   // AUD-012-R9
        self.clock = clock
        sessionStart = clock()
        classifier = AudioStateClassifier(thresholds: thresholds)
        normalizer = Normalizer(output: normalizedOutput)
        scratchCount = PCMSink.maxSampleRate * PCMSink.maxChannels / 10   // up to 100 ms per drain
        scratch = UnsafeMutablePointer<Float>.allocate(capacity: scratchCount)
        scratch.initialize(repeating: 0, count: scratchCount)
        log.reserveCapacity(AudioAnalyzer.maxTransitions)
        sink.setDiscardHandler { [weak self] in self?.discardBufferedAudio() }
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
    ///
    /// `handoff` (AUD-012): the attempt replaces a source in a running visualization. projectM's ring
    /// keeps its faded tail, gets 1,024 frames of silence, and the new source fades in.
    @discardableResult
    public func beginAttempt(handoff: Bool = false) -> AnalyzerUpdate {
        queue.sync {
            let now = clock()
            classifier = AudioStateClassifier(thresholds: classifier.thresholds)
            resetSession(at: now, handoff: handoff)
            attemptPending = true
            return makeUpdate(at: now)
        }
    }

    // MARK: - Source switch (AUD-012)

    /// Starts fading the current source's audio to silence (it keeps delivering meanwhile).
    public func beginHandoffFadeOut() {
        queue.sync { normalizedOutput.beginFadeOut() }
    }

    /// True once the fade-out reached silence.
    public var handoffFadeOutDone: Bool {
        queue.sync { normalizedOutput.handoffPhase == .silent }
    }

    /// Ends the fade-out: drains what the sink holds through the ramp, then completes the ramp from
    /// the last sample if it has not reached silence. Returns the synthesized frames.
    @discardableResult
    public func completeHandoffFadeOut() -> Int {
        queue.sync {
            if normalizedOutput.handoffPhase == .fadingOut { drainAndClassify(force: false) }
            return normalizedOutput.completeFadeOut()
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

    /// Discards every sample that has not been delivered to the renderer yet: the sink ring, the
    /// Normalizer's converter state and the normalized ring; the last levels become silent, so no
    /// level computed from discarded audio is published (AUD-006-R10, R11). The state, the
    /// verified-audio flag, the statistics and the session clock are untouched. Synchronous; the
    /// caller makes sure no producer is writing (`PCMSink.discardBufferedAudio()`). Not callable
    /// from this analyzer's own queue.
    public func discardBufferedAudio() {
        queue.sync {
            sink.ring.drain()
            normalizer.discardPending()
            normalizedOutput.discardBuffered()
            lastLevels = .silent
        }
    }

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
                normalizedOutput.recordSanitized(PCMSanitizer.replaceNonFinite(scratch, count: n))   // AUD-012-R9
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
        // At most 4 publishes per second (R-06); a state change is visible within 250 ms. A switch's
        // first audio is published at once (AUD-012-D7).
        let firstHandoffAudio = handoffAwaitingFirstAudio && total > 0
        if firstHandoffAudio { handoffAwaitingFirstAudio = false }
        if force || firstHandoffAudio || now - lastPublish >= AudioAnalyzer.publishInterval {
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

    private func resetSession(at now: Double, handoff: Bool = false) {
        sessionStart = now
        log.removeAll(keepingCapacity: true)
        pending.removeAll(keepingCapacity: true)
        lastLevels = .silent
        lastPublish = -.infinity
        normalizer.reset()
        if handoff {
            normalizedOutput.resetForHandoff()   // AUD-012 C1.6
            normalizedOutput.beginFadeIn()
        } else {
            normalizedOutput.reset()
        }
        handoffAwaitingFirstAudio = handoff
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
