# Feature Specification: CAM-003 Camera Lens Selection

**Feature Branch**: `feature/cam-003` (spec directory `204-cam-003-lens-selection`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (CAM-003-T01-T10 verified on the Mac with the stand-in camera; device task T11 `{device}` open)

**Input**: User description: "Implement CAM-003 (Camera lens selection) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Offer available wide, ultrawide
and telephoto devices only." Acceptance, verbatim: "Unavailable lens is hidden; switching never
crashes active session." P2, depends on CAM-001 (integrated); builds on CAM-002 (front camera) and
CAM-013 (failure recovery)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `CAM-003-R1…`, success criteria `CAM-003-S1…`, tasks `CAM-003-T01…`. Requirements
of other features are cited by their own IDs: CAM-001-R6, R7, R9, R11, R13; CAM-002-R1, R6, R7, R8,
R10; CAM-012 (badge, Stop camera); CAM-013 (interruptions, Retry); FILE-005 (settings backup);
FILE-013 (permission catalog).

The constitution's Privacy section requires a specification and a privacy review for a sensor. A
lens is another camera of the same kind; this specification extends CAM-001's and CAM-002's review
(section "Privacy review").

## Baseline: what exists today (audit of 2026-11-14, commit `7a07c74e`)

The row's gap status is "Gap candidate; re-audit at implementation". The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Camera visual | Settings › Visual › "Camera" shows the chosen camera (CAM-002: Back or Front) under a circular spectrum. The camera starts only on that choice and runs only while the visual is shown, running and in the foreground (CAM-001-R7). | The back camera is always the wide-angle lens. |
| Camera switch | CAM-002 switches Back/Front on a running session by replacing its input; the slot is closed until the new camera's first picture; a missing camera reports "unavailable" without asking. | No lens switch; no rule for a lens whose input cannot be opened. |
| Device discovery | The app asks only for the default wide-angle camera at a position. | No list of the lenses a device has. |
| Stand-in camera | `StubCameraFrameProvider` simulates permission scenarios, both positions, interruptions and failures for tests, the simulator and DEBUG UI tests. | No lenses, no failing input. |
| Settings | Section "Camera" (while Camera is the visual): Camera Back/Front, Mirror, Crop, Anchor, Zoom. | No lens row. |
| Permission | One iOS camera permission covers every camera; the usage text names "the front or rear camera you choose". | Nothing: a lens is a rear camera. |

## Clarifications

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Which cameras count as "wide, ultrawide and telephoto devices"? → A: The back camera's single physical lenses of those three kinds only. Virtual multi-lens cameras (dual, dual wide, triple), which switch lenses on their own, front lenses, LiDAR and external cameras are never offered (CAM-003-R1). Rejected: offering the virtual triple camera with a zoom slider (not a lens choice, and it changes lenses behind the user's back).
- Q: How are the lenses named, and what control is used? → A: A segmented choice "Lens" with Apple's names "Ultra Wide", "Wide", "Telephoto", in that order (widest first), like the existing Camera Back/Front row (CAM-003-R2, R11). Rejected: zoom factors ("0.5×", "1×", "3×"): the telephoto factor differs per device and would need per-device text.
- Q: Where is the choice offered? → A: In Settings › Camera only, while Back is selected and the device has at least two lenses (CAM-003-R2). A one-lens device and the front camera show no row at all, so nothing disabled or unavailable is ever shown. Rejected: a lens button in the visualizer's controls (more on-screen controls over the picture; can come with CMP-015).
- Q: What does the user see when a lens cannot be opened? → A: The previous lens keeps running and the Lens choice returns to it; no extra notice, because the camera keeps working (CAM-003-R6). Only when no lens at all can be added does CAM-002's existing "unavailable" notice appear (R7). Rejected: a new notice for a failed switch (a new status event for a rare, self-healing case).
- Q: How is the choice stored, and what if the device lacks it? → A: As the raw identifier ("wide", "ultraWide", "telephoto") under one new settings key, included in the settings backup and the Settings erase; any unknown or missing value, and any lens this device lacks, is used as Wide, while the stored value is kept until the user picks another lens (CAM-003-R4, R5). Rejected: overwriting the stored lens with Wide on a device that lacks it (a restored backup would lose the choice for the other device).
- Q: When a chosen lens cannot be opened, does the stored choice change? → A: Yes, after the user's own choice: once the switch ends, the stored lens follows the lens actually running, so the row, the next start and a return from Front all agree (CAM-003-R6). A lens that is merely missing on this device (restored backup) keeps its stored value (R5). Found while running CAM-003-T09: without it, returning from Front retried the failing lens and fell back to Wide.
- Q: Does listing lenses need camera permission, and is it covert use? → A: Listing reads the system's list of built-in cameras; it opens no camera, captures nothing, shows no indicator and asks for nothing, so it is allowed before consent (CAM-003-R3). The camera itself still starts only on the user's choice of Camera with permission granted (CAM-001-R7), with iOS's indicator and the app's badge.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Pick the lens the device has (Priority: P1)

