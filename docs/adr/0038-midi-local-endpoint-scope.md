# ADR-0038: MIDI Is Local Only: USB, Virtual and System-Connected Endpoints, No Network MIDI

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: MIDI-001 (`specs/107-midi-001-midi-endpoint-discovery`)
- **Constitution**: I (public APIs only), VI (modular boundaries); Platform, Security & Privacy
  (no telemetry, permissions at point of use)
- **Builds on**: FR-068 as amended and ADR-0008 (networking only in the OSC transport folder),
  FILE-012 (binary network-symbol scan), FILE-013 (permission catalog)

## Context

The MIDI rows (MIDI-001 to MIDI-013) need a list of MIDI endpoints with stable IDs. CoreMIDI can
also run MIDI over the network (RTP-MIDI through `MIDINetworkSession`) and pair Bluetooth MIDI
devices (`CABTMIDICentralViewController`, which needs a Bluetooth usage string).

## Decision

1. **Local endpoints only.** projectM lists the sources and destinations CoreMIDI reports for USB
   hardware, virtual endpoints of other apps on the device, and Bluetooth MIDI devices the system
   has already connected. Listing needs no permission.
2. **No network MIDI.** The app never enables, configures or references `MIDINetworkSession`,
   `MIDINetworkHost` or `MIDINetworkConnection`; endpoints attributed to Apple's RTP-MIDI driver
   are hidden. `check_compliance.py` (source) and `check_network_symbols.py` (binary) fail on these
   symbols. Network MIDI would need its own row, an FR-068 amendment and a privacy review.
3. **No Bluetooth pairing yet.** `CABTMIDICentralViewController` and
   `CABTMIDILocalPeripheralViewController` are rejected by `check_compliance.py` until a row adds
   the Bluetooth usage string to FILE-013's catalog with its review.
4. **Stable IDs** come from `kMIDIPropertyUniqueID`; a name-based fallback (FNV-1a 64 plus an
   ordinal) covers a zero or colliding number and is marked so later rows can refuse to persist it.
5. **Nothing about devices persists** in MIDI-001; only the "Listen for MIDI devices" toggle
   (`settings.midi.enabled`, off by default). Mapping rows decide their own persistence.
6. Discovery runs only while the toggle is on and the app is in the foreground; no MIDI messages
   are received in MIDI-001.
7. **Receiving (amended 2026-11-14 by MIDI-002, `specs/125-midi-002-midi-input-monitor`; decided by
   Claude under owner rule 4).** One shared input (`MIDIInputService`, its own CoreMIDI client and
   one port from `MIDIInputPortCreateWithProtocol` with the MIDI 1.0 protocol) receives only while
   listening is on, the app is in the foreground and a feature needs messages (MIDI-002: the open
   MIDI Monitor). It connects exactly the inputs MIDI-001 lists, so network MIDI is never connected.
   The receive block decodes Universal MIDI Packets into a preallocated 512-event ring (drop newest,
   counted) with no allocation, lock or logging; the main actor drains it at display rate. Messages
   carry no source (`connRefCon` nil, no source field), and nothing received is stored or logged.
   MIDI-003 onward reuse the input and its `MIDIEvent` model.
8. **Bindings (amended 2026-11-14 by MIDI-003, `specs/128-midi-003-midi-learn`; decided by Claude under owner
   rule 4).** A learned binding is keyed by message kind, MIDI channel and controller number only, from any
   connected device; no endpoint ID, unique number or name is stored with it or added to `MIDIEvent`. Reasons:
   Decision 7 keeps no source on messages; fallback IDs (Decision 4) are not stable across reconnects; and the
   mapping list is in the library backup, where a device identifier would fingerprint the user's equipment.
   Learn accepts control change on controllers 0–119 only (channel mode messages 120–127 are commands). The
   list is global (not per scene), at most 64 bindings, one per control and one per parameter (rebinding
   replaces), stored as text lines in `settings.midi.mappings`, backed up (FILE-005) and erased with Settings
   (FILE-011). Received values set the live manual value of the native glow parameters, pass MOD-002 and the
   ACC-012 clamp, and are never stored. Per-device profiles are MIDI-012's.
9. **Profiles (amended 2026-11-14 by MIDI-012, `specs/171-midi-012-profiles`; decided by Claude under owner rule 4).**
   A mapping profile may be linked to one input by its system unique number only (never a fallback ID, never a name).
   The link stays in the local profiles file (`Application Support/MIDIProfiles/profiles.json`), is never exported
   (`.pmmidi` documents hold the name and the mapping lines only) and is never in a library backup (FILE-005 does not
   carry the profiles file; FILE-011's Settings category erases it). A listed linked input only suggests its profile;
   applying stays the user's action.

## Consequences

- MIDI-002 onward build on `MIDIEndpointDiscovery` and `MIDIEndpointID`; MIDI-003 onward also on
  MIDI-002's shared input and `MIDIEvent` (Decision 7).
- A physical controller check of receiving (MIDI-002-T20) is a device task.
- MIDI-004 onward extend a binding (range, curve, inversion, 14-bit, notes) without changing its key (Decision 8);
  a physical controller check of learn (MIDI-003-T17) is a device task.
- A physical controller check (MIDI-001-S8) remains a device task; the driver-owner strings used
  for attribution are confirmed there.
