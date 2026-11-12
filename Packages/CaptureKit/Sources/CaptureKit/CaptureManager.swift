// CaptureManager.swift — one active source, truthful state (task T029; contracts/audio-source.md).
//
// * Exactly one source is active (FR-001). Switching fully stops the old source first, then the
//   new source is shown with "Waiting" until classified (FR-016).
// * `state` is exactly the classifier's output (Constitution IV); the UI reads nothing else.
// * Operations are serialized, so rapid start/stop/switch sequences (FR-052) end in the state of
//   the last action with no duplicate sessions.
// * Stop, Restart and selecting a source cancel a start that is still in flight (for example
//   waiting on the system picker, which may never answer) instead of queuing behind it (FR-007;
//   owner review 2026-11-08, ADR-0001 ruling 7). They call the source's `stop()`, which the
//   contract allows during `start` (guarantee 3); the start then ends as a cancelled start,
//   "Not started — cancelled", the same result as cancelling the picker itself.
// * Analysis runs on AudioAnalyzer's work queue; this class receives its published updates and
//   applies lifecycle events synchronously.
// * Every start attempt begins from a clean slate (FR-011, FR-013, FR-031): the previous session's
//   state, reason, statistics, levels, verified-audio flag and logs are cleared before the source's
//   `start` (which may show the system picker or a permission prompt), and analyzer updates
//   published before the attempt are ignored.
// * `transitions` is read from the analyzer's ordered per-attempt log after every published update
//   and every lifecycle event, so final transitions (stopped, endedBySystem, a failed start) reach
//   the export even though the analysis timer is already stopped.
// * Session time 0 is when the source's `start` returned (FR-022): the sink and the analyzer are
//   both marked then. Lifecycle and source-event log entries are stamped with the session clock
//   when this class handles them; entries handled while a start is pending are stamped 0.
// * User pause (AUD-006): `pause()` suspends In-App Playback at the user's request (the
//   transport's Pause and Stop playback). It goes through the classifier's `suspended` event, so
//   the state is Paused and "Active audio" must be verified again after `resume()`
//   (Constitution IV). Unlike a lifecycle pause it is never undone by foreground or unlock, nor
//   by the end of an interruption: only `resume()` continues. It never applies to System/App
//   Capture or Microphone.
import AudioCore
import Observation

@MainActor
@Observable
public final class CaptureManager {
    public private(set) var activeMode: AudioSourceMode?
    public private(set) var state: AudioState = .notStarted
    public private(set) var stopReason: StopReason?
    /// Detail of the last stop or failure in this session, e.g. a ScreenCaptureKit error with
    /// "(SCStreamError -3824)". Exported as `session.stopDetail` (owner ruling 2026-11-08) so
    /// RI-003 evidence can tell stop causes apart; nil when the source gave no detail.
    public private(set) var stopDetail: String?
    public private(set) var levels = LevelMeter.Levels.silent
    public private(set) var statistics = PCMSinkStatistics()
    public private(set) var prolongedSilenceHint = false
    public private(set) var hasVerifiedActiveAudio = false
    public private(set) var transitions: [StateTransition] = []
    public private(set) var lifecycleLog: [LifecycleLogEntry] = []
    public private(set) var sessionSeconds: Double = 0
    /// Session summary for the export (FR-021): loudest peak and mean RMS while running.
    public private(set) var sessionPeakMaxDBFS: Float = LevelMeter.floorDBFS
    public private(set) var sessionRMSMeanDBFS: Float = LevelMeter.floorDBFS
    /// Every distinct format seen this session, with when it first appeared (FR-017, FR-020).
    public private(set) var formatsSeen: [FormatObservation] = []
    /// True while a source's `start` is in flight: the system picker or a permission prompt may be
    /// on screen. The UI keeps Stop enabled then, because Stop cancels the start (ADR-0001 ruling 7).
    public private(set) var isStarting = false
    /// True while In-App Playback is paused at the user's request (AUD-006): from `pause()` until
    /// `resume()`, a stop, a failure, the end by the system, or a new attempt.
    public private(set) var isPausedByUser = false

