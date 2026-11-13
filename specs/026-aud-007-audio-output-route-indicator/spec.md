# Feature Specification: AUD-007 Audio output route indicator

**Feature Branch**: `feature/aud-007` (spec directory `026-aud-007-audio-output-route-indicator`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement AUD-007 (Audio output route indicator) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Show active route and explain when
an output changes." Acceptance, verbatim: "Plug or unplug headphones; indicator changes without
claiming a capture source." Dependencies: none (works with AUD-014's route handling). Honor the
repository constitution (IV) and owner rule 7."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `AUD-007-R1…`, success criteria `AUD-007-S1…`, tasks `AUD-007-T01…`. Requirements of
feature 001 (`specs/001-ios-projectm-visualizer/spec.md`) and AUD-014
(`specs/009-aud-014-audio-session-interruption-recovery/spec.md`) stay in force; nothing here amends
them. In particular AUD-014-R14 (a disconnected output pauses In-App Playback with "Paused — audio
route changed", FR-051), AUD-014-R17 and R18 (the on-hold explanation and its announcement) and
AUD-014-R19 (Microphone and System/App Capture texts do not change) are unchanged.

## Baseline: what exists today (audit of 2026-11-13)

| Capability | Today |
|---|---|
| Which output the audio plays through | Not shown anywhere |
| Output disconnected while In-App Playback plays | Pauses; banner "Paused — audio route changed" plus "The audio output was disconnected. Press Play to continue." (AUD-014) |
| New output connected | Nothing visible; playback continues on the new output (iOS behavior) |
| Microphone input changes | The Microphone source continues on the new input, or fails with "Microphone unavailable" (feature 001 lifecycle matrix) |
| Source-and-state indicator | "In-App Playback · Active audio" etc. (FR-042, FR-070) |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See where the sound goes (Priority: P1)

A user plays a track (In-App Playback) and wants to know whether it is coming out of the device's
speaker, wired headphones, Bluetooth headphones or an AirPlay receiver. The controls show a compact
route indicator, for example "Output: Speaker" or "Output: AirPods Pro", using the name iOS gives
the device.

**Why this priority**: The roadmap row's first half ("Show active route").

**Independent Test**: With an injected route, start In-App Playback, open the controls and read the
indicator; it names the injected output and never a capture source.

**Acceptance Scenarios**:

1. **Given** In-App Playback runs on the built-in speaker, **When** the controls are shown, **Then**
   the indicator reads "Output: Speaker" and VoiceOver reads "Audio output: Speaker".
2. **Given** the output is a Bluetooth device named "AirPods Pro" by iOS, **When** the controls are
   shown, **Then** the indicator reads "Output: AirPods Pro".
3. **Given** System/App Capture is the active source, or no source runs, **When** the controls are
   shown, **Then** no route indicator is shown.

---

### User Story 2 - Understand an output change (Priority: P1)

While a track plays the user plugs in or unplugs headphones, connects AirPods or picks an AirPlay
receiver. The indicator changes to the new output and a short explanation appears for a few
seconds, for example "Now playing through Headphones" or, when AUD-014 pauses playback because the
headphones were unplugged, "Headphones disconnected — paused". VoiceOver users hear the
explanation.

**Why this priority**: The roadmap row's second half and its acceptance ("Plug or unplug
headphones; indicator changes without claiming a capture source").

**Independent Test**: With an injected route provider, a sequence of changes (wired in, wired out,
Bluetooth in, Bluetooth out, AirPlay) produces the expected indicator text, explanation and
announcement; a UI test triggers a fake change and reads the indicator.

**Acceptance Scenarios**:

1. **Given** In-App Playback plays on the speaker, **When** wired headphones are connected,
   **Then** the indicator reads "Output: Headphones" and the explanation "Now playing through
   Headphones" appears and is announced.
2. **Given** In-App Playback plays on wired headphones, **When** they are disconnected, **Then**
   playback pauses exactly as AUD-014-R14 requires, the indicator reads "Output: Speaker" and the
   explanation reads "Headphones disconnected — paused"; it is shown but not announced separately,
   because AUD-014-R18 already announces the pause.
3. **Given** the user had paused playback, **When** the headphones are disconnected, **Then** the
   explanation reads "Headphones disconnected" (no "paused": playback was already held by the user)
   and is announced.
4. **Given** the outputs did not change (for example a category change at a source start), **When**
   iOS reports a route change, **Then** no explanation appears.

---

### User Story 3 - Microphone mode shows where it listens (Priority: P2)

In Microphone mode the app plays no sound, and its audio session has no output at all. The
indicator therefore shows the microphone input iOS records from ("Input: iPhone Microphone",
"Input: Headset Microphone"), and explains a change ("Now listening through Headset Microphone").

**Why this priority**: The roadmap asks for the indicator while either local audio path runs; in
Microphone mode the only route that changes when a headset is plugged in is the input.

**Independent Test**: With an injected route, Microphone mode's indicator names the input port and
never an output, and its texts never name a source mode or another app.

**Acceptance Scenarios**:

1. **Given** Microphone mode runs on the built-in microphone, **When** the controls are shown,
   **Then** the indicator reads "Input: iPhone Microphone" (the name iOS gives).
2. **Given** Microphone mode runs, **When** a headset with a microphone is connected, **Then** the
   indicator names the headset's input and "Now listening through <name>" appears.

### Edge Cases

- iOS gives an empty port name: the indicator uses a generic name for the kind ("Speaker",
  "Headphones", "Bluetooth device", "AirPlay device", …); it never invents a product name.
- Several outputs at once (for example HDMI plus another port): the indicator names them in iOS's
  order, joined by ", ".
- No output (or, in Microphone mode, no input) after a change: the indicator reads "Output: None"
  ("Input: None") and the explanation "No audio output available" ("No audio input available").
- Rapid repeated changes: the newest change replaces the explanation at once; at most one is shown.
- A change while the indicator is not shown (System/App Capture, no source): the route is still
  tracked so the indicator is correct when it appears, but no explanation is shown or announced.
- A route change that arrives before or after AUD-014's pause in any order: the explanation does not
  depend on that order.
- The route changes while the app is in the background: the indicator shows the current route on
  return; no stale explanation is shown for it.

## Requirements *(mandatory)*

### Functional Requirements

**Model**

- **AUD-007-R1**: The app MUST derive a typed route from the system's current audio route: each
  output (and input) port with a kind and the port name iOS gives. Output kinds: built-in speaker,
  built-in receiver, wired headphones, Bluetooth A2DP, Bluetooth LE, Bluetooth hands-free, AirPlay,
  HDMI, USB audio, car audio, line out, other. Input kinds: built-in microphone, headset
  microphone, Bluetooth hands-free, USB audio, car audio, line in, other.
- **AUD-007-R2**: The route MUST come from a replaceable provider so that tests can inject routes
  and route changes without audio hardware.
- **AUD-007-R3**: The route MUST be refreshed when iOS reports a route change, with the reason iOS
  gives, and when a source starts.

**Indicator**

- **AUD-007-R4**: While In-App Playback is the active source and its session has not ended, the
  controls MUST show a compact indicator "Output: <names>"; while Microphone is the active source,
  "Input: <names>". It MUST NOT be shown for System/App Capture or without an active source.
- **AUD-007-R5**: Names MUST be the port names iOS gives; when iOS gives none, a generic name for the
  kind. The app MUST NOT invent device names.
- **AUD-007-R6**: The indicator MUST have a VoiceOver label "Audio output: <names>" ("Audio input:
  <names>") and an icon matching the primary port's kind.

**Explanation**

- **AUD-007-R7**: When the shown direction's ports change, a short explanation MUST appear for about
  4 seconds (the newest replaces the previous):
  - a port appeared or became primary: "Now playing through <name>" (In-App Playback while not held
    by the user), "Audio output is now <name>" (In-App Playback held by the user), "Now listening
    through <name>" (Microphone);
  - a port was lost (the reason "old device unavailable"): "<lost name> disconnected — paused" when
    AUD-014 pauses In-App Playback for it; otherwise "<lost name> disconnected";
  - nothing left: "No audio output available" / "No audio input available".
- **AUD-007-R8**: No explanation for a category change (the app's own session setup) or when the
  shown ports did not change.
- **AUD-007-R9**: The "— paused" wording MUST follow the same rule as AUD-014's pause: In-App
  Playback, reason "old device unavailable", and playback not already held by the user. Both MUST
  use one shared definition of which route-change reason pauses playback.
- **AUD-007-R10**: VoiceOver MUST announce each explanation, except the "— paused" one, which
  AUD-014-R18 already announces (two announcements in a row would cut each other off).

**Truthfulness, safety, privacy**

- **AUD-007-R11**: No route text may name a source mode ("System/App Capture", "Microphone",
  "In-App Playback"), use the words "capture" or "captured", name a third-party app, or describe an
  output as where audio comes from (Constitution IV, V).
- **AUD-007-R12**: AUD-014's behavior on a lost output MUST NOT change (AUD-014-R14, R17, R18).
  The QA-007 source contract suite MUST stay green.
- **AUD-007-R13**: Nothing may run on a real-time audio callback; route handling runs on the main
  actor from notifications (Constitution VII).
- **AUD-007-R14**: No permission, entitlement, background mode, network use, stored data or new
  dependency; public APIs only (Constitution I, Privacy). The route is never stored or exported.
- **AUD-007-R15**: Debug builds MUST offer a launch hook to inject a fake route and post fake route
  changes for UI tests; Release builds contain none of it.

### Key Entities

- **Route port**: kind, direction (input or output), name as given by iOS.
- **Audio route**: the ordered input and output ports at one moment.
- **Route change**: the reason iOS gave, the route before and after, and a sequence number.
- **Route context**: what the indicator shows and how it words a change: playback (held by the user
  or not), microphone, or none.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **AUD-007-S1**: Every port type iOS defines maps to a kind; unknown types map to "other"
  (checked by a table-driven unit test, on the host and the simulator).
- **AUD-007-S2**: For the sequences wired in, wired out (playing and user-paused), Bluetooth in and
  out, AirPlay, category change and no output, the indicator text, explanation and announcement
  match the string contract exactly (unit tests, each under 2 s).
- **AUD-007-S3**: No route string produced for any kind, name and context contains a source mode
  label, "capture" or a third-party app name (unit test over every string).
- **AUD-007-S4**: A lost output still pauses In-App Playback with "Paused — audio route changed",
  and the explanation says "— paused" in that case (unit test plus a simulator UI test under 30 s).
- **AUD-007-S5**: On a device (D1), plugging and unplugging wired headphones (or connecting and
  disconnecting Bluetooth headphones) changes the indicator within 1 second, with the explanation,
  and never names a capture source (`{device}` check, final phase).

## Assumptions

- iOS reports route changes through the audio session's route-change notification with a reason;
  the current route is read from the session at that moment.
- The simulator's route is fixed, so route changes on the simulator come only from the Debug launch
  hook; real plug and unplug is device-only and runs in the final device phase.
- Explanation timing (about 4 seconds) is a presentation detail and is not asserted by tests.
