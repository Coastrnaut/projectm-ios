// MIDIMappingCoordinator+HighResolution.swift — 14-bit mappings in the app (MIDI-005-R5, R6;
// specs/266-midi-005-14-bit-controls, contract H5, research MIDI-005-D4, D5).
//
// * Learn detection: after a learn binds CC 0–31, the fine controller (CC n+32, same channel) later in the learning batch
//   or within 500 ms (the injected clock) sets `hires=1` on that mapping, once. The learning gesture applies no value
//   (MIDI-003-R7): values start with the next coarse message.
// * The options screen's "14-bit control" switch (CC 0–31 only) saves at once.
// * Both announce on the `.midi` lane through the injected announcer and add no Undo step (like MIDI-004's options).
import ParameterGraph
import PerformanceControl

extension MIDIMappingCoordinator {
    /// Whether `target` is mapped to a coarse controller (CC 0–31), so it can be 14-bit.
    func canUseHighResolution(for target: ParameterID) -> Bool {
        guard let key = bindings.binding(for: target)?.key else { return false }
        return key.kind == .controlChange && MIDIHighResolution.isCoarseController(key.number)
    }

    /// "Glow intensity uses 14-bit control (CC 7 and CC 39)."
    static func highResolutionDetectedText(name: String, key: MIDIControlKey) -> String {
        let fine: UInt8 = MIDIHighResolution.fineController(for: key.number) ?? key.number
        return name + " uses 14-bit control (CC " + String(key.number) + " and CC " + String(fine) + ")."
    }

    /// The options screen's switch (MIDI-005-R6): saved at once, announced, no Undo step.
    func setHighResolution(_ enabled: Bool, for target: ParameterID) {
        guard canUseHighResolution(for: target), var options = options(for: target) else { return }
        options.highResolution = enabled
        guard updateOptions(options, for: target) else { return }
        announce(name(of: target) + (enabled ? " 14-bit control on." : " 14-bit control off."))
    }

    /// Arms the learn watch for a binding the learn just made (nothing when the list was full).
    func armHighResolutionWatch(_ key: MIDIControlKey, target: ParameterID) {
        guard bindings.target(for: key) == target else {
            highResolutionWatch.disarm()
            return
        }
        highResolutionWatch.arm(key: key, target: target, now: clock())
    }

    /// Marks the watched mapping 14-bit when `events` hold its fine controller in time (MIDI-005-R5).
    func detectHighResolution(in events: ArraySlice<MIDIEvent>) {
        guard highResolutionWatch.isArmed,
              let found = highResolutionWatch.detect(in: events, now: clock()),
              bindings.target(for: found.key) == found.target,
              var options = options(for: found.target), !options.highResolution else { return }
        options.highResolution = true
        guard updateOptions(options, for: found.target) else { return }
        let text: String = Self.highResolutionDetectedText(name: name(of: found.target), key: found.key)
        lastMessage = text
        announce(text)
    }
}