    private let sources: [AudioSourceMode: any AudioSource]
    private let sink = PCMSink()
    let analyzer: AudioAnalyzer
    private let runsAnalysisTimer: Bool
    @ObservationIgnored private var current: (any AudioSource)?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var operationTail: Task<Void, Never>?
    /// The source whose `start` is in flight, so a command can cancel it instead of waiting.
    @ObservationIgnored private var startingSource: (any AudioSource)?
    /// Bumped by every Stop, Restart and select. An attempt remembers the value it was queued
    /// with; if a later command bumped it, the attempt is cancelled, whether it is queued, stopping
    /// the previous source, or waiting inside `start` (ADR-0001 ruling 7).
    @ObservationIgnored private var cancelGeneration = 0
    @ObservationIgnored private var lastSequence: UInt64 = 0
    @ObservationIgnored private var pauseReason: StopReason?
    @ObservationIgnored private var lastFormatChangeCount = 0
    @ObservationIgnored private var rmsSum: Double = 0
    @ObservationIgnored private var rmsCount = 0

    /// - Parameters:
    ///   - sources: one source per mode.
    ///   - runsAnalysisTimer: false in tests, which drive `analyzer.step()` directly.
    ///   - clock: injected for tests.
    ///   - signposts: latency-stage signposts (task T062), e.g. Diagnostics' `PipelineSignposts`.
    public init(sources: [any AudioSource], thresholds: ClassifierThresholds = .default,
                runsAnalysisTimer: Bool = true,
                clock: @escaping @Sendable () -> Double = { MonotonicClock.nowSeconds() },
                signposts: (any AudioPipelineSignposts)? = nil) {
        var map: [AudioSourceMode: any AudioSource] = [:]
        for s in sources { map[s.mode] = s }
        self.sources = map
        self.runsAnalysisTimer = runsAnalysisTimer
        analyzer = AudioAnalyzer(sink: sink, thresholds: thresholds, clock: clock)
        analyzer.setSignposts(signposts)
        analyzer.setUpdateHandler { [weak self] update in
            Task { @MainActor in self?.receive(update) }
        }
    }

    // MARK: - Queries

    public func availability(of mode: AudioSourceMode) -> SourceAvailability {
        sources[mode]?.availability ?? .unavailable(.unsupportedOS)
    }

    /// FR-014: a third-party content name is shown only if the OS identified it and Active audio
    /// was verified for it in this session. Otherwise nil, and the UI shows "System/App Capture".
    /// Normalized audio (Float32 interleaved stereo, 44.1 kHz) for the renderer, filled by the
    /// analysis work queue: source → PCMSink → work queue → Normalizer → normalized ring
    /// (research R-05/R-06). The same reader serves every session; each attempt empties it.
    public nonisolated var normalizedOutput: any NormalizedPCMReader { analyzer.normalizedOutput }

    /// True while `source` is the started source of the current session (AUD-006: the transport
    /// acts only on its own In-App Playback source, never on a source that replaced it).
    public func isCurrent(_ source: any AudioSource) -> Bool {
        current === source
    }

    public var displayedContentIdentity: String? {
        guard activeMode == .systemAppCapture, hasVerifiedActiveAudio,
              let identifying = current as? ContentIdentifying else { return nil }
        return identifying.contentIdentity
    }

    // MARK: - Commands (serialized)

    /// Selects and starts a source, stopping any current source first (FR-016). A start still in
    /// flight is cancelled first, so choosing another source never waits on an open picker.
    public func select(_ mode: AudioSourceMode) async {
        let generation = await cancelPendingStart()
        await serialized { await self.startInner(mode, generation: generation) }
    }

    /// Stops the active source within 1 s (FR-007). Idempotent. A start still in flight (for
    /// example waiting on the system picker) is cancelled and ends as "Not started — cancelled".
    public func stop() async {
        _ = await cancelPendingStart()
        await serialized {
            guard self.current != nil else { return }
            await self.stopCurrent()
            self.apply(.userStopped)
        }
    }

