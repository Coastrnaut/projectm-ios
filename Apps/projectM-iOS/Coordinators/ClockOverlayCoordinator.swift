// ClockOverlayCoordinator.swift — the MED-011 clock overlay in the app (MED-011-R1, R2, R5 to R8; research
// MED-011-D2, D4; contracts/clock-overlay.md C2, C4).
//
// * `settings` are saved at once and pushed to every attached layer. Hidden → the layers get an empty spec
//   (transparent, nothing drawn) and the tick stops.
// * `attach(to:)` gives a compositor visual (Photo, Video, Camera, Text) its own MED-009 `TextLayerSource`
//   (name "clock") as the top `.clock` stack entry, after MED-010's logo, so the clock is content: it reaches
//   captures, recordings and the external display. Layers are held weakly; a released visual drops out.
// * `tick()` reads the injected `ClockSource` and pushes a spec only when the string changed (`ClockText`), so
//   the text layer rasterizes once per change and CMP-013 reuses its picture in between. While shown and a layer
//   is live, a main-actor task ticks at each whole second (`ClockSchedule`); the compositors' frame loops run on
//   the main run loop, so the spec is set on their thread. No network time (R2).
import Compositor
import Foundation
import Metal
import Observation
import TextLayer

@MainActor
@Observable
final class ClockOverlayCoordinator {
    static let help = "Shows the time on this device over the Photo, Video, Camera and Text visuals, "
        + "and in their captures and recordings. projectM and the spectrum and oscilloscope visuals don't show it."

    var settings: ClockOverlaySettings {
        didSet {
            guard settings != oldValue else { return }
            store?.save(settings)
            refresh()
        }
    }
    /// The string shown last (nil before the first tick or while hidden).
    private(set) var currentText: String?

    @ObservationIgnored private let store: ClockOverlayStore?
    @ObservationIgnored let source: any ClockSource
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private var text: ClockText
    @ObservationIgnored private let layers = OverlayTextLayers(kind: .clock)   // shared with MED-012's countdown
    @ObservationIgnored private var ticker: Task<Void, Never>?

    init(store: ClockOverlayStore?, source: any ClockSource = SystemClockSource(), locale: Locale = .autoupdatingCurrent) {
        self.store = store
        self.source = source
        self.locale = locale
        let loaded = store?.load() ?? .default
        settings = loaded
        text = ClockText(formatter: loaded.makeFormatter(locale: locale, timeZone: source.timeZone))
    }

    isolated deinit { ticker?.cancel() }

    static func makeDefault(defaults: UserDefaults) -> ClockOverlayCoordinator {
        ClockOverlayCoordinator(store: ClockOverlayStore(defaults: defaults))
    }

    /// The app's clock: the device's wall clock, or in DEBUG UI tests the `-uitestClockFixed` fixture.
    static func makeForApp(defaults: UserDefaults) -> ClockOverlayCoordinator {
        #if DEBUG
        if let fixed = UITestClockFixture.make(defaults: defaults) { return fixed }
        #endif
        return makeDefault(defaults: defaults)
    }

    private func makeText() -> ClockText {
        ClockText(formatter: settings.makeFormatter(locale: locale, timeZone: source.timeZone))
    }

    /// "Off", or the format ("24-hour", "12-hour with seconds") — the Show Clock row's VoiceOver value.
    var summary: String {
        guard settings.isShown else { return "Off" }
        return settings.hourCycle.title + (settings.showsSeconds ? " with seconds" : "")
    }

    // MARK: - Ticks

    /// Reads the clock; pushes a new spec to the layers only when the string changed. Returns whether it did.
    @discardableResult
    func tick() -> Bool {
        guard settings.isShown else { return false }
        guard let string = text.update(at: source.now, timeZone: source.timeZone) else { return false }
        currentText = string
        push(settings.spec(for: string))
        return true
    }

    /// After a settings change: the new style (and string) at once, then the tick as needed.
    private func refresh() {
        if settings.isShown {
            text = makeText()   // a new format or style: the next tick always pushes
            tick()
        } else {
            currentText = nil
            push(settings.spec(for: nil))
        }
        updateTicker()
    }

    private func push(_ spec: TextOverlaySpec) { layers.push(spec) }

    /// Runs the one-per-second task while shown and a layer is live.
    private func updateTicker() {
        let run = settings.isShown && !layers.isEmpty
        if run, ticker == nil {
            ticker = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    guard let delay: TimeInterval = self.map({ (c: ClockOverlayCoordinator) -> TimeInterval in ClockSchedule.delay(after: c.source.now) }) else { return }
                    try? await Task.sleep(for: .milliseconds(Int((delay * 1000).rounded(.up))))
                    guard !Task.isCancelled, let self, self.keepTicking() else { return }
                }
            }
        } else if !run, let task = ticker {
            task.cancel()
            ticker = nil
        }
    }

    /// One tick of the task; false (and the task is dropped) when nothing needs the clock any more.
    private func keepTicking() -> Bool {
        guard settings.isShown, !layers.isEmpty else {
            ticker = nil
            return false
        }
        tick()
        return true
    }

    /// True while the tick task runs (tests).
    var isTicking: Bool { ticker != nil }

    // MARK: - Layers (MED-011-R6)

    /// Gives `compositor` its clock layer (top of its stack) and returns it; nil when it has one or the stack
    /// refused it.
    @discardableResult
    func attach(to compositor: Compositor) -> TextLayerSource? {
        tick()   // the current time for the layers already attached and this one
        guard let layer = layers.attach(to: compositor, spec: settings.spec(for: settings.isShown ? currentText : nil)) else { return nil }
        updateTicker()
        return layer
    }

    /// Frames in which any live clock layer showed the clock (DEBUG probe, tests).
    var framesShown: Int { layers.framesShown }
}
