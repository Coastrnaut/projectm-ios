// MIDIMappingCoordinator+Notes.swift — MIDI-006 note triggers in the mapping coordinator (MIDI-006-R3 to R9;
// specs/143-midi-006-note-triggers, contract N4, research MIDI-006-D2 to D5).
//
// * Learn: `startLearningNote(_:)` arms the note session (cancelling a CC learn: one session at a time); the first
//   key press (note on, velocity > 0) in a batch binds it and ends learn mode. The learning press fires nothing and
//   its later release is ignored by the router (the key was never down there). Cancel, the 30 s timeout and the
//   input stopping are MIDI-003's.
// * Triggers: every batch goes through `MIDINoteRouter` (edges only, velocity 0 = release); its commands go to
//   `performNotes`. Triggers announce nothing here: the actions announce on their own lanes (cue, status events).
// * Stuck notes (MIDI-006-R6): held keys are released when the input stops receiving, when the listed inputs shrink,
//   and when a held binding is deleted, replaced, moved or undone.
// * MIDI-008 (specs/157-midi-008-transport, contract T4): the section is "Transport" (Play/Pause, Play, Pause and the
//   MIDI-006 rows). Learn also accepts a CC button press (controller 0–119, value ≥ 64) and real-time Start/Continue/Stop
//   (not on the hold row); the learned press is registered in the router's press filter so its duplicate copies fire
//   nothing (research MIDI-008-D7). A CC learned as a button leaves the MIDI-003 list (one action per control, D6).
import Foundation
import PerformanceControl

/// One row of the "Note triggers" section (contract N4).
struct MIDINoteRow: Identifiable, Equatable {
    let target: MIDINoteTarget
    /// "Note C4 · Ch 1"; nil when not mapped.
    let control: String?
    let isLearning: Bool

    var id: String { target.id }
    var name: String { target.title }

    /// "Next cue, note C4, channel 1" / "Next cue, not mapped"
    var accessibilityLabel: String {
        guard let control else { return name + ", not mapped" }
        let spoken: String = control.replacingOccurrences(of: "Note ", with: "note ")
        return name + ", " + spoken.replacingOccurrences(of: " · Ch ", with: ", channel ")
    }
}

extension MIDIMappingCoordinator {
    static let noteFooterText: String = "Learn waits up to 30 seconds for a key or pad (a note), a button that sends a control change (pressed at 64 or more, released below 64) or MIDI Start, Continue or Stop. Rows act when the key or button goes down; Black out while held is black only while it is held. Repeated copies of one press act once. Play/Pause, Play and Pause control the visualizer's Pause."

    /// "Note C4 · Ch 1" (channels shown 1–16).
    static func noteText(_ key: MIDIControlKey) -> String {
        let channel: Int = Int(key.channel) + 1
        return "Note " + MIDIEventText.noteName(key.number) + " · Ch " + String(channel)
    }

    /// "note C4 on channel 1"
    static func spokenNote(_ key: MIDIControlKey) -> String {
        let channel: Int = Int(key.channel) + 1
        return "note " + MIDIEventText.spokenNoteName(key.number) + " on channel " + String(channel)
    }

    /// "Press a key or pad on your MIDI device to map Next cue"
    static func noteLearnPrompt(_ target: MIDINoteTarget) -> String {
        "Press a key or pad on your MIDI device to map " + target.title
    }

    /// MIDI-008: "Note C4 · Ch 1", "CC 20 · Ch 1", "MIDI Start", "MIDI Stop".
    static func triggerText(_ key: MIDIControlKey) -> String {
        switch key.kind {
        case .start: return "MIDI Start"
        case .stop: return "MIDI Stop"
        case .controlChange: return controlText(key)
        default: return noteText(key)
        }
    }

    /// MIDI-008: "note C4 on channel 1", "CC button 20 on channel 1", "MIDI Start", "MIDI Stop".
    static func spokenTrigger(_ key: MIDIControlKey) -> String {
        switch key.kind {
        case .start, .stop: return triggerText(key)
        case .controlChange:
            let channel: Int = Int(key.channel) + 1
            return "CC button " + String(key.number) + " on channel " + String(channel)
        default: return spokenNote(key)
        }
    }

    var noteRows: [MIDINoteRow] {
        MIDINoteTarget.all.map { (target: MIDINoteTarget) -> MIDINoteRow in
            let key: MIDIControlKey? = noteBindings.binding(for: target)?.key
            let control: String? = key.map { (key: MIDIControlKey) -> String in Self.triggerText(key) }
            return MIDINoteRow(target: target, control: control, isLearning: learningNoteTarget == target)
        }
    }

    /// Sends the router's commands to `performer` (it holds only weak references to the show and the display).
    func connectNoteActions(_ performer: MIDINoteActionPerformer) {
        performNotes = { (commands: [MIDINoteCommand]) -> Void in performer.perform(commands) }
    }

    // MARK: Learning

    func startLearningNote(_ target: MIDINoteTarget) {
        guard canLearn else { return }
        if isLearning { cancelLearningSilently() }
        noteSession.start(target: target, now: clock())
        setLearningNoteTarget(target)
        lastMessage = nil
        cancelTimeout?()
        cancelTimeout = scheduler(MIDILearnSession<MIDINoteTarget>.timeoutNanoseconds) { [weak self] () -> Void in self?.timeoutFired() }
        announce(Self.noteLearnPrompt(target) + ".")
        updateClient()
    }