A viewer with Camera chosen and the back camera selected sees a "Lens" choice in Settings listing
exactly the back lenses this device has, for example "Ultra Wide" and "Wide" on an iPhone 15. Picking
"Ultra Wide" shows the wider picture under the spectrum. A device with only one back lens shows no
Lens choice at all.

**Why this priority**: It is the row's observable behavior and the first half of its acceptance.

**Independent Test**: With stand-in inventories (wide only; wide and ultra wide; all three) the Lens
choice is absent, offers two, and offers three lenses respectively.

**Acceptance Scenarios**:

1. **Given** a device whose back camera has only the wide lens, **When** the user opens the Camera
   section, **Then** no Lens choice is shown.
2. **Given** a device with wide and ultra wide back lenses, **When** the user opens the Camera
   section with Back selected, **Then** the Lens choice offers exactly "Ultra Wide" and "Wide", and
   no telephoto entry exists (hidden, not disabled).
3. **Given** a device with all three, **Then** the choice offers "Ultra Wide", "Wide" and "Telephoto".
4. **Given** Front is selected, **Then** no Lens choice is shown.

---

### User Story 2 - Switching never breaks the running camera (Priority: P1)

While the camera runs, the viewer switches lenses repeatedly. Each switch shows the new lens's
picture as soon as it arrives; if a lens cannot be opened, the camera keeps showing the lens it had
and the choice returns to it. The app never crashes, the camera never ends up without a picture
source, and the audio and frame loop keep running.

**Why this priority**: It is the second half of the acceptance.

**Independent Test**: With a stand-in session, switch through every lens several times while it
runs, including to a lens whose input fails; after every switch the session runs with exactly one
input.

**Acceptance Scenarios**:

1. **Given** the camera runs on Wide, **When** the user picks Ultra Wide, **Then** the session keeps
   running, its input becomes the ultra wide lens and the picture of the wide lens is not shown after
   the switch.
2. **Given** the camera runs, **When** the user picks a lens whose input cannot be opened, **Then**
   the previous lens keeps running, the choice shows the previous lens, and nothing crashes.
3. **Given** the camera runs, **When** the user switches lenses ten times in a row, **Then** after
   each switch the session runs with exactly one input.

---

### User Story 3 - The choice is remembered, safely (Priority: P2)

The chosen lens is remembered across launches as an ordinary setting. On a device that lacks the
remembered lens (a restored backup, a different device), the wide lens is used and shown as
selected; the stored choice never starts the camera by itself.

**Independent Test**: Store "telephoto", give the app a wide and ultra wide inventory: the effective
lens and the shown selection are Wide.

**Acceptance Scenarios**:

1. **Given** Ultra Wide was chosen, **When** the app is relaunched and Camera chosen, **Then** the
   ultra wide lens runs.
2. **Given** Telephoto is stored and the device has no telephoto lens, **Then** Wide runs and is
   shown as selected.

### Edge Cases

- A lens disappears between the list and the switch (input cannot be opened): the previous lens
  keeps running (R6).
- Neither the new lens nor the previous one can be re-added: the wide lens is tried; if that also
  fails the feed reports "unavailable" with the existing notice (R7), never a crash.
- Switching while access is undecided, denied or restricted: only recorded; no prompt (CAM-002 rule).
- Switching while interrupted or failed: the camera starts again on the new lens (as CAM-002-R7).
- Switching Back → Front: the front camera always uses its wide lens; returning to Back restores the
  chosen back lens.
- No camera at all (simulator, `unavailable` scenario): no Lens choice; nothing asked.

