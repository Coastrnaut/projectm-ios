# Feature Specification: REC-011 Export to Photos

**Feature Branch**: `feature/rec-011` (spec directory `210-rec-011-export-to-photos`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement REC-011 (Export to Photos) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Save completed image or video only after explicit user action." Acceptance,
verbatim: "Permission denial leaves local original intact and shows error." P1, M, depends on REC-001
(integrated); REC-003, REC-010, REC-012 and FILE-013 are integrated too."

Identifiers carry the roadmap ID: requirements `REC-011-R1…`, success criteria `REC-011-S1…`, tasks
`REC-011-T01…`, research decisions `REC-011-D1…`.

## Baseline: what exists today (audit of 2026-11-14, commit `9baece96`)

| Area | Today |
|---|---|
| Still frames (REC-001) | "Frame ready" offers the encoded still (PNG, HEIC or JPEG) held in memory: Save… (file exporter), Share…, Discard. |
| Recordings (REC-003, REC-010) | "Recording ready" offers `<tmp>/Recordings/<name>.mp4`: Save… (file mover), Share…, Keep (into Recordings), Discard. Settings › Storage › Recordings lists kept files with Play, Share…, Rename, Delete. |
| Share sheet (REC-012) | A temporary copy is shared; Save Image/Video to Photos and Assign to Contact are excluded (REC-012-R7). |
| Permissions (FILE-013) | Four: Microphone, Camera, Local Network, Screen recording. `check_permission_catalog.py` fails on any Photos library key; `PermissionCatalogTests` and `CaptureShareAppTests` assert none exists. The Photos picker (MED-001/002) needs none. |
| Announcements (ACC-011) | Capture results announce through `StatusEventRouter` (X6-X8 frame and share notices on the capture lane); REC-010 announces on the library lane. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the conservative, local-first option.

- Q: Which Photos access does the app ask for? → A: **Add only** (iOS's "Add Photos Only"). The app never reads, lists or changes the user's library; full library access is never requested and its usage key stays forbidden. This is the least privilege that can save; it overrides FILE-013's "no Photos key" rule and REC-012-R7's "no Photos permission" for the add-only key only (ADR).
- Q: Where is Save to Photos offered? → A: As an explicit button on the "Frame ready" panel, the "Recording ready" panel and each readable row of Settings › Storage › Recordings. Nothing is saved automatically: not on capture, not on recording finish, not on Keep.
- Q: When is the permission requested? → A: Only when the user taps Save to Photos and iOS has not asked yet. Never at launch, on capture, on recording finish or on opening Recordings.
- Q: What happens to the local original on any outcome? → A: It is never moved, changed or deleted by Save to Photos: the offered frame stays offered, the offered recording stays offered at its path, a library file stays in Recordings. The user still decides with Save…, Share…, Keep or Discard.
- Q: Does the share sheet now offer its own Save to Photos? → A: No. It stays excluded, so the one way into Photos is the explicit button with the app's own error handling.
- Q: What does the user see on denial or restriction? → A: A notice naming the problem, saying the file is still in the app, with Open Settings (iOS has a switch for this app); it is announced.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Save a finished frame or recording to Photos (Priority: P1)

A performer saves a frame they like, or a finished recording, into their photo library to post later.

**Why this priority**: It is the roadmap row.

**Independent Test**: With access granted (an injected authorization), tapping Save to Photos on an offered frame or recording saves it exactly once, shows and announces "Saved to Photos.", and the offer stays.

**Acceptance Scenarios**:

1. **Given** a frame is offered and access is granted, **When** the user taps Save to Photos, **Then** one photo is added to the library, "Saved to Photos." is shown and announced and the frame stays offered.
2. **Given** a recording is offered and iOS has not asked yet, **When** the user taps Save to Photos, **Then** iOS asks for add-only access; on Allow the video is added once and the recording file stays where it was.
3. **Given** a kept recording in Settings › Storage › Recordings, **When** the user taps Save to Photos on its row, **Then** the video is added and the file stays in Recordings.

---

### User Story 2 - Denied or failed save keeps the original (Priority: P1)

**Why this priority**: It is the roadmap acceptance.

**Independent Test**: With access denied, restricted, or a save that fails, the offered recording file is byte-identical afterwards, still offered, and an error notice is shown and announced.

**Acceptance Scenarios**:

1. **Given** access is denied, **When** the user taps Save to Photos, **Then** nothing is added, the original is unchanged and still offered, and "Photos access is off …" is shown with Open Settings and announced.
2. **Given** access is restricted (Screen Time or management), **Then** the restricted notice is shown, the original is unchanged.
3. **Given** access is granted but the save fails, **Then** "The file couldn't be saved to Photos. It is still in the app." is shown, the original is unchanged.

---

### User Story 3 - No surprise prompts (Priority: P1)

**Independent Test**: Launching, capturing a frame, finishing a recording, keeping it and opening Recordings never query or request Photos access.

### Edge Cases

- The user taps Save to Photos twice quickly: one save runs; the second tap is ignored while saving.
- The user taps Discard or Keep while a save of that recording runs: those actions wait (disabled) until the save ends, so the file cannot vanish mid-save.
- "Limited" access (not used for add-only, but reported by some iOS versions) counts as granted.
- An incomplete library file offers no Save to Photos (as it offers no Play or Share).

## Requirements *(mandatory)*

### Functional Requirements

- **REC-011-R1**: The "Frame ready" and "Recording ready" panels and each readable Recordings row MUST offer a labeled **Save to Photos** button.
- **REC-011-R2**: The app MUST query or request Photos access only inside a Save to Photos action the user started; launch, capture, recording finish, Keep and opening Recordings MUST NOT.
- **REC-011-R3**: The app MUST request add-only access, declare only the add-only usage text, and never read the photo library.
- **REC-011-R4**: When iOS has not asked yet, the action MUST request access and continue with the answer.
- **REC-011-R5**: With access granted (or limited), the item MUST be added exactly once: a still from its encoded bytes, a recording from its file without moving it.
- **REC-011-R6**: Every outcome MUST leave the local original unchanged: the offered frame and recording stay offered, the recording and library files keep their path and bytes.
- **REC-011-R7**: Denied MUST show "Photos access is off. To save to Photos, allow adding photos for projectM in Settings." with Open Settings; restricted MUST show "Saving to Photos is restricted on this device." with Open Settings; both add "The file is still in the app."
- **REC-011-R8**: A failed save MUST show "The file couldn't be saved to Photos. It is still in the app."; success shows "Saved to Photos.".
- **REC-011-R9**: Every outcome text MUST be announced through the status-event router (capture lane), and shown as a dismissible notice.
- **REC-011-R10**: While a save runs, Save to Photos MUST be disabled, and Keep, Discard, Rename and Delete MUST be disabled for the item being saved.
- **REC-011-R11**: The share sheet MUST keep excluding Save to Photos and Assign to Contact.
- **REC-011-R12**: The permission catalog, Info.plist, privacy policy "Permissions and why" and the catalog check MUST list Photos (add only); the full-library key MUST remain forbidden.
- **REC-011-R13**: DEBUG `-uitestPhotosAccess granted|denied|restricted|failing` MUST replace the Photos service with a stand-in so UI tests never show a system prompt.

### Key Entities

- **PhotosAccess**: notDetermined, granted, denied, restricted (from iOS's add-only status).
- **PhotosSaveOutcome**: saved, denied, restricted, failed; each with its notice text.

## Success Criteria *(mandatory)*

- **REC-011-S1**: Denied, restricted and a failed save each leave the original recording byte-identical and still offered, and show the error (unit tests with injected access).
- **REC-011-S2**: Granted saves exactly once per tap; not-determined requests access exactly once and then saves.
- **REC-011-S3**: Zero access queries or requests at launch, on frame capture, recording finish, Keep and opening Recordings.
- **REC-011-S4**: The catalog check, privacy manifest check and permission catalog tests pass with exactly five permissions and no full-library key.
- **REC-011-S5**: A UI test drives Save to Photos to the denied notice with Open Settings in under 30 s.

## Assumptions

- Photos' own saving is out-of-process; the stand-in replaces it for UI tests, and the real path is checked on the simulator with `simctl privacy` and on a device (`{device}` task).
- No new setting or UserDefaults key is needed.
- Videos are the app's MP4 (HEVC or H.264) and stills PNG, HEIC or JPEG; Photos accepts all of them.
