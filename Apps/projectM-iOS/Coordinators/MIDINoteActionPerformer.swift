// MIDINoteActionPerformer.swift — MIDI-006 note commands to the app's existing actions (research MIDI-006-D5,
// contract N4; specs/143-midi-006-note-triggers).
//
// * Next cue / Previous cue: SHOW-001's step (the keyboard path: the controls are not shown); the show announces the
//   cue on its `.cue` lane.
// * Black out (trigger): OUT-010's toggle, as the controls' Black out button.
// * Black out while held: engage blacks out only if the output is not already blacked out, and remembers that it did;
//   release restores only what the hold did, and only if the output is still blacked out (spec Clarifications).
//   Restore keeps OUT-010's fade and spacing; the status-event path announces both.
// * MIDI-008 (specs/157-midi-008-transport, research MIDI-008-D5): Play/Pause toggles the visualizer's Pause (FR-046);
//   Play only resumes and Pause only pauses, so a repeat changes nothing. The app's path announces on `.playback` and
//   never reveals the controls.
// The actions are injected so tests drive the performer without a show or a display.
import PerformanceControl

@MainActor
final class MIDINoteActionPerformer {
    struct Actions {
        var nextCue: @MainActor () -> Void
        var previousCue: @MainActor () -> Void
        var isBlackoutRequested: @MainActor () -> Bool
        var setBlackout: @MainActor (Bool) -> Void
        /// MIDI-008: the visualizer's Pause.
        var isPaused: @MainActor () -> Bool = { () -> Bool in false }
        var setPaused: @MainActor (Bool) -> Void = { (_: Bool) -> Void in }
    }

    private let actions: Actions
    /// The hold blacked out the output and has not restored it yet.
    private(set) var holdBlackedOut = false

    init(actions: Actions) {
        self.actions = actions
    }

    /// The app's performer over the show and the output blackout.
    convenience init(show: ShowCoordinator, external: ExternalDisplayCoordinator,
                     isPaused: @escaping @MainActor () -> Bool = { () -> Bool in false },
                     setPaused: @escaping @MainActor (Bool) -> Void = { (_: Bool) -> Void in }) {
        var actions = Actions(
            nextCue: { [weak show] () -> Void in show?.next() },
            previousCue: { [weak show] () -> Void in show?.previous() },
            isBlackoutRequested: { [weak external] () -> Bool in external?.isBlackoutRequested ?? false },
            setBlackout: { [weak external] (on: Bool) -> Void in external?.setBlackout(on) })
        actions.isPaused = isPaused
        actions.setPaused = setPaused
        self.init(actions: actions)
    }

    func perform(_ commands: [MIDINoteCommand]) {
        for command in commands { perform(command) }
    }

    /// MOD-006: a trigger-mode action fired by a threshold trigger (the same path as a note's `.fire`).
    func fire(_ action: MIDINoteAction) {
        switch action {
        case .cueNext: actions.nextCue()
        case .cuePrevious: actions.previousCue()
        case .blackout: actions.setBlackout(!actions.isBlackoutRequested())
        case .transportToggle: actions.setPaused(!actions.isPaused())
        case .transportPlay: if actions.isPaused() { actions.setPaused(false) }
        case .transportPause: if !actions.isPaused() { actions.setPaused(true) }
        }
    }

    func perform(_ command: MIDINoteCommand) {
        switch (command.target.action, command.phase) {
        case (.cueNext, .fire), (.cuePrevious, .fire), (.blackout, .fire),
             (.transportToggle, .fire), (.transportPlay, .fire), (.transportPause, .fire):
            fire(command.target.action)
        case (.blackout, .engage):
            guard !actions.isBlackoutRequested() else { return }
            actions.setBlackout(true)
            holdBlackedOut = true
        case (.blackout, .release):
            guard holdBlackedOut else { return }
            holdBlackedOut = false
            if actions.isBlackoutRequested() { actions.setBlackout(false) }
        case (.cueNext, _), (.cuePrevious, _), (.transportToggle, _), (.transportPlay, _), (.transportPause, _):
            break   // cue and transport actions are trigger-only
        }
    }
}
