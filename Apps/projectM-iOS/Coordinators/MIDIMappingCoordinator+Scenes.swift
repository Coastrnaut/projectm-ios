// MIDIMappingCoordinator+Scenes.swift — MIDI-007 scene selection in the mapping coordinator (MIDI-007-R1, R2, R6 to
// R10; specs/147-midi-007-scene-selection, contract S4, research MIDI-007-D3 to D6).
//
// * Learn: `startLearningScene(_:)` arms the scene session (cancelling any other learn: one session at a time); the
//   first program change or key press (note on, velocity > 0) in a batch binds it and ends learn mode. That message is
//   removed from the batch before notes and scenes are routed, so it selects nothing and fires no MIDI-006 trigger.
//   Cancel, the 30 s timeout and the input stopping are MIDI-003's.
// * A learned note leaves MIDI-006's list (one action per note); a scene keeps one key (program or note).
// * Routing: `MIDISceneRouter` gives the batch's newest command; `performScenes` (a `MIDISceneActionPerformer`) applies
//   it, debounced on the current scene. Nothing here saves on a selection (MIDI-007-R3).
// * Announcements (learn, result, timeout) go through the injected `.midi` announcer.
import Foundation
import PerformanceControl

/// One row of the "Scene triggers" section (contract S4).
struct MIDISceneRow: Identifiable, Equatable {
    let sceneID: String
    /// The scene's name, or "Scene not found" when no cue shows it.
    let name: String
    /// "Program 5 · Ch 1" or "Note C4 · Ch 1".
    let control: String

    var id: String { sceneID }

    /// "Drop, program 5, channel 1"
    var accessibilityLabel: String {
        let spoken: String = control.replacingOccurrences(of: "Program ", with: "program ")
            .replacingOccurrences(of: "Note ", with: "note ")
        return name + ", " + spoken.replacingOccurrences(of: " · Ch ", with: ", channel ")
    }
}

extension MIDIMappingCoordinator {
    static let sceneNotFoundText: String = "Scene not found."
    static let sceneNotFoundName: String = "Scene not found"
    static let sceneFullText: String = "No more scene mappings fit (128). Delete one first."
    static let sceneFooterText: String = "Assign MIDI… on a cue in Settings › Show learns the next program change or key for its scene. A trigger for the scene already showing does nothing. Program number selects cue: program 0 selects cue 1, program 1 cue 2, and so on; a program mapped to a scene takes precedence. Bank select is not used."

    /// "Program 5 · Ch 1" or "Note C4 · Ch 1" (programs 0–127 as the MIDI Monitor shows them; channels 1–16).
    static func sceneControlText(_ key: MIDIControlKey) -> String {
        guard key.kind == .programChange else { return noteText(key) }
        let channel: Int = Int(key.channel) + 1
        return "Program " + String(key.number) + " · Ch " + String(channel)
    }

    /// "program 5 on channel 1" or "note C4 on channel 1"
    static func spokenSceneControl(_ key: MIDIControlKey) -> String {
        guard key.kind == .programChange else { return spokenNote(key) }
        let channel: Int = Int(key.channel) + 1
        return "program " + String(key.number) + " on channel " + String(channel)
    }

    /// The scene's name for texts ("Scene not found" when no cue shows it).
    func sceneTitle(_ sceneID: String) -> String { sceneDisplayName(sceneID) ?? Self.sceneNotFoundName }

    /// "Send a program change or press a key on your MIDI device to map Drop"
    func sceneLearnPrompt(_ sceneID: String) -> String {
        "Send a program change or press a key on your MIDI device to map " + sceneTitle(sceneID)
    }

    var sceneRows: [MIDISceneRow] {
        sceneBindings.bindings.map { (binding: MIDISceneBinding) -> MIDISceneRow in
            MIDISceneRow(sceneID: binding.sceneID, name: sceneTitle(binding.sceneID), control: Self.sceneControlText(binding.key))
        }
    }

    /// The scene's mapped control ("Program 5 · Ch 1"); nil when not mapped.
    func sceneControl(for sceneID: String) -> String? {
        sceneBindings.binding(forScene: sceneID).map { (binding: MIDISceneBinding) -> String in Self.sceneControlText(binding.key) }
    }

