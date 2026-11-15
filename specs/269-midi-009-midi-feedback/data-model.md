# Data Model: MIDI-009 MIDI Feedback

- **Feedback flag** (`MIDIMappingOptions.feedback: Bool`): stored as `fb=1` on a `cc:` line; default off (D1).
- **Feedback message** (`MIDIFeedbackMessage`): channel 0–15, controller 0–127, value 0–127; one MIDI 1.0 control change.
- **Control state** (memory only, per feedback binding key): target, 14-bit flag, known code (`UInt16?`, last sent or received), pending code, last send time, echo window end. Created on configure; dropped when the binding loses `fb=1`; known reset to nil on resync.
- **Sent-byte record** (memory only): per (channel, controller) the last value sent and its time; consumed by one matching echo or expired after 100 ms.
- **Paired destinations** (`Set<MIDIEndpointID>`): derived from MIDI-001's list each tick, never stored.

State per control: idle (known = code) → pending (code changed) → sent (rate slot free, cap not reached) → idle; incoming → suppressed (100 ms) → idle.
