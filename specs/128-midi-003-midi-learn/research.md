# Research: MIDI-003 MIDI Learn

Decisions by Claude under owner rules 4 and 9 (2026-11-14).

## MIDI-003-D1 Binding key: kind, channel, controller; no device

- **Decision**: a binding is `MIDIControlKey` (MIDI-002: kind, channel, number) → `ParameterID`.
  Kind is always control change in this row; it is kept so notes (MIDI-006) and other kinds can be
  learned later without a format change.
- **Rationale**: MIDI-002 events carry no source by design (ADR-0038 Decision 7); adding one would
  undo that row's privacy proof. MIDI-001's fallback IDs (name hash plus ordinal) change when a
  similar device is added, so a per-device binding could silently retarget. A stored device ID would
  also make the mapping list (which is in the library backup) identify the user's equipment.
- **Alternatives**: channel + controller + endpoint ID (needs a source in every event, unstable for
  fallback IDs, privacy cost); per-device profiles (MIDI-012).

## MIDI-003-D2 Rebinding policy: replace, both ways

- **Decision**: `MIDIBindingList.bind(key, to:)` removes any binding with the same key and any
  binding with the same target, then appends. Outcome: `.added`, `.replaced(previousKey)` (the
  target had another control), `.moved(fromTarget)` (the control drove another parameter); both
  can happen at once (`.moved` wins in the status, both are reported). The list never exceeds 64; a
  bind that would exceed it is refused (`.full`).
- **Rationale**: one knob → one parameter and one parameter ← one knob makes "what does this knob
  do" a single answer, keeps MIDI-004's per-binding range and curve unambiguous, and needs no
  dialog with a hand on the controller. Undo covers mistakes.
- **Alternatives**: ask (a dialog during learn); many-to-one or one-to-many (later rows can relax
  the policy; the stored form allows it).

## MIDI-003-D3 Eligibility

- **Decision**: eligible iff `kind == .controlChange && number <= 119`. Controllers 120–127 are
  channel mode messages (MIDI 1.0 specification); clock and active sensing never reach batches
  (MIDI-002 ring counts them); everything else is ignored.
- **Rationale**: the acceptance names CC; channel mode messages are sent by panic buttons and DAWs,
  not by knobs, and binding one would be a trap.

## MIDI-003-D4 Session and timeout on an injected clock

- **Decision**: `MIDILearnSession` is a value: `.idle` or `.learning(target, deadline)`; deadline =
  start + 30 s in monotonic nanoseconds. `handle(_ batch:, now:)` first expires when `now >=
  deadline`, then scans for the first eligible event. The coordinator also schedules an expiry
  through an injected `@MainActor (Duration, @escaping @MainActor () -> Void) -> Cancellable`
  scheduler (a `Task.sleep` in the app; manual in tests), because no batch arrives when nothing is
  sent (MIDI-002 skips empty drains).
- **Rationale**: deterministic tests with no wall-clock waits; the timeout fires even in silence.

## MIDI-003-D5 Values: linear over the full range, newest per batch, learning event skipped

- **Decision**: for each event in the batch with an index other than the learning event's, if its
  key is bound and `normalizedValue` is non-nil, the target's value is `minimum + n × (maximum −
  minimum)` from its continuous descriptor (n clamped to 0…1); later events overwrite earlier ones.
  The result is merged into the coordinator's live values and pushed once per batch. A binding whose
  target is no longer learnable is ignored at load and dropped on the next save.
- **Rationale**: the acceptance is about creating the binding; MIDI-004 replaces the linear map with
  range, curve and inversion per binding. Pushing once per batch bounds the work at 30 Hz.

## MIDI-003-D6 Where values are applied: the host's glow resolution

- **Decision**: `NativeSpectrumHost.externalValues` (parameter ID → value) replaces the glow's
  manual fields (intensity, radius, threshold, knee) inside `resolveEffectiveGlow`, before MOD-002
  modulation (which then modulates around the MIDI value as its manual value) and before
  `SafetyClamp.modulated` and `BloomParameters.limited(by:)` (ACC-012-R4). Setting the property
  re-resolves at once, like `glow`.
- **Rationale**: `ModulationPolicy.allowsExternalControl` means MIDI sets the manual value; the
  host is the one place where a manual glow becomes the rendered glow, so the clamp is guaranteed.
  Writing settings instead would persist every message, record undo states through SCN-010's
  history, and change scenes, which the spec rules out (MIDI-003-R8).
- **Alternatives**: a live `ParameterStore` (nothing renders from one today); writing
  `AppSettings` (persistence and undo churn).

## MIDI-003-D7 Global storage as text lines

- **Decision**: `settings.midi.mappings` holds `[String]`, one `cc:<channel>:<number>=<parameter
  ID>` per binding (channel 0–15 as stored by MIDI-002, shown as 1–16), in list order. Unknown
  kinds, out-of-range numbers, malformed lines, duplicates beyond the policy and lines past 64 are
  skipped on load. The key is in FILE-005's included keys, so a backup carries it and FILE-011's
  Settings category erases it (its key list derives from the included keys).
- **Rationale**: a string list is a type the backup already carries (`.strings`), readable in a
  backup file, and has no room for identifiers. Global, because the controller rig outlives scenes.
- **Alternatives**: JSON data (opaque in backups); per-scene storage (scene recall would rebind the
  controller).

## MIDI-003-D8 Undo inside the mappings screen

- **Decision**: the coordinator keeps the list before the last change (learn, move, replace,
  delete) while the screen is open; Undo restores and saves it, and announces nothing (the row
  changes visibly and VoiceOver reads it). Closing the screen clears it.
- **Rationale**: bindings are not scene state, so SCN-010's history (scene inputs) is the wrong
  place; a one-step undo covers the realistic mistake (wrong knob).

## MIDI-003-D9 Receiving only while needed

- **Decision**: the coordinator registers the input client `"mappings"` iff learning or the list is
  non-empty, so the MIDI-002 rules (listening on, foreground) still decide whether anything is
  connected. The input's state observer ends learning (status: "Learning stopped: Listen for MIDI
  devices is off.") when receiving stops.
- **Rationale**: no input open for a feature that cannot use it (MIDI-002-R1).
