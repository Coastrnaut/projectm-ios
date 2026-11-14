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
// * Interruptions of In-App Playback (AUD-014): from "interruption began" until playback resumes
//   or the session ends, the manager remembers the open interruption: whether playback was
//   eligible to resume (it was playing, or only held by the app lifecycle), what iOS has indicated
//   so far, whether the user changed the transport, and whether the output was lost. At
//   "interruption ended" and at every return to the foreground or unlock it asks
//   `InterruptionPolicy` and resumes only on `.resume`. So: no resume after a user pause, Stop
//   playback, seek or track change during the interruption; none after a lost output; none on a
//   return to the foreground while the interruption is open or ended without a resume indication
//   (the Paused state then keeps the "Interrupted" reason, FR-015); a resume indicated while the
//   app was in the background happens on the return. A Play that iOS refuses while the
//   interruption is open leaves the session as it was. States, reasons and log names are those of
//   feature 001 (FR-051). Microphone and System/App Capture take the paths they always took.
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
    /// AUD-012: the target of a source switch while the label must read "Switching source…" (C3).
    public private(set) var switchingTo: AudioSourceMode?
    /// AUD-012-R9: samples the renderer boundary replaced (non-finite or out of range) since launch.
    public private(set) var sanitizedSampleCount = 0
    /// AUD-012: how long a switch's fade-out may wait for the old source's audio.
    @ObservationIgnored public var handoffTiming: HandoffTiming = .default
    /// AUD-012-R12: called on the main actor when an attempt sets `activeMode` (AUD-011's flag).
    @ObservationIgnored public var onSessionMode: ((AudioSourceMode) -> Void)?

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
    /// The open interruption of In-App Playback (AUD-014); nil when there is none.
    @ObservationIgnored private var interruption: OpenInterruption?
    /// False between background or lock and the next foreground or unlock.
    @ObservationIgnored private var isPresentable = true
    /// The user pause is the transport's Stop playback (AUD-014: the policy's "stopped").
    @ObservationIgnored private var userPauseIsStop = false
    /// AUD-012: the cancel generation of the latest attempt, and whether that attempt came from a
    /// switch whose label still waits for its first audio.
    @ObservationIgnored private var attemptGeneration = 0
    @ObservationIgnored private var awaitingSwitchAudio = false

    /// What is remembered about an interruption of In-App Playback (data-model.md).
    private struct OpenInterruption {
        /// Playback was playing, or only held by the app lifecycle, when the interruption began.
        var eligible: Bool
        var signal: InterruptionPolicy.SystemSignal = .pending
        /// Pause, Stop playback, seek, next or previous since it began.
        var userChangedTransport = false
        /// The output route was lost since it began.
        var outputLost = false
    }
    @ObservationIgnored private var lastFormatChangeCount = 0
    @ObservationIgnored private var rmsSum: Double = 0
    @ObservationIgnored private var rmsCount = 0

    /// - Parameters:
    ///   - sources: one source per mode.
    ///   - runsAnalysisTimer: false in tests, which drive `analyzer.step()` directly.
    ///   - clock: injected for tests.
    ///   - signposts: latency-stage signposts (task T062), e.g. Diagnostics' `PipelineSignposts`.
    ///   - analysisTapCapacityFrames: > 0 adds an analysis tap of that many stereo frames to the
    ///     normalized output, read through `analysisTap` by native visuals (VIS-001-R14); 0, the
    ///     default, means no tap.
    public init(sources: [any AudioSource], thresholds: ClassifierThresholds = .default,
                runsAnalysisTimer: Bool = true,
                clock: @escaping @Sendable () -> Double = { MonotonicClock.nowSeconds() },
                signposts: (any AudioPipelineSignposts)? = nil,
                analysisTapCapacityFrames: Int = 0) {
        var map: [AudioSourceMode: any AudioSource] = [:]
        for s in sources { map[s.mode] = s }
        self.sources = map
        self.runsAnalysisTimer = runsAnalysisTimer
        analyzer = AudioAnalyzer(sink: sink, thresholds: thresholds, clock: clock, analysisTapCapacityFrames: analysisTapCapacityFrames)
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

    /// The normalized output's analysis tap (ANL-001-R9): the same audio, every frame in order, for
    /// one analysis consumer such as a native visual's band feed (VIS-001-R14). Nil unless `init`
    /// got a positive `analysisTapCapacityFrames`. Never handed to projectM (ADR-0008 decision 5).
    public nonisolated var analysisTap: (any NormalizedPCMReader)? { analyzer.normalizedOutput.analysisTap }

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
        switchingTo = nil   // AUD-012-R15: not a switch
        let generation = await cancelPendingStart()
        await serialized { await self.startInner(mode, generation: generation) }
    }

    /// Stops the active source within 1 s (FR-007). Idempotent. A start still in flight (for
    /// example waiting on the system picker) is cancelled and ends as "Not started — cancelled".
    public func stop() async {
        switchingTo = nil   // AUD-012-R11: the target is never shown
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
        switchingTo = nil   // AUD-012-R15
        let generation = await cancelPendingStart()
        await serialized {
            guard let mode = self.activeMode else { return }
            await self.stopCurrent()
            await self.startInner(mode, generation: generation)
        }
    }

    /// AUD-012 (contract C2): switches to `mode` with a bounded handoff, keeping the visualization.
    /// No effect when `mode` is already the running (or starting) source or the switch's target.
    public func switchSource(to mode: AudioSourceMode) async {
        if switchingTo == mode { return }
        if switchingTo == nil, mode == activeMode, current != nil || isStarting { return }
        switchingTo = mode   // C3: the old label is gone from the request on
        let generation = await cancelPendingStart()
        await serialized { await self.switchInner(mode, generation: generation) }
    }

    /// Resumes a Paused source (e.g. after "Paused — audio route changed"), and ends a user pause.
    public func resume() async {
        await serialized { await self.resumeInner() }
    }

    /// Pauses In-App Playback at the user's request (AUD-006-R20, R21): the source stays started,
    /// the state is Paused with no reason, and only `resume()` continues it. A session that an
    /// interruption, a lost route or the app's lifecycle already paused becomes a user pause.
    /// No effect for System/App Capture and Microphone, or without a session.
    ///
    /// `asStop`: the pause is the transport's Stop playback (AUD-014: an interruption then leaves
    /// playback stopped, not paused). A pause during an open interruption cancels its resume.
    public func pause(asStop: Bool = false) async {
        await serialized {
            guard let source = self.current, self.activeMode == .inAppPlayback,
                  self.state.isRunning || self.state == .interrupted || self.state == .paused else { return }
            self.interruption?.userChangedTransport = true
            if self.isPausedByUser {
                if asStop { self.userPauseIsStop = true }
                return
            }
            // A source that is already Paused (route lost, lifecycle) was suspended then.
            if self.state != .paused { await source.suspend() }
            self.pauseReason = nil
            self.isPausedByUser = true
            self.userPauseIsStop = asStop
            self.apply(.suspended)
        }
    }

    /// The user moved In-App Playback's transport without pausing: a seek, or another track
    /// (AUD-014-R2). During an open interruption this cancels the automatic resume; stopped
    /// playback becomes paused at the new place.
    public func noteUserTransportChange() {
        guard activeMode == .inAppPlayback, current != nil else { return }
        interruption?.userChangedTransport = true
        userPauseIsStop = false
    }

    /// App lifecycle per the data-model lifecycle matrix (FR-050, FR-053, FR-054).
    public func handle(_ event: AppLifecycleEvent) async {
        log(event.rawValue)
        await serialized {
            switch event {
            case .background, .lock: self.isPresentable = false
            case .foreground, .unlock: self.isPresentable = true
            }
            guard let source = self.current, let mode = self.activeMode, mode != .systemAppCapture else {
                // System/App Capture continues while the stream delivers (RI-003); if the OS ends
                // it, the source reports endedBySystem.
                return
            }
            switch event {
            case .background, .lock:
                guard self.state.isRunning || self.state == .interrupted else { return }
                await source.suspend()
                // AUD-014: an open interruption of In-App Playback stays visible as the reason.
                self.pauseReason = self.interruption.map { $0.outputLost ? .audioRouteChanged : .interrupted }
                self.apply(.suspended)
            case .foreground, .unlock:
                // A user pause (AUD-006) stays until the user resumes.
                guard !self.isPausedByUser else { return }
                if self.interruption != nil {
                    // AUD-014-R5, R6: only the policy resumes after an interruption.
                    await self.applyInterruptionPolicy()
                    return
                }
                guard self.state == .paused, self.pauseReason == nil else { return }
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

    /// The serialized part of a switch: fade-out, then a handoff attempt (C2.3).
    private func switchInner(_ mode: AudioSourceMode, generation: Int) async {
        let cancelled = { generation != self.cancelGeneration }
        if cancelled() { return }   // superseded before it began; the newer command owns the label
        let fades = current != nil
        if fades {
            analyzer.beginHandoffFadeOut()
            // A source that is not delivering (paused, interrupted) cannot fade with audio.
            if state.isRunning { await waitForFadeOut(cancelled: cancelled) }
            analyzer.completeHandoffFadeOut()
        }
        if cancelled() { return }
        // A switch that superseded another one mid-way continues its ramp (no jump to unity).
        let handoff = fades || analyzer.handoffInProgress
        await startInner(mode, generation: generation, handoff: handoff, switching: true)
    }

    /// Polls until the fade-out reached silence, a newer command arrived, or the wait limit passed.
    private func waitForFadeOut(cancelled: () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: handoffTiming.fadeOutWaitLimit)
        while !analyzer.handoffFadeOutDone, !cancelled(), clock.now < deadline {
            try? await Task.sleep(for: handoffTiming.pollInterval)
        }
    }

    private func startInner(_ mode: AudioSourceMode, generation: Int, handoff: Bool = false,
                            switching: Bool = false) async {
        let cancelled = { generation != self.cancelGeneration }
        await stopCurrent()
        activeMode = mode
        attemptGeneration = generation
        awaitingSwitchAudio = switching
        onSessionMode?(mode)
        beginAttempt(handoff: handoff)
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
    private func beginAttempt(handoff: Bool = false) {
        sink.reset()
        let update = analyzer.beginAttempt(handoff: handoff)
        // Updates published before this point belong to the previous session; `receive` drops them.
        lastSequence = update.sequence
        pauseReason = nil
        isPausedByUser = false
        userPauseIsStop = false
        interruption = nil
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
        userPauseIsStop = false
        interruption = nil
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
            userPauseIsStop = false
            interruption = nil
            apply(state == .interrupted ? .interruptionEnded(shouldResume: true) : .resumed)
        } catch let error as SourceError {
            // AUD-014-R8: while the interruption is still open iOS may refuse to give the audio
            // back (a call is going on). The session stays as it was: track, position, state.
            if interruption?.signal == .pending { return }
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
                guard mode != .systemAppCapture else { return }
                if mode == .inAppPlayback { self.openInterruption() }
                self.apply(.interruptionBegan)
            case .interruptionEnded(let shouldResume):
                if mode == .inAppPlayback {
                    // AUD-014-R4: an end without an open interruption changes nothing.
                    guard self.interruption?.signal == .pending else { return }
                    self.interruption?.signal = shouldResume ? .endedShouldResume : .endedWithoutResume
                    await self.applyInterruptionPolicy()
                    return
                }
                guard mode != .systemAppCapture, self.state == .interrupted else { return }
                if shouldResume { await self.resumeInner() }
            case .outputRouteLost:
                if self.state.isRunning {
                    self.pauseReason = .audioRouteChanged
                    self.apply(.suspended)
                } else if mode == .inAppPlayback, !self.isPausedByUser {
                    // AUD-014-R14: lost during an interruption or while the lifecycle holds playback.
                    // Nothing resumes by itself afterwards; a Paused state shows the reason now.
                    self.interruption?.outputLost = true
                    if self.state == .paused {
                        self.pauseReason = .audioRouteChanged
                        self.apply(.suspended)
                    }
                }
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

    // MARK: - Interruptions of In-App Playback (AUD-014)

    /// "Interruption began" for In-App Playback: opens the record, or keeps the open one.
    private func openInterruption() {
        if var open = interruption {
            // A second "began" while it is open changes nothing. After an end, playback is on hold:
            // a new interruption can resume it only if the last one was told to resume and that
            // resume is still waiting for the foreground (AUD-014-R4).
            guard open.signal != .pending else { return }
            open.eligible = open.eligible && open.signal == .endedShouldResume
            open.signal = .pending
            interruption = open
            return
        }
        // Held only by the lifecycle (background, lock) counts as playing: it would resume on return.
        let heldByLifecycle = state == .paused && !isPausedByUser && pauseReason == nil
        interruption = OpenInterruption(eligible: state.isRunning || heldByLifecycle,
                                        outputLost: pauseReason == .audioRouteChanged)
        if heldByLifecycle {
            pauseReason = .interrupted
            apply(.suspended)                         // no state change; shows the reason
        }
    }

    /// Asks the policy what the open interruption allows now, and does it.
    private func applyInterruptionPolicy() async {
        guard let open = interruption, current != nil, state == .interrupted || state == .paused else { return }
        let before: InterruptionPolicy.Transport =
            open.eligible ? .playing : (isPausedByUser && userPauseIsStop ? .stopped : .paused)
        let pausedBy: InterruptionPolicy.PausedBy =
            isPausedByUser ? .user : (open.outputLost || pauseReason == .audioRouteChanged ? .system : .nobody)
        let decision = InterruptionPolicy.decide(InterruptionPolicy.Input(
            source: .inAppPlayback, before: before, pausedBy: pausedBy, signal: open.signal,
            isPresentable: isPresentable, userChangedTransport: open.userChangedTransport, sourceIsUsable: true))
        switch decision {
        case .resume:
            await resumeInner()
        case .stayPaused(.outputDisconnected):
            // The source paused itself when the route was lost: "Paused — audio route changed".
            pauseReason = .audioRouteChanged
            apply(.suspended)
        case .stayPaused, .stayStopped, .fail, .notApplicable:
            break                                     // on hold: Interrupted (FR-051), or the user's pause
        }
    }

    private func apply(_ event: LifecycleEvent) {
        switch event {
        case .failed(.error(let detail)), .startFailed(.error(let detail)): stopDetail = detail
        default: break
        }
        let update = analyzer.apply(event)
        lastSequence = max(lastSequence, update.sequence)
        sanitizedSampleCount = analyzer.normalizedOutput.sanitizedSampleCount
        switch event {
        case .startFailed, .failed, .endedBySystem, .userStopped:
            endSwitchLabelIfCurrent()   // C3: the attempt ended
        default:
            break
        }
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

    /// Clears the switching label, unless a newer command is pending (it owns the label then).
    private func endSwitchLabelIfCurrent() {
        guard awaitingSwitchAudio, attemptGeneration == cancelGeneration else { return }
        awaitingSwitchAudio = false
        switchingTo = nil
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
        sanitizedSampleCount = analyzer.normalizedOutput.sanitizedSampleCount
        // C3: the new source's first audio, or a decided state, ends "Switching source…".
        if awaitingSwitchAudio, current != nil, update.state.isRunning,
           update.statistics.sampleCount > 0 || update.state != .waiting {
            endSwitchLabelIfCurrent()
        }
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

    /// Analyzer access for handoff tests (tests only).
    var analyzerForTesting: AudioAnalyzer { analyzer }

    /// The sink, for test sources (tests only).
    var sinkForTesting: PCMSink { sink }
}

/// AUD-012: how long a switch's fade-out may wait for the old source's audio (research AUD-012-D5).
public struct HandoffTiming: Sendable, Equatable {
    public var fadeOutWaitLimit: Duration
    public var pollInterval: Duration

    public init(fadeOutWaitLimit: Duration, pollInterval: Duration) {
        self.fadeOutWaitLimit = fadeOutWaitLimit
        self.pollInterval = pollInterval
    }

    /// 150 ms, polled every 5 ms (the 100 ms ramp plus delivery jitter).
    public static let `default` = HandoffTiming(fadeOutWaitLimit: .milliseconds(150), pollInterval: .milliseconds(5))
    /// No wait: the fade-out is completed from the last sample at once (deterministic tests).
    public static let immediate = HandoffTiming(fadeOutWaitLimit: .zero, pollInterval: .milliseconds(1))
}