    /// Ends any learn session without a message (a new learn replaces it).
    private func cancelLearningSilently() {
        _ = noteSession.cancel()
        cancelCCLearnSession()
        endLearning()
    }

    func deleteNoteMapping(_ target: MIDINoteTarget) {
        let before: MIDINoteBindingList = noteBindings
        var after: MIDINoteBindingList = noteBindings
        guard after.remove(target: target) != nil else { return }
        releaseNotes(changedFrom: before, to: after)
        noteBindings = after
        rememberUndo(cc: bindings, notes: before)
        listChanged()
    }

    // MARK: Receiving

    /// Note learn first (the learning press is consumed), then the router on the rest of the batch. Returns the
    /// learning press's index (MIDI-007: scene routing skips it too).
    @discardableResult
    func receiveNotes(_ batch: [MIDIEvent]) -> Int? {
        let allowsRealTime: Bool = noteSession.target?.mode != .hold   // MIDI-008: real-time has no release
        let eligible: (MIDIEvent) -> Bool = { (event: MIDIEvent) -> Bool in
            MIDILearnEligibility.isTriggerEligible(event, allowsRealTime: allowsRealTime)
        }
        guard noteSession.isLearning, let outcome = noteSession.handle(batch, now: clock(), isEligible: eligible) else {
            route(batch[...])
            return nil
        }
        switch outcome {
        case let .bound(learned, target, eventIndex):
            let event: MIDIEvent = batch[eventIndex]
            let key: MIDIControlKey = event.triggerKey ?? learned   // Continue learns as Start
            route(batch[..<eventIndex])
            bindNote(key, to: target)
            if noteBindings.binding(forKey: key) != nil { noteRouter.registerPress(key, timestamp: event.timestamp) }
            route(batch[(eventIndex + 1)...])
            return eventIndex
        case .timedOut:
            finishTimedOut()
            route(batch[...])
        case .cancelled:
            route(batch[...])
        }
        return nil
    }

    private func route(_ events: ArraySlice<MIDIEvent>) {
        guard !events.isEmpty, !noteBindings.isEmpty || noteRouter.hasKeysDown else { return }
        let commands: [MIDINoteCommand] = noteRouter.route(Array(events), bindings: noteBindings)
        if !commands.isEmpty { performNotes(commands) }
    }

    private func bindNote(_ key: MIDIControlKey, to target: MIDINoteTarget) {
        let before: MIDINoteBindingList = noteBindings
        var after: MIDINoteBindingList = noteBindings
        let outcome: MIDINoteBindOutcome = after.bind(key, to: target)
        endLearning()
        let mapped: String = target.title + " mapped to " + Self.spokenTrigger(key)
        let scenesBefore: MIDISceneBindingList = sceneBindings
        let ccBefore: MIDIBindingList = bindings
        switch outcome {
        case .full:
            lastMessage = Self.fullText
            announce(Self.fullText)
            updateClient()
            return
        case let .moved(from), let .movedAndReplaced(from, _):
            lastMessage = mapped + " (moved from " + from.title + ")."
        case .added, .replaced:
            lastMessage = mapped + "."
            if let freed = sceneBindings.remove(key: key) {   // MIDI-007-R8: one action per note
                lastMessage = mapped + " (moved from " + sceneTitle(freed.sceneID) + ")."
            }
            if let parameter = freeControlBinding(key) {   // MIDI-008-R6: a CC is a button or a parameter control
                lastMessage = mapped + " (moved from " + name(of: parameter) + ")."
            }
        }
        releaseNotes(changedFrom: before, to: after)
        noteBindings = after
        if before != after || scenesBefore != sceneBindings || ccBefore != bindings {
            rememberUndo(cc: ccBefore, notes: before, scenes: scenesBefore)
        }
        announce(lastMessage ?? mapped)
        listChanged()
    }

    // MARK: Stuck notes (MIDI-006-R6)

    /// Releases every held key (input stopped, an input went away).
    func releaseAllNotes() {
        guard noteRouter.hasKeysDown else { return }
        let commands: [MIDINoteCommand] = noteRouter.releaseAll(bindings: noteBindings)
        if !commands.isEmpty { performNotes(commands) }
    }

    /// Releases the held keys whose binding differs between two lists (deleted, replaced, moved, undone), using the
    /// old list so a hold releases the action it engaged.
    func releaseNotes(changedFrom old: MIDINoteBindingList, to new: MIDINoteBindingList) {
        let changed: [MIDIControlKey] = noteRouter.down.filter { (key: MIDIControlKey) -> Bool in
            old.binding(forKey: key)?.target != new.binding(forKey: key)?.target
        }
        guard !changed.isEmpty else { return }
        let commands: [MIDINoteCommand] = noteRouter.release(keys: changed, bindings: old)
        if !commands.isEmpty { performNotes(commands) }
    }

    /// Called on every input state change: release all when the input stops or a listed input disappears.
    func releaseNotesIfInputChanged() {
        let sources: Set<MIDIEndpointID> = input.listedSources
        let lost: Bool = !lastSources.isSubset(of: sources)
        lastSources = sources
        if !input.isReceiving || lost { releaseAllNotes() }
    }
}
