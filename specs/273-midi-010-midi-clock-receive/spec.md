# Feature Specification: MIDI-010 MIDI Clock Receive

**Feature Branch**: `feature/midi-010` (spec directory `273-midi-010-midi-clock-receive`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement MIDI-010 (MIDI clock receive) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable
behavior, verbatim: "Sync show tempo to external MIDI clock when available." Acceptance, verbatim: "24 pulses per quarter
note yield correct BPM within tolerance." Priority P2, effort L, depends on MIDI-001 (integrated)."

Identifiers carry the roadmap ID: requirements `MIDI-010-R1…`, success criteria `MIDI-010-S1…`, research decisions
`MIDI-010-D1…`, tasks `MIDI-010-T01…`. Other features are cited by their own IDs: MIDI-001 (discovery), MIDI-002 (input,
decoders and ring), MIDI-008 (transport mapping), MIDI-011 (hot-plug), SHOW-011 (tempo source), SHOW-010 (beat grid),
ANL-005/ANL-006 (tempo estimate and confidence), MOD-009 (tempo-synced LFO), VIS-015 (tunnel), MED-006 (slideshow).

## Baseline: what exists today (audit of 2026-11-14, branch point `459ffdaf`)

| Area | Today |
|---|---|
| Decoding | MIDI-002's UMP decoder (type 0x1 system words) and byte-stream parser already turn Timing Clock 0xF8, Start 0xFA, Continue 0xFB, Stop 0xFC and Song Position 0xF2 into `.clock`, `.start`, `.continue`, `.stop`, `.songPosition` events with monotonic nanosecond timestamps (the CoreMIDI input converts host time; 0 → arrival). |
| Ring | The shared 512-event ring stores Start/Continue/Stop/Song Position; Timing Clock is only **counted** (MIDI-002-R4), so its timestamps never reach the main actor. |
| Transport | MIDI-008 lets a learned `rt:start` / `rt:stop` line drive Play/Pause; nothing follows the clock. |
| Tempo | SHOW-011 `TempoSource` → `TempoSnapshot` (origin manual or estimated, BPM, period, anchor). Manual tap wins; else the ANL-005 estimate at confidence ≥ 0.5. `TempoCoordinator` publishes it; SHOW-010 beat grid, MOD-009 LFOs, VIS-015 tunnel, ACC-007 haptics, MED-006 slideshow and the scene HUD read it. SHOW-011's hand-off names MIDI-010 as "another override kind beside manual". |
| Settings | MIDI section: Listen toggle, status, Monitor, Mappings, Panic, endpoint rows. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9).

