// SceneRotationCoordinator.swift — SHOW-013 auto scene rotation in the app (specs/256-show-013-auto-scene-rotation;
// R3 to R8; contract C3, C4; research SHOW-013-D2 to D5).
//
// * Owns the stored `SceneRotationSettings` (`settings.show.rotation`, JSON; a device performance choice: excluded from
//   backups, erased with Settings, cleared by the UI-test reset) and the session state: on/off (off at every launch), the
//   seed (new each time rotation turns on) and the step count.
// * `tick()` re-reads the holds: a timed cue counting down unheld (`showPlays`, SHOW-002/SHOW-007: the show wins) and
//   SHOW-002's holds (`isHeld`: pause, blackout, repair report, background, Hold). A hold clears the deadline; the
//   interval restarts when it ends. Otherwise it arms (timer, or the Nth bar line of SHOW-011's tempo) and, when due,
//   picks with ShowControl's seeded `SceneRotationPlan` and goes to the scene's first cue through the show's step path:
//   `timedGo(to:)` for the timer (quantized like SHOW-002's advance), `stepNow(.go)` on a bar line (already on the bar).
//   Transitions, Reduce Motion, Reduce flashing, the repair report and the cue announcement are therefore a cue step's.
// * `sceneChanged()` runs on every step that moved the show (chained onto `ShowCoordinator.cueStarted`), so a manual
//   change, the timed advance or rotation's own step restarts the interval from that moment.
// * The nanosecond clock is SHOW-011's tempo clock (`MonotonicClock`), injected; tests call `tick()` (`runsLoop` false).
//   While on, a main-actor task ticks every 250 ms or sooner at the deadline; off runs nothing.
import AudioCore
import Foundation
import Observation
import PerformanceControl
import ShowControl

@MainActor
@Observable
final class SceneRotationCoordinator {
    static let key = "settings.show.rotation"
    static let tickInterval: Duration = .milliseconds(250)
    static let noScenesText = "No scenes are in rotation."
    static let oneSceneText = "Only one scene is in rotation."
    static let showPlayingText = "Paused while the show plays"
    static let heldText = "Held"
    static let offText = "Off"
    static let switchingText = "Changing scene"

    enum Status: Equatable {
        case off
        case waiting
        case switching
        case held
        case showPlaying
        case idle(SceneRotationPlan.Idle)
    }

    private(set) var isOn = false
    private(set) var settings: SceneRotationSettings
    private(set) var status: Status = .off
    /// Switches requested by rotation (tests and DEBUG probes).
    private(set) var rotations = 0

    @ObservationIgnored private(set) var seed: UInt64 = 0
    @ObservationIgnored private(set) var step: Int64 = 0
    @ObservationIgnored private(set) var deadline: SceneRotationSchedule.Deadline?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private weak var show: ShowCoordinator?
    @ObservationIgnored var clock: () -> UInt64 = { () -> UInt64 in MonotonicClock.nowNanoseconds() }
    @ObservationIgnored var tempo: () -> TempoSnapshot = { () -> TempoSnapshot in .none }
    @ObservationIgnored var reduceFlashing: () -> Bool = { () -> Bool in false }
    /// SHOW-002's holds (pause, blackout, repair report, background, Hold).
    @ObservationIgnored var isHeld: () -> Bool = { () -> Bool in false }
    /// A timed cue counts down unheld: the show plays on its timeline (research SHOW-013-D3).
    @ObservationIgnored var showPlays: () -> Bool = { () -> Bool in false }
    @ObservationIgnored var makeSeed: () -> UInt64 = { () -> UInt64 in UInt64.random(in: UInt64.min...UInt64.max) }
    /// DEBUG `-uitestSceneRotation <seconds>`: a timer interval below the 15 s floor (UI tests only).
    @ObservationIgnored var intervalOverrideSeconds: Int?
    @ObservationIgnored private let runsLoop: Bool
    @ObservationIgnored private var loop: Task<Void, Never>?

    init(show: ShowCoordinator, defaults: UserDefaults, runsLoop: Bool = true) {
        self.show = show
        self.defaults = defaults
        self.runsLoop = runsLoop
        settings = Self.load(defaults)
        let previous: (() -> Void)? = show.cueStarted
        show.cueStarted = { [weak self] () -> Void in
            previous?()
            self?.sceneChanged()
        }
    }

    isolated deinit { loop?.cancel() }

    static func load(_ defaults: UserDefaults) -> SceneRotationSettings {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(SceneRotationSettings.self, from: data) else { return SceneRotationSettings() }
        return stored
    }

    // MARK: - Settings (R7, R8)

    func setOn(_ on: Bool) {
        guard on != isOn else { return }
        isOn = on
        deadline = nil
        if on {
            seed = makeSeed()
            step = 0
            status = .waiting
            tick()
        } else {
            status = .off
        }
        updateLoop()
    }