    /// One-tap restart of the last mode (FR-055). For System/App Capture this re-presents the
    /// system picker, because `start` always does (FR-002). A start still in flight is cancelled
    /// first.
    public func restart() async {
        let generation = await cancelPendingStart()
        await serialized {
            guard let mode = self.activeMode else { return }
            await self.stopCurrent()
            await self.startInner(mode, generation: generation)
        }
    }

    /// Resumes a Paused source (e.g. after "Paused — audio route changed"), and ends a user pause.
    public func resume() async {
        await serialized { await self.resumeInner() }
    }

    /// Pauses In-App Playback at the user's request (AUD-006-R20, R21): the source stays started,
    /// the state is Paused with no reason, and only `resume()` continues it. A session that an
    /// interruption, a lost route or the app's lifecycle already paused becomes a user pause.
    /// No effect for System/App Capture and Microphone, or without a session.
    public func pause() async {
        await serialized {
            guard let source = self.current, self.activeMode == .inAppPlayback, !self.isPausedByUser,
                  self.state.isRunning || self.state == .interrupted || self.state == .paused else { return }
            // A source that is already Paused (route lost, lifecycle) was suspended then.
            if self.state != .paused { await source.suspend() }
            self.pauseReason = nil
            self.isPausedByUser = true
            self.apply(.suspended)
        }
    }

    /// App lifecycle per the data-model lifecycle matrix (FR-050, FR-053, FR-054).
    public func handle(_ event: AppLifecycleEvent) async {
        log(event.rawValue)
        await serialized {
            guard let source = self.current, let mode = self.activeMode, mode != .systemAppCapture else {
                // System/App Capture continues while the stream delivers (RI-003); if the OS ends
                // it, the source reports endedBySystem.
                return
            }
            switch event {
            case .background, .lock:
                guard self.state.isRunning || self.state == .interrupted else { return }
                await source.suspend()
                self.pauseReason = nil
                self.apply(.suspended)
            case .foreground, .unlock:
                // A user pause (AUD-006) stays until the user resumes.
                guard self.state == .paused, self.pauseReason == nil, !self.isPausedByUser else { return }
                await self.resumeInner()
            }
        }
    }

    // MARK: - Internals

    private func serialized(_ operation: @escaping @MainActor () async -> Void) async {
        let previous = operationTail
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        operationTail = task
        await task.value
    }

    /// Cancels every earlier attempt (queued or in flight) without waiting for the serialized
    /// queue, and returns this command's generation. A start waiting inside `start` is ended by the
    /// source's `stop()`, which is safe during `start` (contract guarantee 3). The bump happens
    /// before the first await, so the order of commands decides (ADR-0001 ruling 7, FR-052).
    private func cancelPendingStart() async -> Int {
        cancelGeneration += 1
        let generation = cancelGeneration
        if let source = startingSource { await source.stop() }
        return generation
    }

    private func startInner(_ mode: AudioSourceMode, generation: Int) async {
        let cancelled = { generation != self.cancelGeneration }
        await stopCurrent()
        activeMode = mode
        beginAttempt()
        guard let source = sources[mode] else {
            apply(.startFailed(.unsupportedOS))
            return
        }
        if case .unavailable(let reason) = source.availability {
            apply(.startFailed(reason))
            // Tells "blocked before start" apart from a failure inside `start` with the same reason.
            stopDetail = "Not started: the source was unavailable (\(reason.code)) before start"
            return
        }
        // A command after this attempt was queued (for example Stop during Restart's stop of the
        // previous source) cancels it before the picker is ever shown.
        if cancelled() { applyCancelledStart(); return }
        startingSource = source
        isStarting = true
        defer {
            startingSource = nil
            isStarting = false
        }
        do {
            let events = try await source.start(into: sink)
            if cancelled() {
                // A command cancelled this start, but the source started before it saw the cancel.
                // Stop it again; the attempt still ends as cancelled, never as a running session.
                await source.stop()
                applyCancelledStart()
                return
            }
            // Session time 0 is now, when the source has actually started; the picker or
            // permission prompt shown inside `start` does not count (FR-022, Gate 2).
            sink.markSessionStart()
            current = source
            apply(.started)
            listen(to: events, from: source)
            if runsAnalysisTimer { analyzer.startTimer() }
        } catch let error as SourceError {
            if cancelled() { applyCancelledStart(); return }
            apply(.startFailed(error.reason))
            if let detail = error.detail { stopDetail = detail }
        } catch {
            if cancelled() { applyCancelledStart(); return }
            apply(.startFailed(.error(String(describing: error))))
        }
    }

