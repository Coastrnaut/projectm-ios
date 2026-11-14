# Feature Specification: UIX-015 Onboarding Permission Explainer

**Feature Branch**: `feature/uix-015` (spec directory `108-uix-015-onboarding-permission-explainer`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (UIX-015-T01-T13 verified on the Mac and an own iOS 27.2 simulator; T14 `{device}` open)

**Input**: User description: "Implement UIX-015 (Onboarding permission explainer) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Explain camera, microphone and
local network permissions before system prompt." Acceptance, verbatim: "Denied permission has a clear
fallback and no repeated nagging." P0, effort M, depends on SCN-001 (integrated). Verification: SwiftUI
UI tests plus the simulator."

Identifiers in this feature carry the roadmap ID: requirements `UIX-015-R1…`, success criteria
`UIX-015-S1…`, tasks `UIX-015-T01…`. Other features are cited by their own IDs: FR-005 (microphone
explainer), FILE-013 (permission catalog and notices), CAM-001/CAM-002/CAM-013 (Camera visual), OSC-001
(OSC receiver), OSC-007 (listener badge), UIX-001 (guided first scene), ACC-011 (status events).

## Baseline: the audit (2026-11-14, commit `b75c685f`)

| Permission | Explainer before the system prompt | Denied today | Asks again? |
|---|---|---|---|
| Microphone | Yes: FR-005's sheet ("Microphone", the FR-005 text, Cancel / Continue) whenever the user picks Microphone while iOS has not asked yet; the acknowledgement lives in memory only | Status banner (contract text) with Open Settings and Choose source; other sources stay available | No: once iOS has an answer the explainer never shows; the banner appears only for the attempt that failed |
| Camera | **None**: picking the Camera visual in Settings starts the camera, and iOS's prompt appears at once | FILE-013 notice "Camera access is off. To show the camera, allow it in Settings." with Open Settings; the spectrum keeps running. The notice **cannot be dismissed** and does not say what still works | iOS asks once; the notice stays as long as the Camera visual is shown |
| Local Network | **None**: turning on OSC receiver opens the listener, and iOS's prompt appears at once | FILE-013 notice in Settings' OSC section (catalog text, Open Settings), replacing the status line; no popup | iOS asks once; with OSC left on, every launch retries the listener silently and the notice shows only in Settings |
| Screen capture | iOS's own picker each time (out of scope: no app prompt to precede) | Banner with Restart and Choose source | iOS's picker is the explainer |
| MIDI (MIDI-001) | No permission needed | — | — |
| Photos | No permission (FILE-013) | — | — |

Findings: (1) camera and local network have no explainer; (2) the camera's denied notice names no
fallback and cannot be dismissed; (3) the local network notice names no fallback; (4) the
microphone's explainer pattern (FR-005) exists but is not shared.

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative option.

- Q: When is a camera or local network explainer shown? → A: Only when the user picks the feature that
  needs the permission (the Camera visual row in Settings; turning on OSC receiver), only while iOS has
  not asked yet, and only if the user has not already continued past this explainer. Never at launch,
  never unprompted. Applied to UIX-015-R1, R2.
- Q: What do the buttons do? → A: "Continue" records that the permission was explained and goes ahead
  with the user's pick, so iOS's prompt appears next. "Not now" cancels the pick: no prompt, the
  previous visual or OSC off stays. Applied to UIX-015-R3, R4.
- Q: Does the microphone change? → A: No. FR-005's explainer, its text and its buttons are fixed by
  feature 001's contract (`contracts/ui-states.md`). The microphone already meets the rules: iOS reports
  whether it has asked, and the explainer shows only before that. Applied to UIX-015-R9.

### Session 2026-11-14 (speckit-clarify)

Five questions, each answered by Claude with the recommended option (owner rule 4).

- Q: CAM-001-R5 says the camera notice stays while the camera cannot show pictures; may the user
  dismiss the denied or restricted notice? → A: Yes, for denied and restricted only (the permission
  notices). Dismiss hides it for the current attempt; the spectrum keeps running and the visual's
  VoiceOver value still says "Camera access off". Choosing the Camera visual again is a new attempt.
  Interrupted, failed and no-camera notices keep CAM-001/CAM-013's rules (no Dismiss). This refines
  CAM-001-R5 for the permission notices. Applied to UIX-015-R7.
- Q: How do the many existing UI tests that pick Camera or turn on OSC avoid the new explainer? → A: As
  UIX-001's guided scene: in DEBUG or automation builds, a harness launch (an `-uitest…` argument,
  `-autostart`, XCTest or `PROJECTM_AUTORUN`) suppresses the explainer, unless the launch passes
  `-uitestPermissionExplainers`. Release builds never suppress it. Applied to UIX-015-R13.
