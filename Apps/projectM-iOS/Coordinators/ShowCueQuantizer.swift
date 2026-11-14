// ShowCueQuantizer.swift — SHOW-003: cue steps held until the next beat or bar in the app
// (specs/214-show-003-beat-quantized-cues; R1 to R9; research SHOW-003-D2, D5, D6, D8; contract Q2).
//
// * Owns PerformanceControl's `QuantizedCueStep` and the mode (`settings.show.quantizeCues`, absent = Off). Owned by
//   `AppSettings` (like MOD-017's `ParameterQuantizer`), so the Settings erase and the UI-test reset reach it.
// * `ShowCoordinator.next/previous/go(to:)` ask `intercept` first: Off, or a step that would not move, goes on at
//   once; otherwise the request is queued (or replaces / cancels the waiting one) and nothing moves now.
// * The beat grid is SHOW-011's tempo snapshot and the clock the monotonic analysis clock, both injected (`connect`),
//   so tests drive `tick(at:)` with synthetic times and turn the wake-ups off.
// * One wake-up task sleeps until the deadline while a step waits (D5); none otherwise. At the deadline `willStep`
//   runs first (MOD-017's own tick, D6), then `perform` runs the step through the show's unchanged step path.
// * Announcements go to the `.cue` lane (ACC-004) through `announce`.
import AudioCore
import Foundation
import Observation
import PerformanceControl

@MainActor
@Observable
final class ShowCueQuantizer {
    static let key = "settings.show.quantizeCues"
    static let cancelledAnnouncement = "Queued cue cancelled"
    static let noTempoAnnouncement = "Cue changed now, no tempo"
    /// The modes offered (MOD-017's Cue has no meaning for a cue step).
    static let modes: [QuantizeMode] = [.off, .beat, .bar]

    private(set) var step = QuantizedCueStep()
    /// Steps applied at a boundary (tests and DEBUG probes).
    private(set) var appliedAtBoundary = 0

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var clock: () -> UInt64 = { () -> UInt64 in MonotonicClock.nowNanoseconds() }
    @ObservationIgnored var tempo: () -> TempoSnapshot = { () -> TempoSnapshot in .none }
    @ObservationIgnored var announce: (String) -> Void = { (_: String) -> Void in }
    /// Runs before a queued step applies, with its deadline (MOD-017's parameter tick: same-beat changes first).
    @ObservationIgnored var willStep: (UInt64) -> Void = { (_: UInt64) -> Void in }
    /// Runs a step through the show's immediate path; set by `ShowCoordinator`.
    @ObservationIgnored var perform: (CueStepRequest) -> Void = { (_: CueStepRequest) -> Void in }
    /// False in tests: they call `tick(at:)` themselves.
    @ObservationIgnored var schedulesWakeUps = true
    @ObservationIgnored private var wakeTask: Task<Void, Never>?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let stored: QuantizeMode = defaults.string(forKey: Self.key).flatMap(QuantizeMode.init(rawValue:)) ?? .off
        step = QuantizedCueStep(mode: stored)
    }

    isolated deinit { wakeTask?.cancel() }

    // MARK: - Mode (R1, R8)

    var mode: QuantizeMode {
        get { step.mode }
        set { setMode(newValue) }
    }

    private func setMode(_ newMode: QuantizeMode) {
        let dropped: Bool = step.setMode(newMode)
        let stored: QuantizeMode = step.mode
        if stored == .off { defaults.removeObject(forKey: Self.key) } else { defaults.set(stored.rawValue, forKey: Self.key) }
        if dropped { announce(Self.cancelledAnnouncement) }
        reschedule()
    }

    static func title(_ mode: QuantizeMode) -> String {
        switch mode {
        case .beat: return "Beat"
        case .bar: return "Bar"
        case .off, .cue: return "Off"
        }
    }

    // MARK: - Requests (R2, R3, R5, R6)

    enum Decision: Equatable {
        /// Step now (Off, or the no-tempo fallback, already announced).
        case stepNow
        /// Queued, replaced, cancelled or kept: nothing moves now.
        case held
    }

    /// A step request that would move the show. `timed` is SHOW-002's advance.
    func intercept(_ request: CueStepRequest, timed: Bool = false) -> Decision {
        let result: CueStepRequestResult = step.request(request, at: clock(), tempo: tempo(), timed: timed)
        defer { reschedule() }
        switch result {
        case let .applyNow(reason):
            if reason == .noTempo { announce(Self.noTempoAnnouncement) }
            return .stepNow
        case .queued, .replaced:
            if let text = queuedText { announce(text) }
            return .held
        case .cancelled:
            announce(Self.cancelledAnnouncement)
            return .held
        case .kept:
            return .held
        }
    }

    // MARK: - Boundaries (R4)

    /// Applies the waiting step when `time` has reached its deadline (once).
    func tick(at time: UInt64) {
        let deadline: UInt64? = step.deadline
        if let request = step.takeDue(at: time), let deadline {
            willStep(deadline)
            appliedAtBoundary += 1
            perform(request)
        }
        reschedule()
    }

    private func reschedule() {
        wakeTask?.cancel()
        wakeTask = nil
        guard schedulesWakeUps, let deadline = step.deadline else { return }
        let now: UInt64 = clock()
        let delay: UInt64 = deadline > now ? deadline - now : 0
        wakeTask = Task { @MainActor [weak self] () -> Void in
            try? await Task.sleep(for: .nanoseconds(Int64(clamping: delay)))
            guard !Task.isCancelled, let self else { return }
            self.tick(at: self.clock())   // an early wake-up applies nothing and reschedules
        }
    }

    // MARK: - Texts (R7)

    /// "Cue queued for the next beat" (or bar) while a step waits; nil otherwise.
    var queuedText: String? {
        guard step.pending != nil else { return nil }
        return step.mode == .bar ? "Cue queued for the next bar" : "Cue queued for the next beat"
    }
}
