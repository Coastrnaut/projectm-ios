# Feature Specification: MIDI-011 MIDI Hot-Plug Recovery

**Feature Branch**: `feature/midi-011` (spec directory `166-midi-011-hotplug`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement MIDI-011 (MIDI hot-plug recovery) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Reattach matching endpoints without duplicate subscriptions." Acceptance, verbatim:
"Disconnect and reconnect fixture yields one live listener per endpoint." Priority P1, effort M, depends on MIDI-001
(integrated)."

Identifiers carry the roadmap ID: requirements `MIDI-011-R1…`, success criteria `MIDI-011-S1…`, research decisions
`MIDI-011-D1…`, tasks `MIDI-011-T01…`. Other features are cited by their own IDs: MIDI-001 (discovery, stable IDs,
coalescing), MIDI-002 (shared input, ring), MIDI-003/004 (CC mappings), MIDI-006/008 (note and transport triggers,
stuck-key release), ACC-004 (announcer lanes).

## Baseline: what exists today (audit of 2026-11-14, branch point `0fed932a`)

| Area | Today |
|---|---|
| Endpoint identity | MIDI-001 `MIDIEndpointIdentity.assign`: the system's unique number when non-zero and not shared in the snapshot; otherwise a fallback FNV-1a hash of direction, device, entity and endpoint names plus an ordinal. Network endpoints are never listed. |
| Discovery | `MIDIEndpointDiscovery` over `CoreMIDIEndpointProvider` (own client, notify block forwarding setup changed, object added, removed and property changed). Bursts coalesce into one refresh (`MIDIRefreshCoalescer`, 100 ms). An update is delivered only when the listed IDs, names or online flags change. |
| Input | `MIDIInputService` → `CoreMIDIInputProvider`: its own client **without** a notify block, one input port. `connect(sources:)` re-enumerates, maps the requested IDs to current endpoint refs and keeps a list of connected **refs**: a ref already in the list is never reconnected; refs no longer wanted are disconnected. It runs only when the app calls `updateSources`, i.e. after a discovery update. |
| Gaps | (1) An unplug and replug inside one coalescing window leaves the ID list unchanged, so no discovery update and no `connect` call: if the system issued a new ref, the new endpoint is never connected (dead listener); if it kept the ref, the provider believes it is still connected although the system dropped the connection when the source disappeared. (2) Connection bookkeeping is by ref, untestable without CoreMIDI. (3) Discovery announces "MIDI device connected: …" for a returning device; there is no reconnect wording. |
| Stuck keys | MIDI-006-R6 / MIDI-008: `MIDIMappingCoordinator.releaseNotesIfInputChanged()` releases every held key when the input stops or the listed inputs shrink (`lastSources` ⊄ current). |
| Test fakes | `ScriptedMIDIEndpointProvider` (records, plug/unplug/signal bursts) and `ScriptedMIDIInputProvider` (delivers to the ring when any source is connected; no refs, so duplicate subscriptions cannot be observed). DEBUG `-uitestFakeMIDI` panel (Plug/Unplug Fake Keys, Send CC…). `MIDIInputCoordinator.drain()` for tests. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9).

- Q: What identifies "the same endpoint" across a replug? → A: MIDI-001's stable ID, unchanged: the system's unique number, falling back to the name-based ID when the number is missing or shared by two endpoints. The subscription registry is keyed by that ID; the system's endpoint reference is only the current handle and is refreshed whenever it changes.
- Q: Who decides when to reattach? → A: The input itself also follows system setup notifications (added, removed, setup changed), coalesced like MIDI-001 (one reconcile per burst), so a quick unplug and replug that never changes discovery's list is still repaired. Discovery's list stays the source of *which* IDs are wanted.
- Q: What does "one live listener" mean? → A: For every wanted endpoint that is present, exactly one active connection to its current reference; for an absent endpoint, none. A message from an endpoint is delivered once.
- Q: Are held keys released on a quick replug? → A: Yes. Any endpoint the input saw disappear (even briefly) releases held keys through MIDI-008's existing release, because its note-off may have been lost.
- Q: What is announced? → A: When an endpoint that was listed earlier in the same listening session appears again, discovery says "MIDI device reconnected: <name>" instead of "connected", on the `.midi` lane, once per update, following MIDI-001's pattern. Repairs that change no listed endpoint are silent.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: How long does the input wait to reconcile after a setup notification? → A: MIDI-001's coalescing delay (100 ms) and the same coalescer: the first notification of a quiet period schedules one reconcile, later ones are absorbed until it starts; tests use the manual scheduler, never wall time.
- Q: What is "the same listening session" for the reconnect wording? → A: From discovery's start until its stop (toggle off or background). Stopping forgets the endpoints seen, so after a restart a device is "connected" again, as today.
- Q: When a connect call fails, how is it retried? → A: Only by the next reconcile (the next notification or list change); no timer and no retry loop. The endpoint is not counted as connected.
- Q: Is a quick replug that never changes discovery's list announced? → A: No: discovery saw no change, so nothing is spoken; the input still repairs the connection and releases held keys (MIDI-011-R5).
- Q: What does the input expose about its subscriptions? → A: In-memory, read-only counters for tests and the debug fake (active connections by ID, connect and disconnect calls, reconcile count); nothing is logged, stored or shown to the user.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Unplug and replug keeps one listener (Priority: P1) — MVP

A performer's USB controller drops out (cable knocked, hub reset) and comes back. Its mappings keep working after the
replug, and each knob turn or pad press acts once — never twice and never not at all.

**Why this priority**: The row's acceptance.

**Independent Test**: A scripted MIDI system with endpoints A and B. Connect both; remove A; re-add A with a new system
reference and the same unique number; send repeated setup notifications; remove and re-add B twice. After every step:
exactly one active connection per present endpoint and none for absent ones; one message from A is delivered once; keys
held from a removed endpoint are released.