- Q: How is the explainer presented? → A: As a sheet, the same pattern as FR-005's microphone sheet:
  a decorative symbol, the catalog's name as title, the catalog's usage text, a fallback line, then
  "Continue" (prominent) and "Not now". It scrolls, and at accessibility text sizes the buttons stack.
  Applied to UIX-015-R5, R12.
- Q: Should a local network denial turn OSC receiver off? → A: No. OSC-001 keeps the user's toggle;
  the denial stays an inline notice in Settings' OSC section with Open Settings and the fallback. iOS
  never asks twice, so the listener's quiet retry at launch shows nothing outside Settings. Applied
  to UIX-015-R8.
- Q: Does the microphone get a stored explained flag? → A: No. iOS reports whether it has asked, which
  is the flag; FR-005's in-memory acknowledgement is kept. Only camera and local network store a flag
  (two keys). Applied to UIX-015-R9, R11.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - I know why the app wants the camera or the network before iOS asks (Priority: P1)

A user picks the Camera visual (or turns on OSC receiver) for the first time. Before iOS's prompt, the
app shows a short explanation: what the permission is for, that nothing leaves the device, and what
happens if they decline. They choose Continue (iOS asks next) or Not now (nothing is asked).

**Why this priority**: the roadmap's observable behavior; a system prompt without context is the most
common reason people decline.

**Independent Test**: with a never-asked camera stand-in, pick Camera: the explainer appears; Not now
leaves the previous visual and asks nothing; picking Camera again and Continue starts the camera.

**Acceptance Scenarios**:

1. **Given** camera access was never asked, **When** the user picks the Camera visual, **Then** the
   camera explainer appears and the camera has not started.
2. **Given** the camera explainer is shown, **When** the user chooses Not now, **Then** the explainer
   closes, the visual stays as it was, and no permission prompt appears.
3. **Given** the camera explainer is shown, **When** the user chooses Continue, **Then** the Camera
   visual is chosen and the camera asks for access.
4. **Given** local network access was never asked, **When** the user turns on OSC receiver, **Then**
   the local network explainer appears and OSC stays off until the user chooses Continue.

### User Story 2 - Declining leaves a working app and no nagging (Priority: P1)

A user who declined sees, once per attempt to use the feature, what is off and what still works, can
dismiss the notice, and is never shown the explainer again for that permission.

**Why this priority**: the roadmap's acceptance.

**Independent Test**: deny each permission (stand-in or real), use its feature twice, count explainers
and notices.

**Acceptance Scenarios**:

1. **Given** the user continued and then declined the camera, **When** they pick Camera again, **Then**
   no explainer appears; the camera notice appears with the fallback "Showing the spectrum only." and
   Open Settings and Dismiss.
2. **Given** the camera notice is shown, **When** the user dismisses it, **Then** it stays hidden while
   this Camera visual is shown (opening and closing Settings does not bring it back); picking Camera
   again is a new attempt and shows it once more.
3. **Given** local network access was declined, **When** the user turns OSC receiver on again, **Then**
   no explainer appears; the OSC section shows the denied notice with the fallback that OSC control is
   unavailable and everything else works.
4. **Given** the microphone was declined, **When** the user picks Microphone, **Then** no explainer
   appears and the banner offers Open Settings and Choose source (FR-005, FILE-013, unchanged).

### Edge Cases

- The user continued but the app ended before iOS's answer: iOS asks at the next use; the explainer is
  not shown again (it was explained).
- The user had OSC on before this feature (an update): iOS has already asked, so turning OSC off and on
  shows no explainer (OSC enabled at launch, or an observed listening or denied state, counts as
  explained).
