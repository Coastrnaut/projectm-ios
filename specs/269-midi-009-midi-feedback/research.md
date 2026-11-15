# Research: MIDI-009 MIDI Feedback

All decisions by Claude under owner rules 4 and 9 (2026-11-14).

## MIDI-009-D1: Opt-in storage

- **Decision**: `fb=1` segment on the `cc:` line, after `hires=1`, before unknown segments; first occurrence wins, like `invert=` and `hires=`.
- **Rationale**: Options follow the parameter (MIDI-004-R6), profiles copy lines verbatim (MIDI-012), backup and erase need no change, and older builds keep it as an unknown segment.
- **Alternatives**: a global "Send MIDI feedback" key (new UserDefaults key, all-or-nothing; rejected); per-profile flag (profiles are snapshots of lines, so per-line covers it).

## MIDI-009-D2: Parameter value → controller value

- **Decision**: Binary search over the controller codes (0…127, or 0…16383 for 14-bit) of the forward mapping `MIDIBindingValues.value(normalized: code / max, …)`, which is monotonic (non-decreasing, or non-increasing when inverted; every MOD-004 curve is non-decreasing). Pick the code whose mapped value is nearest; on a tie or a flat run, keep the controller's known code when its mapped value equals the nearest one, else the lowest such code.
- **Rationale**: Exact round trip for every code with any curve (the incoming value maps to the same code), handles non-invertible flat piecewise segments without special cases, no analytic inverse per curve kind, at most 14 evaluations.
- **Alternatives**: closed-form inverse per curve (no inverse for flat piecewise segments; rounding drift could echo a neighbour code); a 16384-entry table (memory per mapping).

## MIDI-009-D3: Bounds

- **Decision**: per control a minimum of 1/30 s between sends (33 333 333 ns), coalescing to the newest pending code; send only when the code differs from the known controller code; at most 16 messages per tick (a 14-bit update is 2 messages and is never split across ticks), served round-robin from a rotating start.
- **Rationale**: 30 Hz matches the drain tick and typical LED/motor fader update rates; the cap bounds a burst of 64 mappings (resync) to 16 messages per 33 ms.
- **Alternatives**: a global token bucket only (one busy control could starve others).

## MIDI-009-D4: Loop prevention

- **Decision**: (a) a value applied from the controller sets the control's known code (quantised from the applied parameter value) and an echo window of 100 ms during which nothing is sent for it; pending updates wait until the window ends and are then compared with the known code. (b) A received CC whose (channel, controller, value) equals a byte sent within 100 ms is dropped once. Times from the injected monotonic clock.
- **Rationale**: (a) stops echoing to the sender even with rounding; (b) stops devices that echo from re-applying (it matters for 14-bit, where an echoed coarse byte would reset the fine part). A loopback then settles: a sent value returns, is dropped, nothing changes.
- **Alternatives**: per-source suppression (impossible: messages carry no source, ADR-0038 Decision 7).

## MIDI-009-D5: Destinations

- **Decision**: online, listed (so never network) destinations whose non-empty device name equals the device name of a listed online input; a virtual destination pairs with a virtual input of the same name. Computed from MIDI-001's list each tick while feedback mappings exist; an added destination triggers one resync (R11).
- **Rationale**: Messages have no source; device pairing keeps feedback on controllers the user already connected and away from unrelated synths.
- **Alternatives**: all destinations (would send CCs to every synth); a picker (UI and storage of endpoint IDs, which ADR-0038 Decision 8 avoids).

## MIDI-009-D6: Output API

- **Decision**: a separate CoreMIDI client ("projectM feedback") and `MIDIOutputPortCreate` port created on the first send and kept (Apple advises against disposing CoreMIDI objects on iOS); `MIDISendEventList` with a MIDI 1.0 event list (`MIDIEventListInit(…, ._1_0)`, `MIDIEventListAdd` per message, group 0, word `0x2 << 28 | status << 16 | controller << 8 | value`). Destination IDs map to endpoint references by the same `MIDIEndpointIdentity.assign` rule over the non-network records.
- **Rationale**: Public API, UMP matches the input's protocol, no network.
- **Alternatives**: `MIDISend` with a packet list (deprecated in favour of event lists).

## MIDI-009-D7: When feedback runs

- **Decision**: on the input coordinator's tick (after each 30 Hz drain, also when the batch is empty), so it runs only while the input receives (listening on, foreground, a mapping exists). Panic drops pending updates and takes current codes as known. Base values only: `BloomParameters.applying(externalValues)` of the native host, never MOD-002/MOD-007 layers.
- **Rationale**: background and listening-off stop feedback with no extra state; modulated values cannot flood.
- **Alternatives**: a separate timer (would need its own lifecycle).