    /// Sends scene commands to `performer` (it holds only a weak reference to the show).
    func connectSceneActions(_ performer: MIDISceneActionPerformer) {
        performScenes = { (command: MIDISceneCommand) -> Void in performer.perform(command) }
    }

    // MARK: Learning

    func startLearningScene(_ sceneID: String) {
        guard canLearn, MIDISceneBinding.isValidSceneID(sceneID) else { return }
        if isLearning {
            _ = noteSession.cancel()
            cancelCCLearnSession()
            endLearning()
        }
        sceneSession.start(target: sceneID, now: clock())
        setLearningSceneID(sceneID)
        lastMessage = nil
        cancelTimeout?()
        cancelTimeout = scheduler(MIDILearnSession<String>.timeoutNanoseconds) { [weak self] () -> Void in self?.timeoutFired() }
        announce(sceneLearnPrompt(sceneID) + ".")
        updateClient()
    }

    func deleteSceneMapping(_ sceneID: String) {
        let before: MIDISceneBindingList = sceneBindings
        guard sceneBindings.remove(sceneID: sceneID) != nil else { return }
        rememberUndo(cc: bindings, notes: noteBindings, scenes: before)
        listChanged()
    }

    /// MIDI-007-R6: saved at once, no Undo entry (as MIDI-004's curve picker).
    func setProgramCueMode(_ mode: MIDIProgramCueMode) {
        guard sceneBindings.programCueMode != mode else { return }
        sceneBindings.programCueMode = mode
        save()
        updateClient()
    }

    // MARK: Receiving

    /// Scene learn: binds the first eligible message and returns the batch without it; otherwise the batch.
    func receiveSceneLearn(_ batch: [MIDIEvent]) -> [MIDIEvent] {
        guard sceneSession.isLearning,
              let outcome = sceneSession.handle(batch, now: clock(), isEligible: MIDILearnEligibility.isSceneEligible) else { return batch }
        switch outcome {
        case let .bound(key, sceneID, eventIndex):
            bindScene(key, to: sceneID)
            var rest: [MIDIEvent] = batch
            rest.remove(at: eventIndex)
            return rest
        case .timedOut:
            finishTimedOut()
            return batch
        case .cancelled:
            return batch
        }
    }

    /// Routes the batch (minus a note learning press) and performs its newest scene command.
    func routeScenes(_ batch: [MIDIEvent], skipping consumed: Int?) {
        guard !sceneBindings.isEmpty else { return }
        var events: [MIDIEvent] = batch
        if let consumed, consumed < events.count { events.remove(at: consumed) }
        guard let command = MIDISceneRouter.route(events, list: sceneBindings) else { return }
        performScenes(command)
    }

    private func bindScene(_ key: MIDIControlKey, to sceneID: String) {
        let scenesBefore: MIDISceneBindingList = sceneBindings
        let notesBefore: MIDINoteBindingList = noteBindings
        let outcome: MIDISceneBindOutcome = sceneBindings.bind(key, to: sceneID)
        endLearning()
        let mapped: String = sceneTitle(sceneID) + " mapped to " + Self.spokenSceneControl(key)
        switch outcome {
        case .full:
            lastMessage = Self.sceneFullText
            announce(Self.sceneFullText)
            updateClient()
            return
        case let .moved(fromScene), let .movedAndReplaced(fromScene, _):
            lastMessage = mapped + " (moved from " + sceneTitle(fromScene) + ")."
        case .added, .replaced:
            lastMessage = mapped + "."
            if key.kind == .noteOn, let trigger = noteBindings.binding(forKey: key)?.target {   // one action per note
                var after: MIDINoteBindingList = noteBindings
                after.remove(target: trigger)
                releaseNotes(changedFrom: noteBindings, to: after)
                noteBindings = after
                lastMessage = mapped + " (moved from " + trigger.title + ")."
            }
        }
        if scenesBefore != sceneBindings || notesBefore != noteBindings {
            rememberUndo(cc: bindings, notes: notesBefore, scenes: scenesBefore)
        }
        announce(lastMessage ?? mapped)
        listChanged()
    }
}