    /// A start cancelled by Stop, Restart or another source ends like a cancelled picker:
    /// "Not started — cancelled" (US1-AS4), with a detail that tells the two apart in the export.
    private func applyCancelledStart() {
        apply(.startFailed(.cancelled))
        stopDetail = "Start cancelled from the app before the source started"
    }

    /// Resets every per-session field for a new start attempt. The source is stopped and the
    /// analysis timer is off, so nothing writes the sink and nothing new is published.
    private func beginAttempt() {
        sink.reset()
        let update = analyzer.beginAttempt()
        // Updates published before this point belong to the previous session; `receive` drops them.
        lastSequence = update.sequence
        pauseReason = nil
        isPausedByUser = false
        state = update.state
        stopReason = nil
        stopDetail = nil
        levels = .silent
        statistics = update.statistics
        prolongedSilenceHint = false
        hasVerifiedActiveAudio = false
        sessionSeconds = 0
        transitions.removeAll()
        lifecycleLog.removeAll()
        formatsSeen.removeAll()
        lastFormatChangeCount = 0
        sessionPeakMaxDBFS = LevelMeter.floorDBFS
        sessionRMSMeanDBFS = LevelMeter.floorDBFS
        rmsSum = 0
        rmsCount = 0
    }

    private func stopCurrent() async {
        // A pause reason describes the running session only; it must not outlive a stop, a
        // failure or an end by the system (FR-015).
        pauseReason = nil
        isPausedByUser = false
        eventTask?.cancel()
        eventTask = nil
        if let source = current {
            current = nil
            await source.stop()
        }
        analyzer.stopTimer()
    }

    private func resumeInner() async {
        guard let source = current, state == .paused || state == .interrupted else { return }
        do {
            try await source.resume()
            pauseReason = nil
            isPausedByUser = false
            apply(state == .interrupted ? .interruptionEnded(shouldResume: true) : .resumed)
        } catch let error as SourceError {
            await stopCurrent()
            apply(.failed(error.reason))
            if let detail = error.detail { stopDetail = detail }
        } catch {
            await stopCurrent()
            apply(.failed(.error(String(describing: error))))
        }
    }

    private func listen(to events: AsyncStream<SourceEvent>, from source: any AudioSource) {
        eventTask = Task { @MainActor [weak self] in
            for await event in events {
                guard !Task.isCancelled else { return }
                await self?.handleSourceEvent(event, from: source)
            }
        }
    }

    private func handleSourceEvent(_ event: SourceEvent, from source: any AudioSource) async {
        switch event {
        case .interruptionBegan: log("interruptionBegan")
        case .interruptionEnded: log("interruptionEnded")
        case .outputRouteLost: log("routeChange")
        case .endedBySystem: log("streamStopped")
        case .formatChanged: log("formatChange")
        case .failed: break
        }
        await serialized {
            guard self.current === source, let mode = self.activeMode else { return }
            switch event {
            case .interruptionBegan:
                // FR-051: for System/App Capture an interruption alone changes nothing.
                if mode != .systemAppCapture { self.apply(.interruptionBegan) }
            case .interruptionEnded(let shouldResume):
                guard mode != .systemAppCapture, self.state == .interrupted else { return }
                if shouldResume { await self.resumeInner() }
            case .outputRouteLost:
                guard self.state.isRunning else { return }
                self.pauseReason = .audioRouteChanged
                self.apply(.suspended)
            case .failed(let reason):
                await self.stopCurrent()
                self.apply(.failed(reason))
            case .endedBySystem(let detail):
                await self.stopCurrent()
                self.stopDetail = detail
                self.apply(.endedBySystem)
            case .formatChanged:
                break
            }
        }
    }