**Acceptance Scenarios**:

1. **Given** A and B are connected, **When** A is removed, **Then** A has no connection, B keeps one, and keys held on the input are released.
2. **Given** A was removed, **When** A returns with a new reference and the same unique number, **Then** A has exactly one connection, on the new reference, and one message from A is delivered once.
3. **Given** A and B are connected, **When** setup notifications repeat with nothing changed, **Then** no connection is made or dropped.
4. **Given** the same, **When** B is removed and re-added twice (including once inside one notification burst), **Then** B ends with exactly one connection on its current reference.

### User Story 2 - A mapped control survives a reconnect (Priority: P1)

**Acceptance Scenarios**:

1. **Given** CC 7 is mapped to a glow parameter from the fake source, **When** the source is unplugged and plugged back, **Then** one CC 7 message changes the parameter once (one event delivered, no double trigger) and a mapped trigger fires once.

### User Story 3 - The user hears that the device is back (Priority: P2)

**Acceptance Scenarios**:

1. **Given** listening is on and Fake Keys was listed, **When** it is unplugged and plugged back, **Then** "MIDI device disconnected: Fake Keys" and then "MIDI device reconnected: Fake Keys" are announced on the `.midi` lane.
2. **Given** a device never listed in this session appears, **Then** the existing "MIDI device connected: …" is announced.

### Edge Cases

- Two endpoints report the same unique number: both use MIDI-001's fallback IDs and are connected separately, each once.
- An endpoint with no unique number: tracked by its fallback ID; a rename changes that ID (MIDI-001's documented risk), which reads as a removal and a new endpoint.
- The system keeps the same reference across a replug: the endpoint was seen absent (removed notification or missing from a snapshot), so its old connection is forgotten and it is connected again exactly once.
- A connect call fails: the endpoint is not counted as connected and the next reconcile (notification or list change) tries again; there is no retry timer.
- A quick replug inside one coalescing window: no announcement (discovery's list did not change), but the connection is repaired and held keys are released.
- Offline endpoints are not wanted (MIDI-002 connects online inputs only); going offline disconnects.
- Listening stops (toggle off, background): every connection is dropped and the registry cleared.
- A storm of notifications: one reconcile per coalescing window.

## Requirements *(mandatory)*

### Functional Requirements

- **MIDI-011-R1**: The input MUST keep a subscription registry keyed by MIDI-001's stable endpoint ID, each entry holding the endpoint's current system reference.
- **MIDI-011-R2**: A reconcile MUST compare the wanted IDs with the system's current sources: connect each wanted, present source without an entry exactly once; when a present source's reference changed, drop the old connection and connect the new reference once; disconnect and forget entries whose source is absent or no longer wanted. No source reference is ever connected twice while its entry is live.
- **MIDI-011-R3**: A source the system reports removed MUST lose its entry (and be reconnected by the next reconcile if it is present again), even when its reference is reused.
- **MIDI-011-R4**: System setup notifications (added, removed, setup changed, property changed) MUST trigger a reconcile coalesced to one per burst with MIDI-001's coalescer and delay (100 ms), off the main thread, never per MIDI message; the real-time receive path is unchanged.
- **MIDI-011-R5**: When the input saw a source disappear, held keys MUST be released through MIDI-008's existing release, even if the source returned before the app observed a list change.
- **MIDI-011-R6**: Discovery MUST announce a returning endpoint (listed earlier in the same listening session: from discovery's start to its stop) as "MIDI device reconnected: <name>" on the `.midi` lane; other announcements are unchanged.
- **MIDI-011-R7**: The system's endpoint enumeration and connect/disconnect calls MUST sit behind a protocol so tests can add, remove and re-add endpoints with changing references and stable unique numbers, and count active connections.
- **MIDI-011-R8**: The reconcile logic MUST be pure Swift and pass its tests on Linux; no new stored key, permission, usage string or network API; nothing about an endpoint is logged or stored.
- **MIDI-011-R9**: The DEBUG fake MIDI input MUST model references and connections, so an app test proves a mapped CC works after a reconnect with no double trigger.

### Key Entities

- **Source snapshot**: the system's current sources: reference, record (unique number, names, direction, offline, transport).
- **Subscription**: stable endpoint ID → current reference (live connection).
- **Reconcile plan**: disconnects and connects that take the registry from its state to the wanted state.

## Privacy review *(Constitution, Privacy)*

- The registry lives in memory only, holds IDs and system references, and is never stored or logged. No permission,
  network ability or stored key is added.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MIDI-011-S1**: In the A/B fixture (connect, remove A, re-add A with a new reference, repeated notifications, B removed and re-added twice), after every step each present wanted endpoint has exactly one active connection, absent ones none, a message from A is delivered exactly once, and held keys from a removed endpoint are released (the row's acceptance).
- **MIDI-011-S2**: Colliding unique numbers fall back to per-endpoint IDs, each connected once.
- **MIDI-011-S3**: A burst of notifications costs one reconcile.
- **MIDI-011-S4**: After 20 unplug/replug cycles the registry and the active connections equal the present endpoints (no growth).
- **MIDI-011-S5**: In the app, a mapped CC changes its parameter once per message after a reconnect, and a returning device is announced as reconnected.
- **MIDI-011-S6**: All repository checks pass and the package tests pass on the host (and Linux in CI).

## Assumptions

- CoreMIDI drops a port's connection to a source when that source is removed; connecting the source's reference again is required after it returns, whether or not the reference changed.
- The ring keeps one producer: CoreMIDI calls one port's receive block on one thread.
- A physical replug check is the `{device}` task in the last stage; simulator results are never device evidence.
