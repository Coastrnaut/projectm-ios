// AudioStateClassifier.swift — deterministic audio-state machine (task T026; research R-07;
// contracts/audio-source.md; data-model.md §Transitions).
//
// Pure value type: given the same timeline of inputs it produces the same states. Times are
// seconds on any monotonic clock supplied by the caller (tests inject their own).
//
// Rules (initial thresholds; ClassifierThresholds):
//   started                                    → waiting
//   running, no audio data for 5 s             → noAudioReceived   (FR-012; also applies when
//                                                data stops arriving mid-session — a source that
//                                                stops delivering is never left showing Active)
//   waiting|noAudioReceived|silent, peak ≥ −50 dBFS sustained ≥ 250 ms → active   (FR-011)
//   waiting|noAudioReceived, data below the active threshold          → silent
//   active, peak < −60 dBFS sustained ≥ 2 s    → silent             (FR-011 hysteresis)
//   silent for 60 s                            → prolongedSilenceHint = true, no state change (FR-018)
//   suspended → paused; resumed → waiting; interruptionBegan → interrupted;
//   interruptionEnded(shouldResume: true) → waiting; userStopped → stopped;
//   failed(reason) → stopped; endedBySystem → endedBySystem; startFailed → notStarted.
// Format changes are not state inputs (FR-017).

public struct AudioStateClassifier: Sendable {
    public private(set) var state: AudioState = .notStarted
    public private(set) var prolongedSilenceHint = false
    public private(set) var lastReason: StopReason?
    /// True once Active audio has been verified in the current session (FR-014).
    public private(set) var hasVerifiedActiveAudio = false

    public let thresholds: ClassifierThresholds

    private var sessionStart: Double?
    private var lastDataAt: Double?
    private var aboveSince: Double?
    private var belowSince: Double?
    private var silentSince: Double?

    public init(thresholds: ClassifierThresholds = .default) {
        self.thresholds = thresholds
    }

    /// Feed one analyzed chunk: `peakDBFS` over audio covering `duration` seconds that ended at `t`.
    @discardableResult
    public mutating func dataArrived(at t: Double, peakDBFS: Float, duration: Double) -> AudioState {
        guard state.isRunning, duration > 0 else { return state }
        lastDataAt = t
        let chunkStart = t - duration

        if peakDBFS >= thresholds.activePeakDBFS {
            belowSince = nil
            if aboveSince == nil { aboveSince = chunkStart }
            if let since = aboveSince, t - since >= thresholds.activeMinDuration - 1e-9 {
                transition(to: .active, at: t)
                hasVerifiedActiveAudio = true
            }
        } else if peakDBFS < thresholds.silentPeakDBFS {
            aboveSince = nil
            switch state {
            case .active:
                if belowSince == nil { belowSince = chunkStart }
                if let since = belowSince, t - since >= thresholds.silentMinDuration - 1e-9 {
                    transition(to: .silent, at: t)
                }
            case .waiting, .noAudioReceived:
                transition(to: .silent, at: t)
            default:
                break
            }
        } else {
            // Between the silence and active thresholds: hysteresis band.
            aboveSince = nil
            belowSince = nil
            if state == .waiting || state == .noAudioReceived {
                transition(to: .silent, at: t)
            }
        }
        updateHint(at: t)
        return state
    }

    /// Advance time with no new audio data (timeouts).
    @discardableResult
    public mutating func tick(at t: Double) -> AudioState {
        guard state.isRunning else { return state }
        if let reference = lastDataAt ?? sessionStart,
           t - reference >= thresholds.noAudioTimeout - 1e-9,
           state != .noAudioReceived {
            aboveSince = nil
            belowSince = nil
            transition(to: .noAudioReceived, at: t)
        }
        updateHint(at: t)
        return state
    }

    @discardableResult
    public mutating func lifecycle(_ event: LifecycleEvent, at t: Double) -> AudioState {
        switch event {
        case .started:
            resetSession(at: t)
            hasVerifiedActiveAudio = false
            lastReason = nil
            transition(to: .waiting, at: t)
        case .startFailed(let reason):
            lastReason = reason
            transition(to: .notStarted, at: t)
        case .userStopped:
            lastReason = nil
            transition(to: .stopped, at: t)
        case .failed(let reason):
            lastReason = reason
            transition(to: .stopped, at: t)
        case .suspended:
            if state.isRunning || state == .interrupted {
                transition(to: .paused, at: t)
            }
        case .resumed:
            if state == .paused {
                resetSession(at: t)
                lastReason = nil
                transition(to: .waiting, at: t)
            }
        case .interruptionBegan:
            if state.isRunning {
                lastReason = .interrupted
                transition(to: .interrupted, at: t)
            }
        case .interruptionEnded(let shouldResume):
            if state == .interrupted && shouldResume {
                resetSession(at: t)
                lastReason = nil
                transition(to: .waiting, at: t)
            }
        case .endedBySystem:
            lastReason = .endedBySystem
            transition(to: .endedBySystem, at: t)
        }
        return state
    }

    // MARK: - Private

    private mutating func resetSession(at t: Double) {
        sessionStart = t
        lastDataAt = nil
        aboveSince = nil
        belowSince = nil
        silentSince = nil
        prolongedSilenceHint = false
    }

    private mutating func transition(to newState: AudioState, at t: Double) {
        guard newState != state else { return }
        state = newState
        if newState == .silent {
            silentSince = t
        } else {
            silentSince = nil
            prolongedSilenceHint = false
        }
    }

    private mutating func updateHint(at t: Double) {
        if state == .silent, let since = silentSince {
            prolongedSilenceHint = t - since >= thresholds.prolongedSilenceHint - 1e-9
        } else {
            prolongedSilenceHint = false
        }
    }
}
