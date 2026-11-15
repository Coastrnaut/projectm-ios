# Research: MIDI-005 MIDI 14-bit Controls

## MIDI-005-D1: Store the flag as a MIDI-004 option segment

- **Decision**: `hires=1` after `curve=` and `invert=1` and before unknown segments on the `cc:` line; absent means
  7-bit. Read like `invert=` (first one wins, later repeats dropped).
- **Rationale**: MIDI-004 already keeps unknown segments verbatim, so older builds keep the flag (and drive the coarse
  controller as 7-bit), profiles (MIDI-012) copy lines verbatim, and lines without the flag stay byte-identical. No
  new UserDefaults key, so backup, erase and the key lists are unchanged.
- **Alternatives**: a new line kind (`cc14:`; older builds would drop the mapping as unread); a separate key (one more
  key in every list, and a second source of truth).

## MIDI-005-D2: Value rule (MIDI 1.0)

- **Decision**: value = (MSB × 128 + LSB) / 16383. A coarse message sets MSB and resets LSB to 0; a fine message sets
  LSB under the last MSB; a fine message before any coarse one gives no value. Coarse first, no reordering window.
- **Rationale**: the MIDI 1.0 specification says a new MSB resets the LSB, and every 14-bit controller sends coarse
  first. 0/0 → 0 and 127/127 → 1 exactly, so MIDI-004's ends stay exact.
- **Alternatives**: keep the last LSB on a new MSB (a fader moving up across a coarse step would briefly jump by up to
  127/16383); an order-independent window (delays values and needs a timer).

## MIDI-005-D3: 7-bit fallback

- **Decision**: per channel and coarse controller, a "fine seen" bit. Until it is set, coarse messages read value / 127;
  afterwards (for the session) MSB × 128 / 16383 plus the fine part.
- **Rationale**: a mapping flagged 14-bit by hand on a controller that sends only coarse messages would otherwise top
  out at 16256/16383 (0.992) and never reach the maximum. The bit is memory only (like live values).
- **Alternatives**: a timeout after which the pair falls back (needs a clock per message and changes the scale
  mid-gesture).

## MIDI-005-D4: "When supported" = learn detection plus a manual switch

- **Decision**: after a learn binds controller n (0–31), a watch looks for controller n+32 on the same channel later
  in the learning batch or in batches up to 500 ms after the learning message (the coordinator's injected clock), then
  sets the flag once and disarms. The options screen offers a "14-bit control" switch for controllers 0–31.
- **Rationale**: real 14-bit controllers send both messages back to back (well under one display tick), so detection
  is reliable without user knowledge; the switch covers devices that send fine messages only after movement settles
  and lets the user turn pairing off. Controllers 32–63 can still be learned and bound as 7-bit controls.
- **Alternatives**: manual switch only (users rarely know their controller's CC layout); detection only (no way to
  undo a false detection).

## MIDI-005-D5: Announcements

- **Decision**: detection: "<name> uses 14-bit control (CC n and CC n+32)." after the mapped announcement, also the
  status text; switch: "<name> 14-bit control on." / "… off.". Both on the `.midi` lane; neither is an Undo step.
- **Rationale**: matches MIDI-004's options announcements (immediate save, no Undo entry).

## MIDI-005-D6: MIDI 2.0 UMP out of scope

- **Decision**: no change to `MIDIUMPDecoder`; message type 0x4 stays skipped.
- **Rationale**: the input port is created with the MIDI 1.0 protocol (MIDI-002-D1), so the system translates MIDI 2.0
  sources to MIDI 1.0 messages before the app sees them. Handling 32-bit values would need a MIDI 2.0 port first.
