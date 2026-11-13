# Feature Specification: FILE-013 Privacy Permission Audit

**Feature Branch**: `feature/file-013` (spec directory `078-file-013-privacy-permission-audit`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement FILE-013 (Privacy permission audit) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Centralize descriptions of mic,
camera, Photos and local network access." Acceptance, verbatim: "Denied and restricted states each have
tested user-facing behavior." P0, effort M, depends on SCN-001."

Identifiers in this feature carry the roadmap ID: requirements `FILE-013-R1…`, success criteria
`FILE-013-S1…`, tasks `FILE-013-T01…`. Other features are cited by their own IDs: FR-005 (microphone
explainer), FR-015 (stop reasons), FR-019 (usage descriptions), CAM-001 (Camera visual), OSC-001 (OSC
receiver), MED-001/MED-002 (Photo and Video visuals via the Photos picker), REC-012 (sharing, no Photos
permission). UIX-015 (an onboarding explainer shown before the system prompts) is a separate roadmap
item and is not built here.

## Baseline: the audit (2026-11-13, commit `7ec3fe5`)

Every privacy permission the shipping app (`projectM-iOS`) can trigger, from `project.yml` and the
code that asks for it.

| Permission | Info.plist key | Asked when (point of use) | notDetermined | Denied | Restricted |
|---|---|---|---|---|---|
| Microphone | `NSMicrophoneUsageDescription` | The user chooses Microphone mode, after the FR-005 explainer | Explainer, then iOS's prompt | Status banner "Microphone permission denied. Enable it in Settings › Privacy › Microphone." with Open Settings and Choose source | iOS reports no separate restricted state for recording; it arrives as denied |
| Camera | `NSCameraUsageDescription` | The user chooses the Camera visual (CAM-001-R4) | iOS's prompt | Non-blocking notice "Camera access is off…" with Open Settings; the spectrum keeps running | Notice "Camera access is restricted on this device…" with Open Settings |
| Local Network | `NSLocalNetworkUsageDescription` | The user turns on OSC receiver in Settings (OSC-001-R17) | iOS's prompt when the listener opens | Settings status "Local network access is off for projectM in Settings › Privacy & Security › Local Network."; **no Open Settings button** | No query API and no restricted state; a policy block arrives as the same denial |
| Screen capture (System/App Capture) | `NSScreenCaptureUsageDescription` | The user chooses System/App Capture; iOS's own picker each time | iOS's picker | Banner "Screen recording not allowed" with Restart and Choose source | Chooser row disabled with "Screen recording not allowed" (the picker reports it is not allowed) |
| Photos library | none (no `NSPhotoLibraryUsageDescription`, no `NSPhotoLibraryAddUsageDescription`) | Never: the Photos picker runs outside the app and returns only the picked item | — | — | — |

No other usage-description key exists in the app (CaptureLab and RendererLab are harnesses, not
shipped; CaptureLab carries the microphone, camera and screen-capture keys of its own target and is out
of scope). Findings:

1. The descriptions are scattered: the usage strings live only in `project.yml`, the in-app wording in
   three places (the capture UI strings, the camera feed state, the OSC coordinator), and nothing
   checks that each permission the app declares is described in the app and the privacy policy.
2. Three different "open Settings" code paths exist and only two of the four permissions with a denied
   state offer one; Local Network's denial tells the user where to go but gives no button.
3. Restricted is tested only for the camera's state text; no UI test shows a restricted state, and
   no test documents that microphone and local network have no restricted state of their own.
4. The privacy policy's permission list is hand-written and not checked against the app.

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative option.

- Q: Does "centralize" mean moving the usage strings out of `project.yml`? → A: No. `project.yml` stays
  the only source of the Info.plist values (XcodeGen writes Info.plist from it). A single in-app
  catalog lists every permission with its key, the identical usage text, its in-app description,
  the features that use it and its notices; a script fails when the catalog and `project.yml` differ in
  any key or text. Applied to FILE-013-R1, R6.
- Q: Should the existing notice wording change? → A: No. The microphone and screen-capture texts are
  fixed by feature 001's contract (`contracts/ui-states.md`, checked by `test_scripts.py`), and the
  camera and OSC texts are asserted by shipped tests. The catalog owns the denied and restricted texts
  and the existing features read them from it; wording is unchanged. Applied to FILE-013-R2, R3.
- Q: What does "one notice style" cover? → A: The camera notice and the Local Network status in Settings
  use one shared notice (symbol, text, Open Settings when Settings can help) and one Settings opener.
  The microphone and screen-capture denials stay in the source status banner (feature 001's banner,
  shared with CaptureLab, whose action list is contract-checked), whose Open Settings uses the same
  opener. Applied to FILE-013-R3, R4.
- Q: How are restricted states handled for permissions iOS cannot report as restricted? → A: The
  catalog defines restricted for every permission. Microphone and Local Network map an OS restriction
  to the denied text (iOS reports it as denied) and say so; the mapping and notice are unit-tested
  with injected states. Applied to FILE-013-R2, R5.
- Q: Should screen capture offer Open Settings? → A: No. iOS has no per-app screen-recording switch in
  Settings: a decline is asked again at the next start (Restart), and a Screen Time restriction is set
  by whoever manages the device. Applied to FILE-013-R4.
- Q: Which states are exercised for real on the simulator? → A: Microphone denied, by revoking the
  permission with `simctl privacy` before the run (the test skips, never passes, when the run did not
  revoke it). The simulator has no rear camera (the real camera path reports "unavailable" before any
  permission), cannot script Local Network, and cannot set restricted for anything; those states use
  the existing DEBUG stand-ins (camera scenario, fake source) and a new DEBUG OSC failure stand-in.
  Restricted on D1 via Screen Time is a `{device}` task. Applied to FILE-013-R7, R8, R9.
- Q: How does a UI test prove that Open Settings works? → A: One test taps the camera notice's Open
  Settings and asserts that iOS Settings (`com.apple.Preferences`) comes to the foreground, then
  returns to the app; the other notices assert the button exists and uses the same opener (unit-tested
  routing). Applied to FILE-013-R8.
- Q: How does VoiceOver read the shared notice? → A: As today's camera notice: one container holding
  the text and a separate Open Settings button; the decorative symbol is hidden; existing identifiers
  stay and new ones follow `<feature>Notice`, `<feature>OpenSettings`. No new announcement. Applied to
  FILE-013-R3.
- Q: Does the OSC listener badge change when Local Network is denied? → A: No. The badge shows only
  while the listener is open (OSC-007); the denial is shown where the user turned OSC on (Settings).
  Applied to Edge Cases.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A denied permission explains itself and leaves the app usable (Priority: P1)

A user who declined (or later turned off) the microphone, camera or local network access uses the
feature that needs it. The app shows a short, non-blocking notice that names what is off, keeps every
other part working, and, where Settings can change it, offers Open Settings.

**Why this priority**: the roadmap's acceptance; a denied permission must never leave the user stuck
or guessing.

**Independent Test**: deny each permission (for real where the simulator allows, injected otherwise),
use its feature, read the notice and its actions.

**Acceptance Scenarios**:

1. **Given** microphone access is denied, **When** the user chooses Microphone, **Then** the status
   banner shows the catalog's microphone-denied text with Open Settings and Choose source.
2. **Given** camera access is denied, **When** the user chooses the Camera visual, **Then** the
   camera notice shows the catalog's camera-denied text with Open Settings, and the spectrum runs.
3. **Given** Local Network access is denied, **When** the user turns on OSC receiver, **Then** the
   OSC status shows the catalog's local-network-denied text and an Open Settings button.
4. **Given** the user declines screen recording, **When** System/App Capture starts, **Then** the
   banner shows "Screen recording not allowed" with Restart and Choose source.

### User Story 2 - A restricted permission says it is restricted (Priority: P1)

On a managed device or with Screen Time limits, the user sees a notice that says the access is
restricted on this device (camera), that capture is not allowed (screen capture), or the denied
notice where iOS reports a restriction as a denial (microphone, local network).

**Independent Test**: inject the restricted state for each permission; check the text and actions.

**Acceptance Scenarios**:

1. **Given** camera access is restricted, **When** the user chooses the Camera visual, **Then** the
   notice says it is restricted on this device and offers Open Settings.
2. **Given** screen capture is not allowed on the device, **When** the chooser shows, **Then** the
   System/App Capture row is disabled and says "Screen recording not allowed".
3. **Given** a restricted state is injected for microphone or local network, **Then** the catalog
   returns that permission's denied notice.

### User Story 3 - One place describes every permission (Priority: P2)

A maintainer (or reviewer) reads one catalog to learn every permission the app can ask for, why, where
it is asked, and what the user sees when it is refused; a check fails when a usage key is added,
removed or reworded without the catalog, or when a Photos library key appears.

**Independent Test**: run the check on the real `project.yml` (passes) and on altered copies (each
fails with a named finding).

**Acceptance Scenarios**:

1. **Given** `project.yml` gains a usage key the catalog does not list, **When** the check runs,
   **Then** it fails naming the key.
2. **Given** a Photos library key is added, **When** the check runs, **Then** it fails.
3. **Given** the privacy policy's permission list, **When** the check runs, **Then** every catalog
   permission is named there and the policy names no other.

### Edge Cases

- The user grants access in Settings and returns: the camera retries when the visual is chosen again
  (CAM-001); OSC retries when toggled; Microphone when chosen again. Unchanged by this feature.
- Open Settings opens the app's own page in iOS Settings; the app does not need to be in any state.
- A permission prompt is never shown at launch: every prompt stays at its point of use (Constitution
  Privacy). This feature adds no prompt.
- A Local Network denial never shows the listener badge (it shows only while listening, OSC-007);
  the denial appears in Settings' OSC section.
- Interrupted or unavailable camera states (not permission states) keep their notices without Open
  Settings.

## Requirements *(mandatory)*

### Functional Requirements

- **FILE-013-R1**: The app MUST have one permission catalog listing every permission it can trigger
  (microphone, camera, local network, screen capture) with: its Info.plist key, the exact usage text,
  a short in-app name, the features that use it, when it is asked, and whether Settings can change it.
  It MUST record that the Photos library needs no permission (out-of-process picker).
- **FILE-013-R2**: The catalog MUST map each framework's status to one permission state
  (notDetermined, granted, denied, restricted) and give, for denied and restricted, the user-facing
  notice text and actions. Texts stay identical to today's (Clarifications).
- **FILE-013-R3**: The camera notice and the Local Network status MUST read their denied and
  restricted texts from the catalog and use one shared notice presentation (one container, the text,
  a separate Open Settings button, decorative symbol hidden); existing accessibility identifiers stay.
- **FILE-013-R4**: Every Open Settings action (microphone banner, camera notice, Local Network) MUST
  use one opener that opens the app's page in iOS Settings. Local Network's denial MUST offer Open
  Settings. Screen capture MUST NOT offer it.
- **FILE-013-R5**: Unit tests MUST cover, for every permission, the state mapping from injected
  framework statuses and the notice text and actions for denied and restricted.
- **FILE-013-R6**: A script MUST check that every usage-description key in the app target of
  `project.yml` has a catalog entry with the identical text and vice versa, that no Photos library
  key appears, and that the privacy policy's permission section names exactly the catalog's
  permissions; it MUST have tests in `scripts/test_scripts.py`.
- **FILE-013-R7**: A UI test MUST show the real microphone-denied path on the simulator (permission
  revoked with `simctl privacy` before the run) and skip, never pass, when the permission was not
  revoked.
- **FILE-013-R8**: UI tests MUST show denied and restricted behaviour for camera (stand-in), local
  network (DEBUG failure stand-in) and screen capture (fake source and fake availability), each under
  30 s; one of them proves Open Settings brings iOS Settings to the foreground.
- **FILE-013-R9**: `{device}`: on D1, deny and restrict (Screen Time) microphone, camera and local
  network in Settings, then use each feature; the notices match the catalog.
- **FILE-013-R10**: `docs/privacy-policy.md`'s permission section MUST match the catalog exactly.
- **FILE-013-R11**: No new permission, prompt, Info.plist key or networking; existing camera, OSC,
  status and guided-scene tests keep passing.

### Key Entities

- **Permission**: one of microphone, camera, local network, screen capture; key, usage text, name,
  features, prompt timing, settings-changeable flag.
- **Permission state**: notDetermined, granted, denied, restricted.
- **Permission notice**: the permission, state, text, whether Open Settings is offered.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FILE-013-S1**: 4 of 4 permissions have tested user-facing behaviour for both denied and
  restricted (unit tests for all 8 combinations; UI tests for every combination the app shows
  differently).
- **FILE-013-S2**: The catalog check passes on the repository and fails on each of at least 4 altered
  inputs (missing entry, extra entry, changed text, Photos key).
- **FILE-013-S3**: At least one denied state is exercised with the real system permission on the
  simulator (microphone).
- **FILE-013-S4**: The privacy policy names exactly the catalog's 4 permissions, checked by the script.
- **FILE-013-S5**: Every new UI test finishes in under 30 s; existing camera, OSC and guided-scene UI
  tests still pass.

## Assumptions

- iOS offers no restricted record-permission state and no Local Network status query; behaviour there
  derives from what iOS reports (denied, or the listener's policy-denied failure).
- The simulator has no rear camera, so the real camera path ends at "unavailable" before any
  permission check; the camera's denied and restricted UI are shown with the DEBUG stand-in, as in
  CAM-001.
- CaptureLab and RendererLab are internal harnesses outside the shipped app's catalog.
- Simulator results are never device evidence (Constitution X); the device checks are FILE-013-R9.
