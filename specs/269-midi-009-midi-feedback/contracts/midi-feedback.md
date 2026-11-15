# Contract: MIDI-009 MIDI Feedback

## F1 Options (package)

- `MIDIMappingOptions.feedback`; segments order `curve=`, `invert=1`, `hires=1`, `fb=1`, unknown. `summary` adds ", feedback".

## F2 Quantizer (package)

- `MIDIFeedbackQuantizer.code(for value: Double, binding: MIDIControlBinding, descriptor: ParameterDescriptor, preferring known: UInt16?) -> UInt16?`: nil unless continuous and finite; else the code (0…127 or 0…16383 when `isHighResolution`) whose mapped value is nearest (research D2).

## F3 Engine (package)

- `MIDIFeedbackEngine(limits:)`, `Limits` (`minimumInterval` 33 333 333 ns, `maxMessagesPerTick` 16, `echoWindow` 100 000 000 ns).
- `configure(bindings: MIDIBindingList)`: tracks bindings with `options.feedback`; new controls start with known = nil.
- `incomingApplied(_ values: [ParameterID: Double], registry:, now:)`: known = quantised value, pending cleared, echo window opened.
- `filterEchoes(_ events: [MIDIEvent], now:) -> [MIDIEvent]`: drops CCs equal to a byte sent within the echo window (once each).
- `tick(values: [ParameterID: Double], registry:, now:) -> [MIDIFeedbackMessage]`: updates pending codes, then emits per R4-R6 (14-bit: coarse then fine).
- `resync()`: known = nil for every control (next tick sends current state). `absorb(values:registry:)`: pending cleared, known = current codes (panic).
- `sentCount`: messages emitted (tests, DEBUG).

## F4 Routing (package)

- `MIDIFeedbackRouting.destinations(in list: MIDIEndpointList) -> Set<MIDIEndpointID>` (research D5).

## F5 Output (package)

- `protocol MIDIFeedbackOutput: AnyObject { func send(_ messages: [MIDIFeedbackMessage], to destinations: Set<MIDIEndpointID>) }`.
- `RecordingMIDIFeedbackOutput` keeps every call (mock). `CoreMIDIFeedbackOutput` (Apple platforms) sends UMP MIDI 1.0 words (`MIDIFeedbackUMP.word(_:)`).

## F6 App

- `MIDIMappingCoordinator.setFeedback(_:for:)`: saves at once, announces "<name> feedback on." / "… off." on `.midi`, no Undo.
- `MIDIMappingCoordinator.feedbackTick()`: called by `MIDIInputCoordinator` after every drain; no work when no binding has feedback.
- `feedbackOutput: MIDIFeedbackOutput` (CoreMIDI in the app, a recording output in tests and under `-uitestFakeMIDI`), `feedbackValues: () -> [ParameterID: Double]` (base glow values).
- Options screen: Toggle "Send feedback", identifier `midiFeedback`.
