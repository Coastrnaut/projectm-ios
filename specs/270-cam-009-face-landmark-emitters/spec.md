# Feature Specification: CAM-009 Face Landmark Emitters

**Feature Branch**: `feature/cam-009` (spec directory `270-cam-009-face-landmark-emitters`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (CAM-009-T01-T15 verified on the Mac: ParameterGraph, Compositor and LibraryBackup package tests on the host, app unit and UI tests on a private iOS 27.2 simulator with a stub face detector; ADR-0081; T16 open `{device}`)

**Input**: User description: "Implement CAM-009 (Face landmark emitters) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Generate normalized on-device face landmark events, opt-in." Acceptance, verbatim:
"Consent gate precedes capture and no face frames leave device." Priority P3, size L, depends on CAM-002 (front
camera layer)."

Identifiers in this feature carry the roadmap ID: requirements `CAM-009-R1…`, success criteria `CAM-009-S1…`,
research decisions `CAM-009-D1…`, tasks `CAM-009-T01…`. Other features are cited by their own IDs: CAM-001 / CAM-002
(camera layer, front camera), CAM-008 (person mask: on-device analysis of camera pictures), CAM-011 (motion sources),
CAM-012 (camera status badge and Stop camera), MOD-002 / MOD-006 / MOD-013 (bindings, threshold triggers, stored
binding IDs), FILE-005 / FILE-011 / FILE-013 (settings backup, erase, permission catalog), REC-001 / REC-003 (frame
and video capture), SCN-002 (scene capture).

## Baseline: what exists today (audit of 2026-11-14, commit `e6f22542`)

| Question | Today |
|---|---|
| Camera pictures | One capture session, owned by the Camera visual's provider (`AVCameraFrameProvider`, CAM-001/002); a stand-in provider for the simulator and UI tests. It runs only while the Camera visual is on screen. |
| Analysis of pictures | CAM-008 offers each picture to a `PersonMasker`, which runs on-device person segmentation on a bounded schedule, on its own serial queue, memory only (ADR-0063). |
| Modulation sources | `AudioFeatureSource` names every bindable source; CAM-011 added `audio.motion.<axis>` fed by an app coordinator through a closure the native spectrum host reads per frame, only while a binding or trigger names it. |
| Camera permission | One camera usage description (FILE-013 catalog); the app asks only when the Camera visual is chosen (UIX-015 explainer). |
| Face analysis | **None.** The privacy policy states the app does no face detection. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option, recommended option first.

- Q: How is face tracking turned on? → A: A separate "Face tracking" switch in Settings › Camera, **off by default**. Turning it on the first time shows an explanation sheet (what is measured, that it stays on the device, that nothing is stored or sent) with "Turn On Face Tracking" and "Cancel". Only Confirm stores consent and turns the switch on; Cancel (or dismissing the sheet) leaves it off. No face analysis runs before consent (CAM-009-R1, R2).
- Q: Is consent remembered, and after reinstalling? → A: Consent is stored in the app's settings on the device only, so it is remembered while the app is installed; deleting the app deletes it, so a reinstall asks again. It is never included in a settings backup (FILE-005 excluded keys) and Settings erase (FILE-011) removes it, so a restored backup can never turn face tracking on. Turning the switch off keeps consent; turning it on again does not re-ask (CAM-009-R3).
- Q: Does face tracking need its own permission or start the camera? → A: No new permission and no second capture session: it analyses only the pictures the Camera visual already captures, under the existing camera permission. It never starts the camera; with the camera off (another visual, paused, Stop camera) nothing is analysed. With camera access denied or restricted no analysis runs and the row says "Face tracking needs camera access." (CAM-009-R4, R5).
- Q: What is measured? → A: Only derived, normalised scalars from the most prominent (largest) face: **face present** (0/1), **centre x**, **centre y**, **size**, **head roll**, **head yaw**, **mouth open** (inner-lip gap ÷ face height) and **eye openness** (mean eye height ÷ width). Each is finite and within 0…1 (CAM-009-R6, R7).
- Q: Source IDs and names? → A: Eight sources `audio.face.<present|x|y|size|roll|yaw|mouth|eyes>` (keeping the `audio.` binding prefix as MOD-007-D4 and CAM-011 did). Names "Face present", "Face left–right", "Face up–down", "Face size", "Head tilt", "Head turn", "Mouth open", "Eyes open". Bindings, layers and threshold triggers accept them (a trigger on "Mouth open" is the face event); expressions do not, as for motion sources (CAM-009-R8).
- Q: Normalisation? → A: x and y are the face centre in the shown picture (0 left/bottom … 1 right/top), mirrored like the picture when the camera is mirrored; size = face height ÷ picture height; roll and yaw map ±45° to 0…1 (0.5 straight); mouth = gap ÷ face height ÷ 0.2 clamped (0.2 of the face height reads fully open); eyes = (ratio − 0.1) ÷ 0.2 clamped (0.1 closed, 0.3 open) (CAM-009-R7).
- Q: Smoothing and absence? → A: A one-pole of 80 ms (MOD-005's envelope) on the analysis clock; with no face, present falls to 0 and the others ease to neutral (x, y, roll, yaw 0.5; size, mouth 0; eyes 0) over 300 ms. Non-finite readings are ignored (CAM-009-R9).
- Q: How often? → A: At most 15 analyses a second (10 under Low Power Mode or a power profile below 60 fps), never two in flight, on a utility queue; paused when the device is serious or critical warm. The render thread never waits (CAM-009-R10).
- Q: What must never be kept or sent? → A: No picture, landmark list, face print or value is stored, logged, put in scenes, diagnostics or performance reports, recorded, or sent. Each picture is released right after its analysis. Saved frames and recordings contain the camera picture exactly as before (CAM-001), never face data. Logs carry no values. The feature adds no network code (CAM-009-R11, R12).
- Q: How does the user know it is running? → A: While face tracking analyses pictures, the camera badge reads "Camera on · Face tracking" (iOS's own camera indicator also shows). The performance overlay shows only "Face tracking on/off"; the performance report's fixed schema (PERF-012) gains nothing and holds no face data (CAM-009-R13).
- Q: Turning it off? → A: The switch off stops analysis at once: no new analysis starts, a result still in flight is dropped, and all values return to neutral (CAM-009-R2).
- Q: Does face tracking work with the back camera too? → A: Yes: it analyses whichever camera the Camera visual shows (front or back), since the user chose that camera; a camera switch resets the values to neutral (CAM-009-R6).
- Q: What does the row show when face detection cannot run (the simulator, or an analysis error)? → A: The switch stays as chosen, no values are produced (sources read neutral) and the row says "Face tracking isn't available right now." An error stops face analysis until the camera visual is opened again (no retry every frame, as CAM-008) (CAM-009-R5).
- Q: Is the sheet and switch accessible? → A: The switch is a standard toggle labelled "Face tracking" with a hint; the sheet's text is readable by VoiceOver and its two buttons are labelled; confirming posts one polite announcement "Face tracking on" through the AccessibilityAnnouncer lane (CAM-009-R2).
- Q: Where can face sources drive something today? → A: Like every binding source they feed the native spectrum's modulation. Face values are live only while the camera runs, which today is the Camera visual; when no picture is analysed the sources read their neutral values. A native visual with a camera layer is future work (CMP-015); this feature does not add one (Assumptions).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Opt in before anything is analysed (Priority: P1)

A performer turns on Face tracking in Settings › Camera. A sheet explains what is measured and that it never leaves
the device; only after they confirm does the app start analysing the camera picture. Cancel leaves it off.

**Why this priority**: It is the roadmap's acceptance: the consent gate precedes capture.

**Independent Test**: With a counting stand-in analyser, run camera pictures with the switch on but no consent: no
face analysis is created or run; after consent and permission, analyses run; after switching off, the count stays
flat.

**Acceptance Scenarios**:

1. **Given** face tracking never confirmed, **When** the user turns the switch on, **Then** the explanation sheet appears and nothing is analysed.
2. **Given** the sheet, **When** the user cancels, **Then** the switch stays off and nothing is analysed.
3. **Given** the sheet, **When** the user confirms with camera access granted and the camera running, **Then** pictures are analysed.
4. **Given** face tracking running, **When** the user turns it off, **Then** no further analysis starts and the values return to neutral.
5. **Given** camera access denied, **When** face tracking is on, **Then** nothing is analysed and the row says it needs camera access.

### User Story 2 - Faces drive the visuals (Priority: P2)

A performer binds "Mouth open" to the glow, or a threshold trigger to "Mouth open"; opening their mouth raises the
glow or fires the trigger.

**Independent Test**: Feed synthetic face observations through the emitter and check the normalised, smoothed
values; drive a bound parameter in the app from an injected source.

**Acceptance Scenarios**:

1. **Given** a synthetic face centred, level, mouth closed, **When** values are read, **Then** x, y, roll, yaw read 0.5 and mouth 0.
2. **Given** a wide-open mouth, **When** values settle, **Then** "Mouth open" reads 1.
3. **Given** the face leaves the picture, **When** time passes, **Then** "Face present" falls to 0 and the others ease to neutral.

### User Story 3 - Nothing leaves the device (Priority: P1)

**Independent Test**: Run the pipeline on stubbed observations and compare the app's files before and after; check
scenes, diagnostics and logs for face data; check the built app for network symbols.

**Acceptance Scenarios**:

1. **Given** a face tracking run, **When** the app's files are listed, **Then** no file was added or changed by it.
2. **Given** a scene saved or a performance report exported while face tracking runs, **When** it is read, **Then** it contains no face values.

### Edge Cases

- Several faces: only the largest is measured.
- Camera switch, stop or interruption: values return to neutral; analysis resumes with the next picture.
- Camera denied after consent: no analysis; consent stays stored; the row explains.
- Analysis fails or face detection is unsupported (the simulator): no values (neutral), the row says face tracking is unavailable, the camera keeps running.
- Non-finite or degenerate landmarks (zero-width eye): that value is held, never NaN.
- A scene with a face binding opened on an older version: the binding is orphaned (MOD-013), not dropped.
- Settings erase or a restored backup: face tracking is off and consent must be given again.

## Requirements *(mandatory)*

### Functional Requirements

- **CAM-009-R1**: Face tracking MUST be off by default and MUST NOT analyse any picture until the user has confirmed the explanation sheet.
- **CAM-009-R2**: Turning the switch on without stored consent MUST show the sheet; Cancel leaves it off; confirming announces "Face tracking on"; turning it off MUST stop analysis at once, drop results in flight and return values to neutral.
- **CAM-009-R3**: Consent MUST be stored on the device only, excluded from settings backups, removed by Settings erase and by the UI-test reset.
- **CAM-009-R4**: Face tracking MUST use only pictures the camera already captures for the Camera visual; it MUST NOT open a capture session, start the camera or add a permission or usage description.
- **CAM-009-R5**: With camera access not granted, no analysis MUST run and the row MUST say "Face tracking needs camera access."; when face detection cannot run or failed, the row MUST say "Face tracking isn't available right now." and no value is produced.
- **CAM-009-R6**: The system MUST derive eight scalars from the largest face: present, x, y, size, roll, yaw, mouth, eyes.
- **CAM-009-R7**: Each value MUST be finite and within 0…1, normalised as in the Clarifications.
- **CAM-009-R8**: The values MUST be bindable sources `audio.face.<feature>` usable by bindings, layers and threshold triggers, not by expressions, with the people-facing names above.
- **CAM-009-R9**: Values MUST be smoothed (80 ms one-pole) on an injected clock; with no face, present falls to 0 and the others ease to neutral (300 ms).
- **CAM-009-R10**: Analyses MUST run at most 15 per second (10 under reduced power), one at a time, off the main and render threads, paused while the device is serious or critical warm.
- **CAM-009-R11**: Pictures, landmarks, face prints and values MUST NOT be stored, logged, written to scenes, diagnostics, performance reports or recordings, or sent; each picture MUST be released right after its analysis.
- **CAM-009-R12**: The face pipeline MUST contain no networking API; compliance and network-symbol checks MUST pass.
- **CAM-009-R13**: While analysis runs, the camera badge MUST say "Face tracking"; the performance overlay MUST show only "Face tracking on/off" while the Camera visual is shown; the performance report (PERF-012, a fixed schema) and diagnostics MUST contain no face data.
- **CAM-009-R14**: The privacy policy MUST describe face tracking accurately.
- **CAM-009-R15**: The plain parts (normalisation, smoothing, schedule, gate) MUST build and test on Linux.

### Key Entities

- **Face feature**: one of present, x, y, size, roll, yaw, mouth, eyes.
- **Face observation sample**: the scalars Vision reports for one face (bounding box, roll, yaw, inner-lip, eye points), memory only.
- **Face feature values**: the eight smoothed 0…1 values.
- **Face tracking gate**: switch, consent, camera permission → whether analysis may run.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CAM-009-S1**: With consent missing, 0 face analyses are created or run over a run of camera pictures; after consent and permission, more than 0; after switching off, the count does not grow.
- **CAM-009-S2**: For synthetic observations (centred, extreme, degenerate, non-finite), 100 % of values are finite and within 0…1, and centred neutral values read 0.5 within 0.01.
- **CAM-009-S3**: A face tracking run adds no file to the app's container, and saved scenes and performance reports contain no face value.
- **CAM-009-S4**: The built app passes the network-symbol, privacy-manifest and compliance checks.
- **CAM-009-S5**: In the UI, the explanation sheet appears before activation and Cancel leaves the switch off (UI test under 30 s).

## Assumptions

- Face values feed the native spectrum's modulation, as every binding source does; the camera runs only in the Camera visual today, so outside it the sources read neutral values. Combining a native visual with a camera layer is future work.
- Route creation in the UI stays out of scope (MOD-012-D6); face sources are bound through scenes and DEBUG seeds.
- Real faces on D1, the indicator on a device and the frame rate with tracking on are `{device}` checks; the simulator has no camera and cannot run face detection.
