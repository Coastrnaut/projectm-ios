// CaptureManager.swift — one active source, truthful state (task T029; contracts/audio-source.md).
//
// * Exactly one source is active (FR-001). Switching fully stops the old source first, then the
//   new source is shown with "Waiting" until classified (FR-016).
// * `state` is exactly the classifier's output (Constitution IV); the UI reads nothing else.
// * Operations are serialized, so rapid start/stop/switch sequences (FR-052) end in the state of
//   the last action with no duplicate sessions.
// * Analysis runs on AudioAnalyzer's work queue; this class only receives published updates.
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
        pauseReason = nil
        guard let source = sources[mode] else {
            apply(.startFailed(.unsupportedOS))
            return
        }
        if case .unavailable(let reason) = source.availability {
            apply(.startFailed(reason))
            return
        }
        sink.reset()
        lastFormatChangeCount = 0
        transitions.removeAll()
        lifecycleLog.removeAll()
        do {
            let events = try await source.start(into: sink)
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

    private func stopCurrent() async {
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
        state = update.state
        stopReason = pauseReason ?? update.reason
        hasVerifiedActiveAudio = update.hasVerifiedActiveAudio
        prolongedSilenceHint = update.prolongedSilenceHint
    }

    private func receive(_ update: AnalyzerUpdate) {
        // Transitions are delivered exactly once, by published updates.
        transitions.append(contentsOf: update.newTransitions)
        guard update.sequence >= lastSequence else { return }
        lastSequence = update.sequence
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
    }

    private func log(_ event: String) {
        guard lifecycleLog.count < 1000 else { return }
        lifecycleLog.append(LifecycleLogEntry(atSeconds: sessionSeconds, event: event))
    }

    // MARK: - Testing

    /// Drives one analysis pass and applies it immediately (tests only).
    func stepAnalysisForTesting() {
        let update = analyzer.step()
        // `step` also publishes asynchronously; apply synchronously here so tests are deterministic.
        guard update.sequence >= lastSequence else { return }
        lastSequence = update.sequence
        state = update.state
        stopReason = pauseReason ?? update.reason
        levels = update.levels
        statistics = update.statistics
        hasVerifiedActiveAudio = update.hasVerifiedActiveAudio
        prolongedSilenceHint = update.prolongedSilenceHint
    }

    /// The sink, for test sources (tests only).
    var sinkForTesting: PCMSink { sink }
}
