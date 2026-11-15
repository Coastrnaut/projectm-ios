# ADR-0080: MIDI Feedback Sends Bounded Control Changes to Paired Local Destinations

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: MIDI-009 (`specs/269-midi-009-midi-feedback`)
- **Constitution**: I (public APIs only), VI (modular boundaries); Platform, Security & Privacy
- **Amends**: ADR-0038 (until now projectM only listed destinations and never sent a MIDI message)

## Context

MIDI-009 sends a mapped parameter's state back to controllers with LED rings or motor faders. ADR-0038 kept MIDI local
and receive-only; messages carry no source (Decision 7), and bindings store no device (Decision 8).

## Decision

1. **Opt-in per mapping.** Feedback is off by default and turned on per `cc:` mapping with the segment `fb=1`; no new
   UserDefaults key and no device identifier is stored.
2. **Local, paired destinations only.** Feedback goes to online destinations from MIDI-001's list (so never network
   MIDI) that belong to the same device as a listened online input, or to a virtual destination named like a listened
   virtual input. No destination picker; unrelated synths receive nothing.
3. **Public output API.** A separate CoreMIDI client and one output port (`MIDIOutputPortCreate`), kept for the
   process, sending MIDI 1.0 Universal MIDI Packets with `MIDISendEventList`. `MIDINetworkSession` and the other network
   MIDI classes stay forbidden (`check_compliance.py`, `check_network_symbols.py`).
4. **Bounded and loop-free.** Only changes of the quantised 7- or 14-bit value are sent, at most 30 per second per
   control (coalesced), at most 16 messages per 30 Hz tick; a value from the controller is never echoed (100 ms quiet
   window) and a device's echo of a sent byte is dropped. Base values only: audio and LFO modulation are never sent.
5. **Runs only while receiving.** Feedback is driven by the shared input's drain tick, so it stops with listening off,
   in the background and when no mapping exists; MIDI panic drops pending feedback.

## Consequences

- Nothing about devices persists and nothing is logged; the privacy manifest and permission catalog are unchanged
  (sending to a local MIDI destination needs no permission).
- A physical check with a motorised or LED controller is the `{device}` task MIDI-009-T15.
