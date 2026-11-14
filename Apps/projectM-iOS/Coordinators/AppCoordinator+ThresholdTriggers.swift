// AppCoordinator+ThresholdTriggers.swift — MOD-006: a scene's threshold triggers drive MIDI-006's trigger actions
// (MOD-006-R11; specs/148-mod-006-threshold-trigger, research MOD-006-D5, D8, contract T6).
//
// * When a native spectrum is created it gets the current scene's usable triggers, exactly as it gets the restored
//   bindings (SCN-002); a show cue's scene changes neither (it applies the look only).
// * A fired trigger goes to a `MIDINoteActionPerformer` over the show and the output blackout: Next cue, Previous cue
//   (SHOW-001's step, announced on the `.cue` lane) and Black out (OUT-010's toggle). The identifiers are MIDI-006's.
import ParameterGraph
import PerformanceControl

extension AppCoordinator {
    func connectThresholdTriggers(_ host: NativeSpectrumHost) {
        try? host.setTriggers(sceneAutosave?.triggerBindings ?? [])   // already read and limited; invalid ones never reach here
        let performer = MIDINoteActionPerformer(show: show, external: externalDisplay)
        host.onTrigger = { (action: ThresholdTriggerAction) -> Void in
            Self.perform(action, with: performer)
        }
    }

    /// Maps a threshold trigger action onto the MIDI-006 action of the same identifier.
    static func perform(_ action: ThresholdTriggerAction, with performer: MIDINoteActionPerformer) {
        guard let note = MIDINoteAction(rawValue: action.rawValue) else { return }
        performer.fire(note)
    }
}
