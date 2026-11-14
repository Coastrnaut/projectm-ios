// MIDIMappingCoordinator+Panic.swift — the user's MIDI panic (MIDI-013-R1 to R6, R9; specs/183-midi-013-panic,
// contract P2, research MIDI-013-D1 to D3).
//
// One command, from the Settings button, ⌘⇧M, the visualizer's VoiceOver action or a `midi.panic` binding:
// * any learn session (CC, trigger or scene) ends with no binding;
// * messages still queued in the input are dropped (they were sent before the command);
// * every held trigger key goes up through the router's source-loss release, so `MIDINoteActionPerformer` undoes a
//   "Black out while held" exactly as on the key's release; then the press rule forgets everything (MIDI-008's repeat
//   window included), so the next press is fresh;
// * "MIDI reset" is announced on the `.midi` lane every time (also when nothing was held).
// It never saves: the stored mappings, live CC values, scene bindings, the show and listening stay as they are.
import Foundation
import PerformanceControl

extension MIDIMappingCoordinator {
    static let panicText: String = "MIDI reset"

    /// Runs the panic (MIDI-013 contract P2).
    func panic() {
        cancelCCLearnSession()
        _ = noteSession.cancel()
        _ = sceneSession.cancel()
        endLearning()
        input.discardPending()   // MIDI-013-R3
        let commands: [MIDINoteCommand] = noteRouter.panic(bindings: noteBindings)
        if !commands.isEmpty { performNotes(commands) }
        lastMessage = Self.panicText + "."
        updateClient()
        announce(Self.panicText)
    }

    /// No key down and no press remembered (tests and the DEBUG probe).
    var isNoteRouterIdle: Bool { noteRouter.isIdle }

    /// The bound trigger keys that are down.
    var heldKeyCount: Int { noteRouter.down.count }
}
