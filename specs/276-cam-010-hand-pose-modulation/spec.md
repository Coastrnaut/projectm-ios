# Feature Specification: CAM-010 Hand Pose Modulation

**Feature Branch**: `feature/cam-010` (spec directory `276-cam-010-hand-pose-modulation`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (CAM-010-T01-T16, T18, T19 verified on the Mac: ParameterGraph, Compositor and LibraryBackup package tests on the host, app unit and UI tests on a private iOS 27.2 simulator with stub and recorded hand detectors; ADR-0087; T17 open `{device}`)

**Input**: User description: "Implement CAM-010 (Hand pose modulation) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Map on-device hand joints to scene parameters." Acceptance, verbatim: "Recorded
synthetic pose frames drive deterministic parameter changes." Priority P3, size L, depends on CAM-001 (camera layer)."

Identifiers in this feature carry the roadmap ID: requirements `CAM-010-R1…`, success criteria `CAM-010-S1…`,
research decisions `CAM-010-D1…`, tasks `CAM-010-T01…`. Other features are cited by their own IDs: CAM-001 / CAM-002
(camera layer, front camera), CAM-008 (person mask), CAM-009 (face landmark emitters: the template for this feature),
CAM-011 (motion sources), CAM-012 (camera badge), MOD-002 / MOD-005 / MOD-006 / MOD-011 / MOD-012 / MOD-013 (bindings,
source smoothing, threshold triggers, layers, modulation matrix, stored IDs), FILE-005 / FILE-011 (settings backup,
erase), SCN-002 (scene capture), PERF-012 (performance report).

## Baseline: what exists today (audit of 2026-11-14, commit `24af20e2`)

| Question | Today |
|---|---|
| Camera pictures | One capture session, owned by the Camera visual's provider (CAM-001/002); a stand-in provider for the simulator and tests. It runs only while the Camera visual is on screen. |
| Analysis hook | CAM-009 added one `pictureAnalyzer` slot on the provider (besides CAM-008's person masker); the face analyzer fills it. Only one analyzer fits the slot. |
| Face tracking | CAM-009: Settings › Camera › Face tracking, off by default, consent sheet first, analysis created lazily behind the gate, 15 Hz (10 Hz reduced, paused warm), `audio.face.*` sources smoothed with MOD-005's envelope; nothing stored or sent (ADR-0081). |
| Where camera-derived sources act | Only the native spectrum host evaluates bindings. The camera runs only in the Camera visual, which evaluates no binding, so face values reach no parameter in the app today (CAM-009-D8). |
| Hand analysis | **None.** |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option, recommended option first.

- Q: How is hand tracking turned on, and does it share face tracking's consent? → A: A separate "Hand tracking" switch in Settings › Camera, below Face tracking, **off by default**, with its own explanation sheet ("Turn On Hand Tracking" / "Cancel") and its own stored consent; face consent never implies hand consent. Consent and switch stay on the device: excluded from the settings backup, removed by Settings erase and the UI-test reset; turning the switch off keeps consent. No new permission and no second capture session: it analyses only the Camera visual's pictures under the existing camera permission and never starts the camera. Both features share one consent model and one analysis host (CAM-010-R1 to R5).
- Q: What exactly is measured, and how is it normalised? → A: From at most two hands (the larger is the first hand), using only joints whose confidence is at least 0.3, and only hands with at least 6 confident joints: **present** (0/1); **x, y** = the wrist in the shown picture (0 left/bottom … 1 right/top, x mirrored with the picture); **pinch** = 1 − (thumb tip–index tip distance ÷ palm length − 0.2) ÷ 0.6, clamped (touching reads 1, a gap of 0.8 palm lengths or more reads 0); **open** = (mean fingertip–wrist distance ÷ palm length − 1.0) ÷ 0.9, clamped (a fist reads 0, a spread hand 1); **size** = palm length ÷ 0.4 of the picture height, clamped (the roadmap brief's "hand height": the wrist y already gives the position); **second, secondX, secondY** = the second hand's present and wrist. Palm length is wrist → middle knuckle; distances are measured with the picture's aspect, so a turn of the device does not change them. A value the joints cannot give (missing wrist, zero palm, non-finite) holds its previous value (CAM-010-R6, R7).
- Q: How are values smoothed so recorded poses give deterministic results? → A: MOD-005's one-pole, 80 ms toward a seen hand and 300 ms toward neutral (present 0, x and y 0.5, the rest 0) without one, on the analysis clock. Each measurement is held as the target from its arrival until the next one (the value moves toward the previous target over the elapsed time, then the new target takes over), so values at a given time depend only on the poses and their times, not on how many frames arrived in between. The first hand after a reset snaps; one step applies at most 0.25 s (CAM-010-R9).
- Q: What are the source IDs and names, and where can they act? → A: Nine sources `audio.hand.<present|x|y|pinch|open|size|second|secondX|secondY>` (the `audio.` binding prefix as CAM-009 and CAM-011), named "Hand present", "Hand left–right", "Hand up–down", "Pinch", "Hand open", "Hand size", "Second hand present", "Second hand left–right", "Second hand up–down". Bindings, layers and threshold triggers accept them; expressions do not. The Camera visual now evaluates the scene's bindings itself on its frame clock with the native visuals' modulator, and applies those that target what it draws: its circular spectrum's inner radius and gap (`visual.circularSpectrum.innerRadius`, `.gap`). So hand and face sources move real parameters while the camera runs; bindings to targets the Camera visual does not draw (the glow it does not render, other visuals' parameters) have no effect there, as before (CAM-010-R8, R16; research CAM-010-D7).
- Q: How often, what is shown, and what must never be kept? → A: At most 15 analyses a second (10 under Low Power Mode or a power profile below 60 fps), one at a time, on its own utility queue, paused when serious or critical warm, the same plan as face tracking. While it analyses, the camera badge reads "Hand tracking" and the performance overlay "Hand tracking on/off" (Camera visual only). No picture, joint, value or hand count is stored, logged, put in scenes, diagnostics, reports or recordings, or sent; each picture is released after its analysis; no network code (CAM-010-R10 to R13).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Opt in before any hand is analysed (Priority: P1)

A performer turns on Hand tracking in Settings › Camera. A sheet explains what is measured and that it never leaves
the device; only after they confirm does the app start analysing the camera picture for hands. Cancel leaves it off.

**Why this priority**: Camera analysis is privacy-sensitive; the consent gate must come first.

**Independent Test**: With a counting stand-in detector, offer camera pictures with the switch on but no consent: no
hand detector is created and no detection runs; after consent and camera access, detections run; after switching
off, the count stays flat.

**Acceptance Scenarios**:

1. **Given** hand tracking never confirmed, **When** the user turns the switch on, **Then** the explanation sheet appears and nothing is analysed.
2. **Given** the sheet, **When** the user cancels, **Then** the switch stays off and nothing is analysed.
3. **Given** the sheet, **When** the user confirms with camera access granted and the camera running, **Then** pictures are analysed for hands.
4. **Given** hand tracking running, **When** the user turns it off, **Then** no further analysis starts and the values return to neutral.
5. **Given** face tracking already confirmed, **When** the user turns hand tracking on, **Then** the hand sheet still appears (consent is per feature).

### User Story 2 - Hands drive the scene (Priority: P1)

A performer binds "Pinch" to a parameter of the scene; pinching thumb and index together moves that parameter while
the Camera visual shows their camera. The same recorded pose sequence always moves it the same way.

**Why this priority**: It is the roadmap's acceptance: recorded synthetic pose frames drive deterministic parameter
changes.

**Independent Test**: Feed a recorded fixture of joint positions over time through the analysis, smoothing and
binding path in place of the detector; the bound parameter takes the expected values at the sample times, the same
in two runs, and the same at shared times when the frames arrive with jittery timing.

**Acceptance Scenarios**:

1. **Given** an open hand centred in the picture, **When** values settle, **Then** present reads 1, x and y about 0.5 and openness high.
2. **Given** thumb and index tips touching, **When** values settle, **Then** "Pinch" reads 1.
3. **Given** the hand leaves the picture, **When** time passes, **Then** present falls to 0 and the others ease to neutral.
4. **Given** a binding from a hand or face source to a parameter the Camera visual draws, **When** the Camera visual runs, **Then** that parameter follows the source.

### User Story 3 - Nothing leaves the device (Priority: P1)

**Independent Test**: Run the pipeline on stubbed poses and compare the app's files before and after; check scenes,
performance reports and the hand sources for hand data, logging, file and network calls.

**Acceptance Scenarios**:

1. **Given** a hand tracking run, **When** the app's files are listed, **Then** no file was added or changed by it.
2. **Given** a scene saved or a performance report exported while hand tracking runs, **When** it is read, **Then** it contains no hand values.

### Edge Cases

- Several hands: at most two are measured; the larger (palm length) is the first hand, the other the second hand.
- Joints below the confidence floor are ignored; a hand with too few confident joints counts as absent.
- Non-finite or degenerate joints (zero hand size): that value holds, never NaN.
- Camera switch, stop or interruption: values return to neutral.
- Camera denied after consent: no analysis; consent stays stored; the row explains.
- Hand detection unavailable (the simulator) or failing: no values (neutral), the row says hand tracking is unavailable, the camera keeps running.
- Face and hand tracking both on: each runs on its own schedule; turning one off does not affect the other.
- A scene with a hand binding opened on an older version: the binding is orphaned (MOD-013), not dropped.
- Settings erase or a restored backup: hand tracking is off and consent must be given again.

## Requirements *(mandatory)*

### Functional Requirements

- **CAM-010-R1**: Hand tracking MUST be off by default and MUST NOT analyse any picture until the user has confirmed its own explanation sheet.
- **CAM-010-R2**: Turning the switch on without stored consent MUST show the sheet; Cancel leaves it off; confirming announces "Hand tracking on"; turning it off MUST stop analysis at once, drop results in flight and return values to neutral.
- **CAM-010-R3**: Consent MUST be stored on the device only, excluded from settings backups, removed by Settings erase and by the UI-test reset.
- **CAM-010-R4**: Hand tracking MUST use only pictures the camera already captures for the Camera visual; it MUST NOT open a capture session, start the camera or add a permission or usage description. Face and hand analysis MUST share the camera's one analysis hook.
- **CAM-010-R5**: With camera access not granted, no analysis MUST run and the row MUST say "Hand tracking needs camera access."; when hand detection cannot run or failed, the row MUST say "Hand tracking isn't available right now." and no value is produced.
- **CAM-010-R6**: The system MUST derive these scalars from at most two hands: first hand present, wrist x, wrist y, pinch, openness, size; second hand present, wrist x, wrist y. Joints below the confidence floor MUST be ignored.
- **CAM-010-R7**: Each value MUST be finite and within 0…1, normalised as in the Clarifications.
- **CAM-010-R8**: The values MUST be bindable sources `audio.hand.<feature>` usable by bindings, layers and threshold triggers, not by expressions, with people-facing names.
- **CAM-010-R9**: Values MUST be smoothed with MOD-005's one-pole on an injected clock, so that the same pose sequence gives the same values at the same times regardless of how often frames arrive between them.
- **CAM-010-R10**: Analyses MUST run at most 15 per second (10 under reduced power), one at a time, off the main and render threads, paused while the device is serious or critical warm.
- **CAM-010-R11**: Pictures, joints and values MUST NOT be stored, logged, written to scenes, diagnostics, performance reports or recordings, or sent; each picture MUST be released right after its analysis.
- **CAM-010-R12**: The hand pipeline MUST contain no networking API; compliance and network-symbol checks MUST pass.
- **CAM-010-R13**: While hand analysis runs, the camera badge MUST say "Hand tracking"; the performance overlay MUST show only "Hand tracking on/off" while the Camera visual is shown.
- **CAM-010-R14**: The privacy policy MUST describe hand tracking accurately.
- **CAM-010-R15**: The plain parts (normalisation, smoothing, schedule, gate) MUST build and test on Linux.
- **CAM-010-R16**: While the Camera visual runs, bindings from any source (hand and face included) to the parameters the Camera visual itself draws MUST change those parameters, evaluated on its frame clock with the same binding machinery as the native visuals.

### Key Entities

- **Hand feature**: one of present, x, y, pinch, open, size, second, secondX, secondY.
- **Hand pose sample**: the confident positions of seven joints of one hand (wrist, thumb tip, index tip, middle tip, ring tip, little tip, middle knuckle) with their confidences, plus the picture's aspect, memory only.
- **Hand feature values**: the nine smoothed 0…1 values.
- **Hand tracking gate**: switch, consent, camera permission → whether analysis may run.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CAM-010-S1**: With consent missing, 0 hand detectors are created and 0 detections run over a run of camera pictures; after consent and permission, more than 0; after switching off, the count does not grow.
- **CAM-010-S2**: A recorded synthetic pose sequence drives a bound parameter to identical values in two runs, to the expected values at sample times (within 0.001), and to the same values at shared times (within 1e-9) when the frames arrive with jittery timing.
- **CAM-010-S3**: For synthetic poses (centred, extreme, degenerate, non-finite, low confidence), 100 % of values are finite and within 0…1.
- **CAM-010-S4**: A hand tracking run adds no file to the app's container, and saved scenes and performance reports contain no hand value.
- **CAM-010-S5**: The built app passes the network-symbol, privacy-manifest and compliance checks.
- **CAM-010-S6**: In the UI, the hand tracking explanation sheet appears before activation and Cancel leaves the switch off (UI test under 30 s).
- **CAM-010-S7**: With the Camera visual running and a hand or face source bound to a parameter it draws, that parameter changes with the source (app test).

## Assumptions

- The Camera visual applies bindings only to the circular spectrum it draws (inner radius, gap); bindings to other targets have no effect there, LFO, band-envelope and motion sources read their no-input values there, and threshold triggers stay with the native visuals (research CAM-010-D7).
- Route creation in the UI stays out of scope (MOD-012-D6); hand sources are bound through scenes, the modulation matrix's existing edits and DEBUG seeds.
- Real hands on D1, the frame rate with hand tracking on and the system camera indicator are `{device}` checks; the simulator has no camera and cannot run hand detection.