- Q: Is following the clock on by default? → A: No. A "Follow MIDI clock" toggle in Settings → MIDI, off by default, stored as `settings.midi.followClock` (excluded from library backups as this device's MIDI setup, like "Listen for MIDI devices"; erased with Settings). While it is off nothing reads the clock and the tempo behaves exactly as today.
- Q: Where does the clock rank among tempo sources? → A: A locked MIDI clock (with the toggle on) outranks the manual tap and the estimate. A tap while the clock is locked is still recorded but the clock keeps the tempo; the app announces "MIDI clock is setting the tempo". When the clock is lost, the tempo falls back at once to the manual tempo if one was tapped, else to the estimate.
- Q: How is the BPM measured? → A: 24 pulses per quarter note; BPM = 60 / (24 × pulse period). The period is the least-squares slope of pulse time against pulse number over the last 96 pulses (4 beats), so jitter averages out. Locked after 24 consistent pulses (one beat). Shown with one decimal ("120.0 BPM").
- Q: Jitter, dropped pulses and outliers? → A: Against the current period, an interval below 0.6 periods is an outlier (ignored); 0.6–1.5 periods is one pulse; 1.5–4.5 periods is that many pulses with the missing ones counted (so the beat count stays right); longer restarts acquisition. Six outliers in a row restart acquisition (a big tempo jump).
- Q: Tempo changes? → A: When the fit over the last 24 pulses differs by more than 2 % from the full window's, the window is cut to those 24 pulses, so a step change converges within about 2 beats; small drifts follow the sliding window.
- Q: When is the clock lost? → A: No pulse for 0.5 s, or a Stop message. After Stop the clock does not set the tempo until Start or Continue (the show follows the master's transport); pulses received meanwhile keep the measurement warm without moving the beat position, so the tempo returns at once. Losing the clock never changes the stored settings.
- Q: Which tempos are accepted? → A: 20–300 BPM (0.1 BPM allowance for measurement); a clock outside the range is ignored and the status says so ("MIDI clock out of range").
- Q: Beat phase? → A: Start sets the next pulse to position 0 (a downbeat); Song Position (in sixteenths, 6 pulses each) received before Continue sets the position Continue resumes from; Continue without one resumes counting. Every 24th position is a beat; the anchor given to the tempo snapshot is the fitted time of the latest beat pulse. A clock that never sent Start or Continue gives a BPM without phase.
- Q: What does the status row show? → A: "MIDI clock: 120.0 BPM" while locked, "MIDI clock: stopped" after Stop, "MIDI clock: out of range", "No MIDI clock" otherwise, and nothing extra while the toggle is off. The tempo readout's source becomes "MIDI clock" ("120 BPM, MIDI clock" spoken).

### Session 2026-11-14 (speckit-clarify)

Answered by Claude with the recommended option (owner rules 4 and 9).

- Q: Does Start or Stop from the clock source also start or pause the show? → A: No. Following the clock only sets the tempo and beat phase; MIDI-008's learned `rt:start` / `rt:stop` rows stay the only way MIDI Start/Stop act on the show (no hidden second mapping).
- Q: Does following the clock need "Listen for MIDI devices" on? → A: Yes. The clock is read through MIDI-002's shared input, which receives only while discovery listens and the app is active; with listening off the status row says "Turn on Listen for MIDI devices" and the tempo is unchanged.
- Q: How does the tempo readout show the clock? → A: As its own source: "120 BPM" with state "MIDI clock", spoken "120 BPM, MIDI clock"; the scene HUD names the source "MIDI clock"; the Reset button stays hidden while the clock sets the tempo (Reset clears only a tapped tempo). Consumers that accept a manual or stable tempo (beat grid, slideshow) treat the clock like a manual tempo.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The show follows a drum machine's tempo (Priority: P1)

A performer connects a drum machine or DAW that sends MIDI clock, turns on "Follow MIDI clock", and the show's tempo (beat grid, tempo-synced LFOs, quantized cues) follows the clock's BPM and beats.

**Why this priority**: it is the roadmap row.

**Independent Test**: feed 24-PPQN pulses with exact timestamps; the tracker reports the BPM within 0.1 and the tempo snapshot reports it with origin MIDI clock.

**Acceptance Scenarios**:

1. **Given** the toggle is on, **When** a source sends clock at 120 BPM, **Then** the tempo reads 120.0 BPM from MIDI clock within one beat.
2. **Given** the clock is locked, **When** it changes to 140 BPM, **Then** the tempo reads 140 within 4 beats.
3. **Given** the toggle is off, **When** a source sends clock, **Then** the tempo is unchanged.

### User Story 2 - Clock loss and transport (Priority: P2)

**Acceptance Scenarios**:

1. **Given** the clock is locked, **When** pulses stop for 0.5 s or Stop arrives, **Then** the tempo falls back to tap or estimate.
2. **Given** Start then pulses, **Then** the beat anchor lies on pulses 0, 24, 48….

### User Story 3 - See the clock in Settings (Priority: P3)

**Acceptance Scenarios**:

1. **Given** Settings → MIDI, **When** the toggle is turned on and a clock arrives, **Then** the status row reads "MIDI clock: 120.0 BPM".

### Edge Cases

- Jitter of ±1 ms per pulse; a dropped pulse; a duplicated or early pulse.
- A free-running clock with no Start (BPM, no phase).
- Clock below 20 or above 300 BPM.
- The input stops (listening off, app in background): the clock is lost.
- Two sources sending clock at once: the input merges them (MIDI-002 keeps no source); the pulses then look like jitter or outliers and the lock may fail. Documented, not solved.

## Requirements *(mandatory)*

### Functional Requirements

- **MIDI-010-R1**: Timing Clock pulses MUST reach the main actor with their timestamps, in order with Start, Continue, Stop and Song Position, without allocating, locking or logging on the receive thread, and without changing what the MIDI Monitor and other input clients see.
- **MIDI-010-R2**: A pure tracker MUST estimate BPM from 24-PPQN pulses (least squares over up to 96 pulses), lock after 24 consistent pulses, reject outliers, count dropped pulses, and follow tempo changes (window cut on a > 2 % short/long disagreement).
- **MIDI-010-R3**: The tracker MUST lose lock after 0.5 s without a pulse or on Stop, not set the tempo after Stop until Start/Continue (pulses meanwhile keep the measurement warm and do not move the position), and ignore tempos outside 20–300 BPM.
- **MIDI-010-R4**: The tracker MUST count positions from Start (0), Song Position + Continue, or Continue, and give the fitted time of the latest beat (position multiple of 24) as the beat anchor.
- **MIDI-010-R5**: The tempo snapshot MUST report a locked clock (toggle on) with origin MIDI clock, outranking tap and estimate, and fall back to tap, else estimate, when the clock is lost or the toggle turned off.
- **MIDI-010-R6**: Settings → MIDI MUST offer "Follow MIDI clock" (off by default, stored as `settings.midi.followClock`) and, while on, a status row with the clock's state ("Turn on Listen for MIDI devices" while listening is off).
- **MIDI-010-R9**: The tempo readout, its spoken value and the scene HUD MUST name the source "MIDI clock"; consumers that accept a manual tempo accept the clock the same way; MIDI Start/Stop act on the show only through MIDI-008 mappings.
- **MIDI-010-R7**: A tap while the clock sets the tempo MUST announce "MIDI clock is setting the tempo" on the tempo's announcement path.
- **MIDI-010-R8**: The model MUST build and pass its tests on Linux; no permission, usage string or network API; the one new key is listed in every settings-key list.

### Key Entities

- **Clock pulse**: a timestamp (monotonic nanoseconds).
- **Clock tracker**: pulse window, fitted period, lock state, position since Start.
- **Clock tempo**: BPM, beat anchor (optional).

## Privacy review *(Constitution, Privacy)*

- One stored Boolean (`settings.midi.followClock`). No message, timestamp, device or endpoint is stored or logged.
- No permission, network ability or usage string is added; local MIDI only (ADR-0038).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MIDI-010-S1**: Exact 24-PPQN pulses at 60, 90, 120, 174.5 and 300 BPM read within ±0.1 BPM (the row's acceptance).
- **MIDI-010-S2**: Pulses jittered by a seeded ±1 ms at 120 BPM read within ±0.5 BPM.
- **MIDI-010-S3**: A step from 120 to 140 BPM reads within ±0.5 of 140 within 4 beats; a dropped pulse and an early outlier pulse leave the reading within ±0.1 and the beat count correct.
- **MIDI-010-S4**: Stop and a 0.5 s gap unlock; Start resets the position and the anchor falls on every 24th pulse.
- **MIDI-010-S5**: In the app, a fake MIDI source's clock makes the tempo snapshot report the MIDI BPM with the toggle on and leaves it unchanged with the toggle off.
- **MIDI-010-S6**: A UI test turns the toggle on, runs a fake clock and reads "MIDI clock: 120.0 BPM" in under 30 s.
- **MIDI-010-S7**: All repository checks pass; the package tests pass on the host (and Linux in CI).

## Assumptions

- Message timestamps are the source's (CoreMIDI host time); jitter from USB or Bluetooth bridges is a few milliseconds.
- Only one clock master is connected at a time.
- A physical clock source check is the `{device}` task in the last stage; simulator results are never device evidence.