    private func apply(_ event: LifecycleEvent) {
        switch event {
        case .failed(.error(let detail)), .startFailed(.error(let detail)): stopDetail = detail
        default: break
        }
        let update = analyzer.apply(event)
        lastSequence = max(lastSequence, update.sequence)
        syncTransitions()
        state = update.state
        stopReason = displayedReason(update.reason)
        hasVerifiedActiveAudio = update.hasVerifiedActiveAudio
        prolongedSilenceHint = update.prolongedSilenceHint
        statistics = update.statistics
        // A failed start has no session, so its duration stays 0.
        if case .startFailed = event { return }
        sessionSeconds = update.sessionSeconds
    }

    /// The reason shown with the state. A user pause shows none (AUD-006-R20): the reason of an
    /// interruption or a route loss that the pause replaced no longer applies.
    private func displayedReason(_ classified: StopReason?) -> StopReason? {
        isPausedByUser ? nil : (pauseReason ?? classified)
    }

    /// Appends the analyzer's transitions not yet copied. The analyzer's log and `transitions` are
    /// both emptied in `beginAttempt`, so the copy is always in order and never duplicates.
    private func syncTransitions() {
        let new = analyzer.transitions(from: transitions.count)
        if !new.isEmpty { transitions.append(contentsOf: new) }
    }

    private func receive(_ update: AnalyzerUpdate) {
        // Each update is applied at most once, and never after a newer synchronous result. This
        // also drops every update published before the current attempt began.
        guard update.sequence > lastSequence else { return }
        lastSequence = update.sequence
        syncTransitions()
        state = update.state
        stopReason = displayedReason(update.reason)
        levels = update.levels
        statistics = update.statistics
        prolongedSilenceHint = update.prolongedSilenceHint
        hasVerifiedActiveAudio = update.hasVerifiedActiveAudio
        sessionSeconds = update.sessionSeconds
        if let reason = update.conversionFailure, update.state.isRunning, let source = current {
            // FR-017: an unconvertible format stops the source with an error, like a source failure.
            Task { await self.failForConversion(reason, source: source) }
        }
        if update.statistics.formatChangeCount > lastFormatChangeCount {
            lastFormatChangeCount = update.statistics.formatChangeCount
            log("formatChange")
        }
        if let format = update.statistics.format, formatsSeen.last?.format != format, formatsSeen.count < 100 {
            formatsSeen.append(FormatObservation(format: format, firstSeenSeconds: update.sessionSeconds))
        }
        if update.state.isRunning, update.statistics.sampleCount > 0 {
            sessionPeakMaxDBFS = max(sessionPeakMaxDBFS, update.levels.peakDBFS)
            rmsSum += Double(update.levels.rmsDBFS)
            rmsCount += 1
            sessionRMSMeanDBFS = Float(rmsSum / Double(rmsCount))
        }
    }

    /// Stamped with the session clock now, when the event is handled; not the last published
    /// time, which lags by up to 250 ms and stops advancing when the session ends.
    private func log(_ event: String) {
        guard lifecycleLog.count < 1000 else { return }
        lifecycleLog.append(LifecycleLogEntry(atSeconds: analyzer.currentSessionSeconds(), event: event))
    }

    // MARK: - Testing

    /// Drives one analysis pass and applies it immediately (tests only). `step` also publishes
    /// the same update asynchronously; `receive` then drops it as already applied.
    private func failForConversion(_ reason: StopReason, source: any AudioSource) async {
        await serialized {
            guard self.current === source, self.state.isRunning else { return }
            // The export records it as the failure reason and stop detail (no schema event exists).
            await self.stopCurrent()
            self.apply(.failed(reason))
        }
    }

    func stepAnalysisForTesting() {
        receive(analyzer.step())
    }

    /// Delivers an update as the analyzer's update handler would (tests only), e.g. a stale one.
    func receiveForTesting(_ update: AnalyzerUpdate) {
        receive(update)
    }

    /// The sink, for test sources (tests only).
    var sinkForTesting: PCMSink { sink }
}
