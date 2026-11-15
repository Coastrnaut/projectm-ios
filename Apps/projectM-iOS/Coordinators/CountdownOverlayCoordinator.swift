// CountdownOverlayCoordinator.swift — the MED-012 countdown overlay in the app (MED-012-R1 to R10; research MED-012-D1
// to D7; contracts/countdown-overlay.md C2 to C5).
//
// * `settings` are saved at once and pushed to every attached layer; a duration change resets the run (stopped at the
//   new duration, re-armed). Hidden → the layers get an empty spec; the countdown itself keeps running.
// * `timer` is MED-012's pure `CountdownTimer` on an injected `MonotonicClock` (the app's reads `ContinuousClock`;
//   never the wall clock). Start/Pause/Reset by hand (Settings); `startFromCue(seconds:)` when a show cue applies a
//   scene with a countdown.
// * `tick()` advances the timer and pushes a spec only when the shown string changed (MED-011's `ChangedText`), so the
//   layer redraws at most once per shown second and never after zero. On the update that reaches zero the finished
//   event fires once: `finishedCount` grows by one and "Countdown finished" is announced on the `.countdown` lane.
//   A main-actor task sleeps to the next change of the shown second only while the countdown runs; `appBecameActive()`
//   ticks once after the background (a countdown that ended meanwhile finishes then, once).
// * `attach(to:)` gives a compositor visual its `.countdown` layer through the shared `OverlayTextLayers`, above the
//   clock, so the countdown is content (captures, recordings, the external display).
import Compositor
import Foundation
import Observation
import TextLayer

@MainActor
@Observable
final class CountdownOverlayCoordinator {
    static let help = "Counts down over the Photo, Video, Camera and Text visuals and in their captures and recordings. "
        + "projectM and the spectrum and oscilloscope visuals don't show it. A cue can start it; it stays on screen only while Show Countdown is on."
    static let finishedAnnouncement = "Countdown finished"

    var settings: CountdownOverlaySettings {
        didSet {
            guard settings != oldValue else { return }
            store?.save(settings)
            if settings.durationSeconds != oldValue.durationSeconds { timer.reset(durationSeconds: settings.durationSeconds) }
            text.clear()   // a new style or duration: the next tick always pushes
            tick()
            updateTicker()
        }
    }
    private(set) var timer: CountdownTimer
    /// The string shown last (nil before the first tick).
    private(set) var currentText: String?
    /// Finished events since launch (tests, DEBUG probe).
    private(set) var finishedCount = 0

    /// Speaks the finished announcement (the app wires the shared announcer).
    @ObservationIgnored var announce: ((String) -> Void)?
    @ObservationIgnored private let store: CountdownOverlayStore?
    @ObservationIgnored let clock: any MonotonicClock
    @ObservationIgnored private var text = ChangedText()
    @ObservationIgnored private let layers = OverlayTextLayers(kind: .countdown)
    @ObservationIgnored private var ticker: Task<Void, Never>?

    init(store: CountdownOverlayStore?, clock: any MonotonicClock = ContinuousMonotonicClock()) {
        self.store = store
        self.clock = clock
        let loaded = store?.load() ?? .default
        settings = loaded
        timer = CountdownTimer(durationSeconds: loaded.durationSeconds)
        currentText = CountdownFormat.string(timer, at: clock.seconds)
    }

    isolated deinit { ticker?.cancel() }

    static func makeDefault(defaults: UserDefaults) -> CountdownOverlayCoordinator {
        CountdownOverlayCoordinator(store: CountdownOverlayStore(defaults: defaults))
    }

    /// The app's countdown: the continuous clock, or in DEBUG UI tests the `-uitestCountdownFixed` fixture.
    static func makeForApp(defaults: UserDefaults) -> CountdownOverlayCoordinator {
        #if DEBUG
        if let fixed = UITestCountdownFixture.make(defaults: defaults) { return fixed }
        #endif
        return makeDefault(defaults: defaults)
    }

    var state: CountdownState { timer.state }

    /// "Off", or the duration ("5:00") — the Show Countdown row's VoiceOver value.
    var summary: String {
        guard settings.isShown else { return "Off" }
        return CountdownFormat.string(seconds: settings.durationSeconds)
    }

    // MARK: - Control (MED-012-R5, R8)

    /// Starts, or resumes after a pause; after a finish, starts again from the full duration.
    func start() {
        timer.start(at: clock.seconds)
        tick()
        updateTicker()
    }

    func pause() {
        timer.pause(at: clock.seconds)
        tick()
        updateTicker()
    }

    /// Stopped at the full duration, re-armed.
    func reset() {
        timer.reset()
        tick()
        updateTicker()
    }

    /// A show cue applied a scene with a countdown: restarts with that duration (the settings' duration is unchanged).
    func startFromCue(seconds: Int) {
        timer.reset(durationSeconds: seconds)
        start()
    }

    /// After the app returns to the foreground: catches up at once (the tick task was suspended meanwhile).
    func appBecameActive() { tick() }

    // MARK: - Ticks

    /// Advances the timer; fires the finished event on the update that reaches zero and pushes a new spec only when
    /// the shown string changed. Returns whether it pushed.
    @discardableResult
    func tick() -> Bool {
        let now = clock.seconds
        if timer.advance(at: now) {
            finishedCount += 1
            announce?(Self.finishedAnnouncement)
        }
        guard let string = text.report(CountdownFormat.string(timer, at: now)) else { return false }
        currentText = string
        layers.push(settings.spec(for: string))
        return true
    }

    /// Runs the tick task while the countdown runs (shown or not: the finished event still fires once).
    private func updateTicker() {
        if timer.isRunning, ticker == nil {
            ticker = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    guard let delay: Double = self.flatMap({ (c: CountdownOverlayCoordinator) -> Double? in
                        CountdownSchedule.delay(c.timer, at: c.clock.seconds)
                    }) else { break }
                    try? await Task.sleep(for: .milliseconds(Int((delay * 1000).rounded(.up))))
                    guard !Task.isCancelled, let self else { return }
                    self.tick()
                }
                self?.ticker = nil
            }
        } else if !timer.isRunning, let task = ticker {
            task.cancel()
            ticker = nil
        }
    }

    /// True while the tick task runs (tests).
    var isTicking: Bool { ticker != nil }

    // MARK: - Layers (MED-012-R7)

    /// Gives `compositor` its countdown layer (top of its stack, above the clock) and returns it; nil when it has one or
    /// the stack refused it.
    @discardableResult
    func attach(to compositor: Compositor) -> TextLayerSource? {
        tick()
        return layers.attach(to: compositor, spec: settings.spec(for: currentText))
    }

    /// Frames in which any live countdown layer showed the countdown (DEBUG probe, tests).
    var framesShown: Int { layers.framesShown }
}