## Requirements *(mandatory)*

### Functional Requirements

- **CAM-003-R1**: The app MUST list the back camera's lenses of three kinds only, wide, ultra wide
  and telephoto, that this device actually has; virtual multi-lens cameras and other kinds are not
  offered.
- **CAM-003-R2**: A Lens choice MUST appear in Settings › Camera only while the Camera visual is
  chosen, Back is selected and at least two lenses are listed; it offers exactly the listed lenses in
  the order Ultra Wide, Wide, Telephoto. An unavailable lens is hidden, never shown disabled.
- **CAM-003-R3**: Listing lenses MUST NOT turn the camera on, ask for permission, or capture any
  picture.
- **CAM-003-R4**: The chosen lens MUST be stored as an ordinary setting (included in the FILE-005
  settings backup and erased with the other settings); it never starts the camera (as CAM-002-R6).
  It is not stored in scenes or show cues.
- **CAM-003-R5**: When the stored lens is not listed on this device, the wide lens MUST be used and
  shown as selected; the stored value is kept until the user picks another lens.
- **CAM-003-R6**: Choosing a lens while the back camera starts or runs MUST switch lenses on the
  running session without stopping it: the new lens's input replaces the old one in one
  configuration change; when the new input cannot be created or added, the previous input stays, the
  feed keeps running and the selection returns to the previous lens.
- **CAM-003-R7**: After any lens switch the session MUST have exactly one camera input, or, only when
  no lens can be added at all (previous and wide included), the feed MUST report "unavailable" with
  CAM-002's notice. A lens switch MUST never crash the app.
- **CAM-003-R8**: After a lens switch no picture of the previous lens is drawn (as CAM-002-R7); the
  frame loop, the analysis and the audio source keep running; the "Camera on" badge stays.
- **CAM-003-R9**: The front camera always uses its wide lens; the back lens choice is kept while
  Front is selected.
- **CAM-003-R10**: The stand-in camera MUST simulate a lens inventory and lenses whose input fails,
  so the simulator and tests exercise R1 to R8 without a camera (CAM-001-R13).
- **CAM-003-R11**: The Lens choice MUST have an accessibility label "Lens" and the chosen lens's name
  as its value.

### Key Entities

- **Camera lens**: wide, ultra wide or telephoto; a name for display; stored by its identifier.
- **Lens inventory**: the back lenses this device has, in display order.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CAM-003-S1**: For each of three inventories (wide only; wide + ultra wide; all three) the Lens
  choice shows exactly 0, 2 and 3 entries respectively, matching the inventory (acceptance, first
  half).
- **CAM-003-S2**: 30 consecutive lens switches on a running stand-in session, a third of them to a
  failing lens, end with zero crashes, the session running and exactly one input after every switch
  (acceptance, second half).
- **CAM-003-S3**: A stored lens missing on the device resolves to Wide in 100% of cases.
- **CAM-003-S4**: On D1 (iPhone 15) Wide ↔ Ultra Wide switches show the new lens's picture and never
  stop the session; on D2 and D3 no Lens choice is shown (device stage, last).

## Privacy review *(Constitution, Privacy; extends CAM-001's and CAM-002's review)*

| Question | Answer |
|---|---|
| What is captured? | The chosen back lens's live picture, only while the Camera visual is on screen in the foreground (CAM-001-R7). Changing lens changes nothing else. |
| When does capture start? | Only after the user chooses Camera in this session and iOS's camera permission is allowed. Listing lenses opens no camera (R3); a stored lens never starts the camera (R4). |
| Who sees it? | As CAM-002: the person at the screen and an external display the user connected; iOS's indicator and the app's badge are shown. |
| Is anything stored? | The lens choice (an identifier, no picture). Pictures as CAM-002. |
| Is anything sent or analysed? | No. |
| App Store privacy label | Unchanged: Data Not Collected. |

## Assumptions

- The usage description already names "the front or rear camera you choose"; a lens is a rear camera,
  so the permission catalog and privacy policy are unchanged.
- Test devices: D1 iPhone 15 has wide and ultra wide back lenses; D2 iPad Pro M5 and D3 iPad A16 have
  one back lens. No test device has a telephoto lens, so telephoto is verified with the stand-in only.
- Lens zoom factors, macro and focus controls are out of scope.