    /// Changes the stored settings (default values remove the key) and rearms from now.
    func update(_ change: (inout SceneRotationSettings) -> Void) {
        var next: SceneRotationSettings = settings
        change(&next)
        if let show { next.prune(keepingScenes: Set(show.list.sceneIDs)) }
        guard next != settings else { return }
        settings = next
        if next == SceneRotationSettings() {
            defaults.removeObject(forKey: Self.key)
        } else if let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: Self.key)
        }
        if isOn { arm(at: clock()) }
    }

    func setEnabled(_ enabled: Bool, sceneID: String) {
        update { (s: inout SceneRotationSettings) -> Void in s.setEnabled(enabled, sceneID: sceneID) }
    }

    /// The plan over the show now (the collection is recomputed at every use).
    var plan: SceneRotationPlan {
        guard let show else { return SceneRotationPlan(collection: [], disabled: []) }
        return SceneRotationPlan(list: show.list, folder: settings.folderID, disabled: Set(settings.disabledSceneIDs))
    }

    // MARK: - Driving (C3)

    /// A step moved the show (manual, timed, a seek or rotation's own): the interval restarts now (R5).
    func sceneChanged() {
        guard isOn, status != .held, status != .showPlaying else { return }
        arm(at: clock())
    }

    func tick() {
        guard isOn, let show else { return }
        if showPlays() { return pause(.showPlaying) }
        if isHeld() { return pause(.held) }
        let now: UInt64 = clock()
        if status == .switching {   // a quantized step waits; the move rearms (a withdrawn one rearms here)
            if show.cueQuantizer?.step.pending != nil { return }
            return arm(at: now)
        }
        guard let due = deadline else { return arm(at: now) }
        guard now >= due.at else { return }
        rotate(show, onBeat: due.onBeat, now: now)
    }

    private func pause(_ reason: Status) {
        deadline = nil
        if status != reason { status = reason }
    }

    private func arm(at now: UInt64) {
        let enabled: Int = plan.enabled.count
        if enabled < 2 {
            deadline = nil
            let idle: Status = .idle(enabled == 0 ? .noScenes : .oneScene)
            if status != idle { status = idle }
            return
        }
        deadline = schedule(after: now)
        if status != .waiting { status = .waiting }
    }

    private func schedule(after now: UInt64) -> SceneRotationSchedule.Deadline {
        let snapshot: TempoSnapshot = tempo()
        if settings.mode == .timer, let override = intervalOverrideSeconds {
            return SceneRotationSchedule.Deadline(at: now &+ UInt64(max(override, 1)) * SceneRotationSchedule.nanosecondsPerSecond,
                                                  onBeat: false)
        }
        return SceneRotationSchedule.deadline(after: now, settings: settings, reduceFlashing: reduceFlashing(),
                                              barLine: { (t: UInt64) -> UInt64? in snapshot.nextBoundary(after: t, beats: 4) })
    }

    private func rotate(_ show: ShowCoordinator, onBeat: Bool, now: UInt64) {
        let pick: SceneRotationPlan.Pick = plan.pick(current: show.list.activeSceneID, seed: seed, step: step)
        guard case let .scene(sceneID) = pick, let cue = show.firstCue(ofScene: sceneID) else { return arm(at: now) }
        step += 1
        rotations += 1
        deadline = nil
        status = .switching
        let result: ShowStep = onBeat ? show.stepNow(.go(cue.id)) : show.timedGo(to: cue.id)
        if result.outcome != .moved, result.outcome != .queued { arm(at: clock()) }   // nothing moved and nothing waits
    }

    // MARK: - Texts (R7)

    /// The status line at `now` ("Next scene in 0:42", "Next scene on the bar in 0:16", the hold and idle texts).
    func statusText(at now: UInt64) -> String {
        switch status {
        case .off: return Self.offText
        case .switching: return Self.switchingText
        case .held: return Self.heldText
        case .showPlaying: return Self.showPlayingText
        case .idle(.noScenes): return Self.noScenesText
        case .idle(.oneScene): return Self.oneSceneText
        case .waiting:
            guard let deadline else { return Self.offText }
            let left: UInt64 = deadline.at > now ? deadline.at - now : 0
            let perSecond: UInt64 = SceneRotationSchedule.nanosecondsPerSecond
            let seconds: Int = Int((left + perSecond - 1) / perSecond)
            let clock: String = ShowCueDwell.clockText(seconds: seconds)
            return deadline.onBeat ? "Next scene on the bar in \(clock)" : "Next scene in \(clock)"
        }
    }

    var statusText: String { statusText(at: clock()) }

    // MARK: - Loop (D4)

    private func updateLoop() {
        if !isOn || !runsLoop {
            loop?.cancel()
            loop = nil
            return
        }
        guard loop == nil else { return }
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let wait: Duration = self?.nextWait() ?? Self.tickInterval
                try? await Task.sleep(for: wait)
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    /// 250 ms, or less when the deadline is nearer (never under 10 ms).
    private func nextWait() -> Duration {
        guard let deadline else { return Self.tickInterval }
        let now: UInt64 = clock()
        let left: UInt64 = deadline.at > now ? deadline.at - now : 0
        return max(.milliseconds(10), min(Self.tickInterval, .nanoseconds(Int64(min(left, UInt64(Int64.max))))))
    }
}
