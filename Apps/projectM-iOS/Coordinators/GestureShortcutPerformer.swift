// GestureShortcutPerformer.swift — UIX-006-R7 (specs/290-uix-006-touch-gesture-mapping, contract G3; research
// UIX-006-D5): each catalogue action through the path its existing control uses, quietly (the controls are not
// revealed, as with the keyboard and MIDI paths, MIDI-006 `MIDINoteActionPerformer`):
// * Next/Previous cue: SHOW-001's `show.next()/previous()` (the show announces the cue on its lane);
// * Next/Previous preset: the preset coordinator's step inside the app's ACC-004 preset announcement;
// * Tap tempo: SHOW-011's `tempo.tap()`;
// * Show/hide HUD: UIX-013's "Show HUD" preference.
// The scene lock never blocks these (SCN-015: navigation never consults it). Actions are injected for tests.
import PerformanceControl

@MainActor
final class GestureShortcutPerformer {
    struct Actions {
        var nextCue: @MainActor () -> Void
        var previousCue: @MainActor () -> Void
        var nextPreset: @MainActor () -> Void
        var previousPreset: @MainActor () -> Void
        var tapTempo: @MainActor () -> Void
        var toggleHUD: @MainActor () -> Void
    }

    private let actions: Actions
    /// The last action run and how many ran (tests and the DEBUG probe, contract G5).
    private(set) var last: GestureAction = .none
    private(set) var count = 0
    /// Called after each run (the app mirrors `last` and `count` into observed state for the probe).
    var didPerform: @MainActor () -> Void = { () -> Void in }

    init(actions: Actions) {
        self.actions = actions
    }

    /// The app's performer. `announcePresetChange` wraps a preset step (the app passes ACC-004's announcer).
    convenience init(show: ShowCoordinator, presets: PresetCoordinator, tempo: TempoCoordinator, hud: SceneHUDSetting,
                     announcePresetChange: @escaping @MainActor (@escaping () async -> Void) async -> Void
                         = { (change: @escaping () async -> Void) async -> Void in await change() }) {
        self.init(actions: Actions(
            nextCue: { [weak show] () -> Void in show?.next() },
            previousCue: { [weak show] () -> Void in show?.previous() },
            nextPreset: { [weak presets] () -> Void in
                Task { @MainActor in await announcePresetChange { () async -> Void in await presets?.next() } }
            },
            previousPreset: { [weak presets] () -> Void in
                Task { @MainActor in await announcePresetChange { () async -> Void in await presets?.previous() } }
            },
            tapTempo: { [weak tempo] () -> Void in tempo?.tap() },
            toggleHUD: { [weak hud] () -> Void in hud?.isEnabled.toggle() }))
    }

    func perform(_ action: GestureAction) {
        switch action {
        case .none: return
        case .nextCue: actions.nextCue()
        case .previousCue: actions.previousCue()
        case .nextPreset: actions.nextPreset()
        case .previousPreset: actions.previousPreset()
        case .tapTempo: actions.tapTempo()
        case .toggleHUD: actions.toggleHUD()
        }
        last = action
        count += 1
        didPerform()
    }
}
