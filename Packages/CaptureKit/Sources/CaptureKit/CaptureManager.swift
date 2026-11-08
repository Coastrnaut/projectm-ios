// CaptureManager.swift — one active source, truthful state (task T029; contracts/audio-source.md).
//
// * Exactly one source is active (FR-001). Switching fully stops the old source first, then the
//   new source is shown with "Waiting" until classified (FR-016).
// * `state` is exactly the classifier's output (Constitution IV); the UI reads nothing else.
// * Operations are serialized, so rapid start/stop/switch sequences (FR-052) end in the state of
//   the last action with no duplicate sessions.
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
import AudioCore
import Observation

@MainActor
@Observable
public final class CaptureManager {
    public private(set) var activeMode: AudioSourceMode?
    public private(set) var state: AudioState = .notStarted
    public private(set) var stopReason: StopReason?
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

    private let sources: [AudioSourceMode: any AudioSource]
    private let sink = PCMSink()
    let analyzer: AudioAnalyzer
    private let runsAnalysisTimer: Bool
    @ObservationIgnored private var current: (any AudioSource)?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var operationTail: Task<Void, Never>?
    @ObservationIgnored private var lastSequence: UInt64 = 0
    @ObservationIgnored private var pauseReason: StopReason?
    @ObservationIgnored private var lastFormatChangeCount = 0
    @ObservationIgnored private var rmsSum: Double = 0
    @ObservationIgnored private var rmsCount = 0

    /// - Parameters:
    ///   - sources: one source per mode.
    ///   - runsAnalysisTimer: false in tests, which drive `analyzer.step()` directly.
    ///   - clock: injected for tests.
    public init(sources: [any AudioSource], thresholds: ClassifierThresholds = .default,
                runsAnalysisTimer: Bool = true,
                clock: @escaping @Sendable () -> Double = { MonotonicClock.nowSeconds() }) {
        var map: [AudioSourceMode: any AudioSource] = [:]
        for s in sources { map[s.mode] = s }
        self.sources = map
        self.runsAnalysisTimer = runsAnalysisTimer
        analyzer = AudioAnalyzer(sink: sink, thresholds: thresholds, clock: clock)
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
    public var displayedContentIdentity: String? {
        guard activeMode == .systemAppCapture, hasVerifiedActiveAudio,
              let identifying = current as? ContentIdentifying else { return nil }
        return identifying.contentIdentity
    }

    // MARK: - Commands (serialized)

    /// Selects and starts a source, stopping any current source first (FR-016).
    public func select(_ mode: AudioSourceMode) async {
        await serialized { await self.startInner(mode) }
    }

    /// Stops the active source within 1 s (FR-007). Idempotent.
    public func stop() async {
        await serialized {
            guard self.current != nil else { return }
            await self.stopCurrent()
            self.apply(.userStopped)
        }
    }

    /// One-tap restart of the last mode (FR-055). For System/App Capture this re-presents the
    /// system picker, because `start` always does (FR-002).
    public func restart() async {
        await serialized {
            guard let mode = self.activeMode else { return }
            await self.stopCurrent()
            await self.startInner(mode)
        }
    }

    /// Resumes a Paused source (e.g. after "Paused — audio route changed").
    public func resume() async {
        await serialized { await self.resumeInner() }
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

    private func startInner(_ mode: AudioSourceMode) async {
        await stopCurrent()
        activeMode = mode
        beginAttempt()
        guard let source = sources[mode] else {
            apply(.startFailed(.unsupportedOS))
            return
        }
        if case .unavailable(let reason) = source.availability {
            apply(.startFailed(reason))
            return
        }
        do {
            let events = try await source.start(into: sink)
            // Session time 0 is now, when the source has actually started; the picker or
            // permission prompt shown inside `start` does not count (FR-022, Gate 2).
            sink.markSessionStart()
            current = source
            apply(.started)
            listen(to: events, from: source)
            if runsAnalysisTimer { analyzer.startTimer() }
        } catch let error as SourceError {
            apply(.startFailed(error.reason))
        } catch {
            apply(.startFailed(.error(String(describing: error))))
        }
    }

    /// Resets every per-session field for a new start attempt. The source is stopped and the
    /// analysis timer is off, so nothing writes the sink and nothing new is published.
    private func beginAttempt() {
        sink.reset()
        let update = analyzer.beginAttempt()
        // Updates published before this point belong to the previous session; `receive` drops them.
        lastSequence = update.sequence
        pauseReason = nil
        state = update.state
        stopReason = nil
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
            apply(state == .interrupted ? .interruptionEnded(shouldResume: true) : .resumed)
        } catch let error as SourceError {
            await stopCurrent()
            apply(.failed(error.reason))
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
            case .endedBySystem:
                await self.stopCurrent()
                self.apply(.endedBySystem)
            case .formatChanged:
                break
            }
        }
    }

    private func apply(_ event: LifecycleEvent) {
        let update = analyzer.apply(event)
        lastSequence = max(lastSequence, update.sequence)
        syncTransitions()
        state = update.state
        stopReason = pauseReason ?? update.reason
        hasVerifiedActiveAudio = update.hasVerifiedActiveAudio
        prolongedSilenceHint = update.prolongedSilenceHint
        statistics = update.statistics
        // A failed start has no session, so its duration stays 0.
        if case .startFailed = event { return }
        sessionSeconds = update.sessionSeconds
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
        stopReason = pauseReason ?? update.reason
        levels = update.levels
        statistics = update.statistics
        prolongedSilenceHint = update.prolongedSilenceHint
        hasVerifiedActiveAudio = update.hasVerifiedActiveAudio
        sessionSeconds = update.sessionSeconds
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
