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

## Consequences

- MIDI-002 onward build on `MIDIEndpointDiscovery` and `MIDIEndpointID`.
- A physical controller check (MIDI-001-S8) remains a device task; the driver-owner strings used
  for attribution are confirmed there.
