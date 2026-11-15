// ShowAutoAdvanceCoordinator.swift — the timed cue advance in the app (SHOW-002-R3 to R9; contract
// specs/208-show-002-timed-cue-advance/contracts/show-cue-dwell.md D4; research SHOW-002-D3, D4).
//
// * Owns the pure `ShowAdvanceTimeline` and an injected monotonic clock (`ShowContinuousClock` in the app, a
//   `ShowManualClock` in tests). `ShowCoordinator.cueStarted` (every step that moved, a dwell edit on the active cue)
//   restarts it from now; `ShowCoordinator.listChanged` cancels it when its cue is no longer the active one.
// * `tick()` re-reads the hold (pause, blackout not live, a pending repair report, the app not active; set by
//   AppCoordinator) and, when the advance is due, calls `show.timedNext()` (SHOW-003: quantized like a Next): the same path as a manual Next (scene,
//   SCN-007 transition, SCN-012 repair, MOD-017 queued changes, the cue announcement). One advance per due time.
// * While the timeline is not idle a main-actor task ticks every 250 ms (or sooner at the deadline); an idle show
//   runs nothing. Tests call `tick()` themselves (`runsLoop` false).
// * `countdown` (whole seconds left, rounded up, and whether held) is what the cue row and the performance pad show.
// * SHOW-005: the performer's Hold (`isOperatorHeld`, session only, never stored) is one more hold source; turning it on
//   withdraws a timed step waiting for the beat (SHOW-003) and re-arms the countdown held at 0, so Hold off requests it
//   again at once. Manual steps never read it. `listChanged` also cancels a countdown left without a next cue (Skip).
// * SHOW-007: `playhead` is a second `ShowAdvanceTimeline` that always counts down the active timed cue (the last one
//   too) with the same holds and is never acted on: the timeline transport's position (research SHOW-007-D4).
//   `reposition(cueID:remaining:)` moves both after a seek. With `loops` on, the last timeline cue counts down too and
//   its due advance wraps to the first timeline cue through `show.timedGo(to:)` (one wrap per due time; `loopWraps`).
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
    /// SHOW-005: the performer's Hold (off at launch; never stored).
    private(set) var isOperatorHeld = false

    @ObservationIgnored private(set) var timeline = ShowAdvanceTimeline()
    /// SHOW-007: the active timed cue's elapsed time (always runs for a cue with a dwell; never fires).
    @ObservationIgnored private(set) var playhead = ShowAdvanceTimeline()
    /// SHOW-007: whether Loop is on (set by `ShowTransportCoordinator`).
    @ObservationIgnored var loops: () -> Bool = { () -> Bool in false }
    /// SHOW-007: wraps requested from the last timeline cue to the first (tests and DEBUG probes).
    @ObservationIgnored private(set) var loopWraps = 0
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
        let held: Bool = heldNow()
        timeline.setHeld(held, at: now)
        playhead.setHeld(held, at: now)
        timeline.cueStarted(show.list.activeCue, hasNext: hasNext(), at: now)   // SHOW-007: Loop counts as a next cue
        playhead.cueStarted(show.list.activeCue, hasNext: true, at: now)
        refresh()
    }

    /// Whether the active cue advances somewhere: the next cue, or (SHOW-007 Loop) the first timeline cue.
    private func hasNext() -> Bool {
        guard let show else { return false }
        return show.list.canGoNext || loopTarget() != nil
    }

    /// SHOW-007-R7: the first timeline cue when Loop is on and the active cue is the last timeline cue.
    private func loopTarget() -> UUID? {
        guard let show, let active = show.list.activeCue?.id, !show.list.canGoNext, loops() else { return nil }
        return ShowTimeline(list: show.list).loopTarget(from: active, looping: true)
    }

    /// SHOW-007-R2: a seek put the active cue's countdown at `remaining` (nil: an open-ended cue, nothing counts down).
    func reposition(cueID: UUID, remaining: Duration?) {
        guard let show, show.list.activeCue?.id == cueID else { return }
        let now: Duration = clock.now()
        let held: Bool = heldNow()
        timeline.setHeld(held, at: now)
        playhead.setHeld(held, at: now)
        if let remaining {
            playhead.rearm(cueID: cueID, remaining: remaining, at: now)
            if hasNext() { timeline.rearm(cueID: cueID, remaining: remaining, at: now) } else { timeline.cancel() }
        } else {
            playhead.cancel()
            timeline.cancel()
        }
        refresh()
    }

    /// SHOW-007-R7: Loop turned on or off. On the last timeline cue the countdown starts (from the playhead's remaining
    /// time) or stops.
    func loopChanged() {
        guard let show, let cueID = show.list.activeCue?.id else { return }
        let now: Duration = clock.now()
        if hasNext() {
            if timeline.isIdle, playhead.cueID == cueID, let left = playhead.remaining(at: now) {
                timeline.rearm(cueID: cueID, remaining: left, at: now)
            }
        } else if timeline.cueID == cueID {
            timeline.cancel()
        }
        refresh()
    }

    /// The list changed: a countdown whose cue is no longer the active one, or (SHOW-005) that has no cue left to advance
    /// to, is cancelled.
    func listChanged() {
        guard let show else { return }
        if let cueID = playhead.cueID, cueID != show.list.activeCue?.id { playhead.cancel() }   // SHOW-007
        guard let cueID = timeline.cueID else { return }
        guard cueID != show.list.activeCue?.id || !hasNext() else { return }
        timeline.cancel()
        refresh()
    }

    /// SHOW-005-R1, R3: turns the performer's Hold on or off (applied at once; the remaining time is kept).
    func setOperatorHold(_ held: Bool) {
        guard held != isOperatorHeld else { return }
        isOperatorHeld = held
        let now: Duration = clock.now()
        if held, let show, let cueID = show.list.activeCue?.id, timeline.isIdle,
           show.cueQuantizer?.withdrawTimed() == true {
            timeline.rearm(cueID: cueID, remaining: .zero, at: now)   // the withdrawn advance waits for Hold off
        }
        timeline.setHeld(heldNow(), at: now)
        playhead.setHeld(heldNow(), at: now)   // SHOW-007
        refresh()
    }

    /// Every hold source: the performer's Hold, then pause, blackout, repair report and background (SHOW-002-R7).
    private func heldNow() -> Bool { isOperatorHeld || isHeld() }

    /// Re-reads the hold, and advances once when the active cue's deadline has been reached.
    func tick() {
        guard let show else { return }
        let now: Duration = clock.now()
        let held: Bool = heldNow()
        timeline.setHeld(held, at: now)
        playhead.setHeld(held, at: now)
        if let cueID = timeline.due(at: now), show.list.activeCue?.id == cueID {
            if show.list.canGoNext {
                show.timedNext()   // SHOW-003: waits for the beat or bar when quantizing; a move calls `cueStarted` (the next cue's countdown starts at its own now)
            } else if let first = loopTarget() {
                loopWraps += 1   // SHOW-007-R7: one wrap per pass
                show.timedGo(to: first)
            }
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
