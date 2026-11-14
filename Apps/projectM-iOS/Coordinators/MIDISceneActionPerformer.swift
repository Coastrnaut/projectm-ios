// MIDISceneActionPerformer.swift — MIDI-007 scene commands to SHOW-001's Go to Cue (MIDI-007-R2, R4 to R6, R10;
// research MIDI-007-D3, D5; specs/147-midi-007-scene-selection, contract S4).
//
// * `.scene(id)`: nothing when `id` is the active cue's scene (debounce: a repeated program change re-applies
//   nothing); "Scene not found." on the `.midi` lane when no cue shows `id`; otherwise Go to Cue for the scene's
//   first cue (SCN-004 `goToScene`), which applies it and announces the cue on SHOW-001's `.cue` lane.
// * `.cue(index)`: nothing when that cue is active; "Cue n not found." when the show has fewer cues; otherwise Go to
//   Cue for that position.
// Selecting never touches the MIDI mappings (MIDI-007-R3). The actions are injected so tests drive the performer
// without a show.
import PerformanceControl
import ShowControl

@MainActor
final class MIDISceneActionPerformer {
    struct Actions {
        /// The active cue's scene ID (nil at Standby).
        var activeSceneID: @MainActor () -> String?
        /// The active cue's 0-based position (nil at Standby).
        var activeIndex: @MainActor () -> Int?
        var cueCount: @MainActor () -> Int
        /// Whether a cue shows the scene.
        var hasScene: @MainActor (String) -> Bool
        var goToScene: @MainActor (String) -> Void
        var goToCue: @MainActor (Int) -> Void
    }

    private let actions: Actions
    private let announce: @MainActor (String) -> Void

    init(actions: Actions, announce: @escaping @MainActor (String) -> Void) {
        self.actions = actions
        self.announce = announce
    }

    /// The app's performer over the show; `announce` is the `.midi` lane.
    convenience init(show: ShowCoordinator, announce: @escaping @MainActor (String) -> Void) {
        let actions = Actions(
            activeSceneID: { [weak show] () -> String? in show?.list.activeSceneID },
            activeIndex: { [weak show] () -> Int? in show?.list.activeIndex },
            cueCount: { [weak show] () -> Int in show?.list.cues.count ?? 0 },
            hasScene: { [weak show] (id: String) -> Bool in show?.firstCue(ofScene: id) != nil },
            goToScene: { [weak show] (id: String) -> Void in show?.goToScene(id) },
            goToCue: { [weak show] (index: Int) -> Void in
                guard let show, index >= 0, index < show.list.cues.count else { return }
                show.go(to: show.list.cues[index].id)
            })
        self.init(actions: actions, announce: announce)
    }

    /// "Cue 10 not found."
    static func cueNotFoundText(_ index: Int) -> String { "Cue " + String(index + 1) + " not found." }

    func perform(_ command: MIDISceneCommand) {
        switch command {
        case let .scene(id, _):
            guard actions.activeSceneID() != id else { return }
            guard actions.hasScene(id) else { return announce(MIDIMappingCoordinator.sceneNotFoundText) }
            actions.goToScene(id)
        case let .cue(index, _):
            guard actions.activeIndex() != index else { return }
            guard index < actions.cueCount() else { return announce(Self.cueNotFoundText(index)) }
            actions.goToCue(index)
        }
    }
}