- The device has no camera at the chosen position: iOS never asks, so no explainer; CAM-002's "No rear
  camera…" notice applies.
- Camera restricted (Screen Time): iOS cannot ask, so no explainer; FILE-013's restricted notice with
  the fallback.
- The explainer appears while VoiceOver runs: it reads the title, the text and both buttons; no
  announcement is posted for it.
- Accessibility text sizes: the explainer scrolls and its buttons stack vertically.
- UI tests that are not about explainers launch with harness arguments; the explainer is suppressed
  there unless `-uitestPermissionExplainers` is passed (as UIX-001's guided scene).

## Requirements *(mandatory)*

### Functional Requirements

- **UIX-015-R1**: Picking the Camera visual in Settings while camera access was never asked (and the
  camera explainer was not continued before) MUST show the camera explainer instead of choosing the
  visual.
- **UIX-015-R2**: Turning on OSC receiver while the local network explainer was not continued before
  MUST show the local network explainer instead of turning OSC on. iOS reports no local network
  status, so "explained" is recorded when the user continues, when OSC was already on at launch, and
  when the listener is seen listening or denied.
- **UIX-015-R3**: The explainer MUST offer Continue, which records the permission as explained and
  performs the pick (iOS's prompt follows), and Not now, which cancels the pick without any prompt.
- **UIX-015-R4**: After Not now, nothing is recorded; the next pick of the feature shows the explainer
  again (the user asked for the feature; the prompt has still not been shown).
- **UIX-015-R5**: The explainer texts MUST come from the permission catalog: the title is the catalog's
  name, the body is the catalog's usage text (identical to the Info.plist text), and a fallback line
  says what happens if the user declines.
- **UIX-015-R6**: An explained, denied or restricted permission MUST never show its explainer again.
- **UIX-015-R7**: The camera's denied and restricted notices MUST name the fallback ("Showing the
  spectrum only.") and offer Dismiss next to Open Settings. A dismissed notice stays hidden until the
  next attempt (the Camera visual is chosen again); it is never shown at launch.
- **UIX-015-R8**: The local network denied notice MUST name the fallback (OSC control is unavailable;
  everything else works). It stays inline in Settings' OSC section and never appears elsewhere.
- **UIX-015-R9**: The microphone keeps FR-005's explainer, texts and actions, and its denied banner,
  unchanged.
- **UIX-015-R10**: Contract-fixed texts (FR-005, the microphone and screen-capture banners, CAM-001's
  notices) MUST NOT change.
- **UIX-015-R11**: The explained flags MUST be stored on the device only, listed in the privacy
  review's allowed keys, and cleared by `-uitestResetNotice`.
- **UIX-015-R12**: The explainer MUST work at accessibility text sizes and with VoiceOver, use no
  animation of its own, and post no announcement.
- **UIX-015-R13**: In DEBUG or automation builds a harness launch suppresses the explainer unless it
  passes `-uitestPermissionExplainers`; Release builds never suppress it.

### Key Entities

- **Explainer decision**: for one permission, from its status (never asked, granted, denied,
  restricted, or unknown) and whether it was explained: show the explainer, or go ahead.
- **Explained flag**: one stored yes per permission (camera, local network), set once, never cleared
  except by a test reset.
- **Notice dismissal**: per attempt, in memory; a new attempt shows the notice again.

## Privacy review *(Constitution, Privacy)*

Two new on-device keys hold a yes per permission; no personal data, nothing sent. No new permission and
no new usage text.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **UIX-015-S1**: For camera and local network, the explainer appears before iOS's prompt in 100% of
  first picks, and never at launch.
- **UIX-015-S2**: After a denial, using the feature twice shows the explainer zero times and the
  fallback text each attempt.
- **UIX-015-S3**: Not now leads to zero permission prompts.
- **UIX-015-S4**: The explainer is readable and both buttons reachable at the largest accessibility
  text size.

## Assumptions

- The simulator cannot script camera or local network prompts; UI tests use the existing stand-ins
  (`-uitestCamera`, `-uitestOSCFailure localNetworkDenied`) and the microphone's real revoke.
- A physical-device check of the real prompts is a `{device}` task.
