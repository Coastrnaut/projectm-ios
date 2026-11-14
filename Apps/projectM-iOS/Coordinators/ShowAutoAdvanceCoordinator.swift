// ShowAutoAdvanceCoordinator.swift — the timed cue advance in the app (SHOW-002-R3 to R9; contract
// specs/208-show-002-timed-cue-advance/contracts/show-cue-dwell.md D4; research SHOW-002-D3, D4).
//
// * Owns the pure `ShowAdvanceTimeline` and an injected monotonic clock (`ShowContinuousClock` in the app, a
//   `ShowManualClock` in tests). `ShowCoordinator.cueStarted` (every step that moved, a dwell edit on the active cue)
//   restarts it from now; `ShowCoordinator.listChanged` cancels it when its cue is no longer the active one.
// * `tick()` re-reads the hold (pause, blackout not live, a pending repair report, the app not active; set by
//   AppCoordinator) and, when the advance is due, calls `show.next()`: the same path as a manual Next (scene,
//   SCN-007 transition, SCN-012 repair, MOD-017 queued changes, the cue announcement). One advance per due time.
// * While the timeline is not idle a main-actor task ticks every 250 ms (or sooner at the deadline); an idle show
//   runs nothing. Tests call `tick()` themselves (`runsLoop` false).
// * `countdown` (whole seconds left, rounded up, and whether held) is what the cue row and the performance pad show.
import Foundation
import Observation
import ShowControl

@MainActor
@Observable
final class ShowAutoAdvanceCoordinator {
    struct Countdown: Equatable {
        let seconds: Int
        let held: Bool
    }

    static let tickInterval: Duration = .milliseconds(250)

    /// The countdown to the next timed advance (nil when nothing counts down).
    private(set) var countdown: Countdown?

    @ObservationIgnored private(set) var timeline = ShowAdvanceTimeline()
    @ObservationIgnored let clock: any ShowMonotonicClock
    @ObservationIgnored private weak var show: ShowCoordinator?
    /// Whether the countdown holds now (pause, blackout, repair report, background); set by AppCoordinator.
    @ObservationIgnored var isHeld: () -> Bool = { () -> Bool in false }
    @ObservationIgnored private let runsLoop: Bool
    @ObservationIgnored private var loop: Task<Void, Never>?

    init(show: ShowCoordinator, clock: any ShowMonotonicClock = ShowContinuousClock(), runsLoop: Bool = true) {
        self.show = show
        self.clock = clock
        self.runsLoop = runsLoop
        show.cueStarted = { [weak self] () -> Void in self?.cueStarted() }
        show.listChanged = { [weak self] () -> Void in self?.listChanged() }
    }

    // MARK: Text

    /// "Next in 0:42", or "Next in 0:42, held".
    var countdownText: String? {
        guard let countdown else { return nil }
        let clock: String = ShowCueDwell.clockText(seconds: countdown.seconds)
        return countdown.held ? "Next in \(clock), held" : "Next in \(clock)"
    }

    /// "next cue in 42 seconds", or "countdown held, 42 seconds left".
    var spokenCountdown: String? {
        guard let countdown else { return nil }
        let spoken: String = ShowCueDwell.spokenText(seconds: countdown.seconds)
        return countdown.held ? "countdown held, \(spoken) left" : "next cue in \(spoken)"
    }

    // MARK: Driving

    /// A step moved to a cue (or its dwell changed): the countdown restarts from now.
    func cueStarted() {
        guard let show else { return }
        let now: Duration = clock.now()
        timeline.setHeld(isHeld(), at: now)
        ShowTimedAdvance.started(list: show.list, timeline: &timeline, at: now)
        refresh()
    }

    /// The list changed: a countdown whose cue is no longer the active one is cancelled.
    func listChanged() {
        guard let show, let cueID = timeline.cueID, cueID != show.list.activeCue?.id else { return }
        timeline.cancel()
        refresh()
    }

    /// Re-reads the hold, and advances once when the active cue's deadline has been reached.
    func tick() {
        guard let show else { return }
        let now: Duration = clock.now()
        timeline.setHeld(isHeld(), at: now)
        if let cueID = timeline.due(at: now), show.list.activeCue?.id == cueID {
            show.next()   // a move calls `cueStarted` (the next cue's countdown starts at its own now)
        }
        refresh()
    }

    private func refresh() {
        let seconds: Int? = timeline.remainingWholeSeconds(at: clock.now())
        let next: Countdown? = seconds.map { (s: Int) -> Countdown in Countdown(seconds: s, held: timeline.isHeld) }
        if next != countdown { countdown = next }
        updateLoop()
    }

    private func updateLoop() {
        if timeline.isIdle {
            loop?.cancel()
            loop = nil
        } else if loop == nil, runsLoop {
            loop = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    let wait: Duration = self?.nextWait() ?? Self.tickInterval
                    try? await Task.sleep(for: wait)
                    guard !Task.isCancelled, let self else { return }
                    self.tick()
                }
            }
        }
    }

    /// 250 ms, or less when the deadline is nearer (never under 10 ms).
    private func nextWait() -> Duration {
        guard !timeline.isHeld, let left = timeline.remaining(at: clock.now()) else { return Self.tickInterval }
        return max(.milliseconds(10), min(Self.tickInterval, left))
    }
}
