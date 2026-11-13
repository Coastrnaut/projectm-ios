# Feature Specification: REC-012 Share via Files

**Feature Branch**: `feature/rec-012` (spec directory `060-rec-012-share-via-files`)

**Created**: 2026-11-13

**Status**: Clarified 2026-11-13 (9 questions answered under owner rule 4)

**Input**: User description: "Implement REC-012 (Share via Files) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Export video or image using system
share sheet with local temporary URL." Acceptance, verbatim: "Share cancellation retains original and
cleans temporary copy." P0, effort S, depends on REC-001 (integrated; REC-003 video recording is
integrated too). Verification: simulator + device (AirDrop, Messages, Save to Files on D1). A Share…
action next to Save for finished stills and recordings; a temporary copy in an app-owned temporary
folder; cleanup on completion, on cancel and at launch; the original stays offered until dismissed;
the Photos activity excluded; no network by the app; privacy policy updated."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `REC-012-R1…`, success criteria `REC-012-S1…`, tasks `REC-012-T01…`. Requirements of
other features are cited by their own IDs: REC-001 (still frame capture,
`specs/055-rec-001-still-frame-capture`), REC-003 (video recording, `specs/058-rec-003-video-recording`,
ADR-0027), REC-011 (export to Photos, not built), FR-065 (what the app may store), FR-070
(accessibility), PRE-014 (preset export, which already shares one archive through the share sheet).

## Baseline: what exists today (audit of 2026-11-13, commit `97977c7`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| Still frames (REC-001) | After Save Frame the encoded picture goes straight to the system Files exporter; cancelling it releases the picture (REC-001-R10). | No share sheet; a cancel loses the picture. |
| Recordings (REC-003) | The finished temporary file goes straight to the system file mover; cancelling deletes it (REC-003-R13). | No share sheet; a cancel loses the recording. |
| Share sheet | PRE-014 shares one preset archive through the system share sheet and deletes it when the sheet closes. | Not available for pictures or videos. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: What is "the original" that a cancelled share must retain, and how long is it retained? → A: The result the user just made: for a still, the encoded picture (held in memory); for a video, the finished recording (the temporary file REC-003 already writes). After Save Frame or a recording, the visualizer offers the result in a small "ready" panel with Save…, Share… and Discard. The result stays offered after a cancelled or completed share, and after a cancelled Save…, until the user saves it to Files (the file then lives where the user put it), taps Discard, or replaces a still with a new Save Frame. Nothing is kept beyond the app session: a still is memory only, and a recording left over at the next launch is deleted (REC-003-R13). Rejected: keep results in an app library (that is REC-010, with its own storage and deletion rules); release the result after any share (a cancel would lose the user's work, which the acceptance forbids).
- Q: Should Save… still open the Files sheet by itself when the result is ready, as REC-001 and REC-003 do today? → A: No. The ready panel offers Save… and Share… side by side and nothing opens by itself; the user picks. One more tap for Save, but the user chooses the destination kind first and a cancelled sheet no longer loses the result. Rejected: open Files first and offer Share… only after it is cancelled (Share would be hidden behind a sheet the user may not want).
- Q: Does the share sheet get the original file, or a copy? → A: A copy, made when the user taps Share…, in an app-owned temporary folder (`<tmp>/Sharing/<random>/`) under a descriptive name ("Visualizer Frame 2026-11-13 at 14.05.32.png", "Visualizer Recording 2026-11-13 at 14.05.32.mp4"). The copy is deleted when the sheet reports that the share completed or was cancelled (or failed), and every leftover copy is deleted at the next launch. The original is never handed to another app, so nothing another app does can change or remove it. Rejected: share the original recording file (a share would then race the later Save… or Discard); share in-memory data without a file (receivers get a generic name and type).
- Q: Which share sheet activities are offered? → A: Everything the system offers for a file (AirDrop, Messages, Mail, Save to Files, other apps the user has), except Save Image/Save Video to Photos and Assign to Contact, which the app excludes. Saving to Photos needs a Photos add permission and its own rules (REC-011); assigning a frame to a contact writes into Contacts. The app requests no new permission. Rejected: allow Save to Photos now (a permission prompt and a usage string this row does not need; REC-011 owns it).
- Q: Which share sheet API? → A: The system activity view controller (`UIActivityViewController`) with its completion handler, which says whether the share completed or was cancelled and so tells the app when to delete the copy. SwiftUI's `ShareLink` gives no completion, so the copy could only be swept at launch. Rejected: `ShareLink`.
- Q: Can a new recording start while a recording is still offered? → A: No. Record refuses with "Save, share or discard the last recording first." so a recording is never deleted without the user's choice. A new Save Frame replaces an offered still (the user asked for a new picture; a still is quick to make again). Rejected: replace an offered recording (could lose up to 10 minutes of work silently).
- Q: What does the user see after the share sheet closes? → A: After a completed share, the notice "Shared." (an accessible element like the other notices, FR-070); after a cancel, nothing new: the ready panel simply stays. After an error, "The file couldn't be shared.". The panel stays in every case. Rejected: a notice on cancel too (noise for a deliberate action); hiding the panel after a completed share (the user may want to save it or share it again).
- Q: Does an offered result survive changing the visual, pausing, blacking out the output or the app going to the background? → A: Yes, all of them: the result was made before and is not the live picture, so Save…, Share… and Discard keep working (sharing never shows the current screen). Only the end of the app process ends it (a still is in memory; a recording's file is deleted at the next launch). Rejected: discard on blackout (the blackout hides the screen, not results the user already made; discarding would lose work).
- Q: Can a still and a recording be offered at the same time? → A: Yes; each kind has its own ready panel ("Frame ready", "Recording ready") with its own buttons and identifiers, and one share sheet at a time (the sheet is modal). Rejected: one shared panel (a new capture would hide the recording's buttons).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Share a frame or a recording (Priority: P1)

A user saved a frame (or finished a recording) and wants to send it to a friend. The visualizer
offers the result with Save…, Share… and Discard. They tap Share…; the system share sheet opens with
the file under a descriptive name; they pick AirDrop, Messages, Save to Files or another app.

**Why this priority**: It is the row's observable behavior.

**Independent Test**: Simulator UI test with the DEBUG share simulation; on a device, AirDrop,
Messages and Save to Files from the sheet (owner).

**Acceptance Scenarios**:

1. **Given** a frame was just captured, **When** the user taps Share…, **Then** the share sheet opens with one PNG or HEIF file named "Visualizer Frame <date> at <time>".
2. **Given** a recording just finished, **When** the user taps Share…, **Then** the share sheet opens with one MP4 file named "Visualizer Recording <date> at <time>".
3. **Given** the share sheet is open, **When** the user completes a share, **Then** the temporary copy is deleted and the result is still offered.

---

### User Story 2 - Cancelling a share keeps the original (Priority: P1)

The user opens the share sheet and closes it without sharing. The result is still offered (they can
save or share it later), and the temporary copy is gone.

**Why this priority**: It is the row's acceptance.

**Independent Test**: Unit tests of the share-file lifecycle and the UI test's simulated cancel.

**Acceptance Scenarios**:

1. **Given** the share sheet is open, **When** the user cancels it, **Then** the result is still offered and the sharing folder holds no copy.
2. **Given** a cancelled share, **When** the user taps Save…, **Then** the Files sheet gets the same picture or recording.
3. **Given** the app ended while a share sheet was open, **When** the app starts again, **Then** the leftover copy is deleted.

---

### User Story 3 - Done with the result (Priority: P2)

The user saves the result to Files or taps Discard; the panel goes away. A discarded recording's
temporary file is deleted.

**Independent Test**: Unit tests.

**Acceptance Scenarios**:

1. **Given** a result is offered, **When** the user taps Discard, **Then** the panel disappears and a recording's temporary file is deleted.
2. **Given** a result is offered, **When** Save… completes, **Then** the panel disappears with "Frame saved." or "Recording saved."
3. **Given** Save… is cancelled, **Then** the result is still offered.

### Edge Cases

- The temporary copy cannot be made (storage full): no sheet opens; a notice says "The file couldn't be shared."; the result is still offered.
- The share sheet reports an error: the copy is deleted, the notice says the file couldn't be shared, the result stays.
- A recording is offered and the user taps Record: refused with "Save, share or discard the last recording first.".
- A still is offered and the user saves a new frame: the new frame replaces the offered one.
- Two shares in a row: each makes its own copy in its own folder; each is deleted when its sheet closes.
- The output is blacked out or paused while a result is offered: Save… and Share… stay available (the result was made before; sharing it shows nothing new on screen).
- iPad: the sheet is a popover anchored to the Share… button.
- VoiceOver: the panel is one container with labeled buttons (FR-070).

## Requirements *(mandatory)*

### Functional Requirements

- **REC-012-R1**: After a successful Save Frame capture or a finished recording, the visualizer MUST offer the result in a ready panel with Save…, Share… and Discard; neither the Files sheet nor the share sheet opens by itself.
- **REC-012-R2**: Share… MUST open the system share sheet with exactly one file: a temporary copy of the result.
- **REC-012-R3**: The temporary copy MUST be in an app-owned temporary folder (`<tmp>/Sharing/<random>/`), named "Visualizer Frame <yyyy-MM-dd> at <HH.mm.ss>.<png|heic>" or "Visualizer Recording <yyyy-MM-dd> at <HH.mm.ss>.mp4", holding the same bytes as the original.
- **REC-012-R4**: When the share sheet reports completion, cancellation or an error, the app MUST delete that share's temporary copy and its folder.
- **REC-012-R5**: A cancelled, completed or failed share MUST leave the original offered and unchanged (the acceptance: "Share cancellation retains original and cleans temporary copy").
- **REC-012-R6**: At launch, the app MUST delete everything in `<tmp>/Sharing` (a directory listing only; no file dates are read).
- **REC-012-R7**: The share sheet MUST exclude Save to Photos and Assign to Contact; the app MUST NOT request any Photos or Contacts permission.
- **REC-012-R8**: The result stays offered until Save… completes, the user taps Discard, or (stills only) a new Save Frame replaces it. A cancelled Save… keeps it.
- **REC-012-R9**: Discard of a recording MUST delete its temporary file; a completed Save… moves it (REC-003); nothing is kept beyond the session (FR-065).
- **REC-012-R10**: While a recording is offered, Record MUST refuse with "Save, share or discard the last recording first." and start nothing.
- **REC-012-R15**: After a completed share the notice reads "Shared."; a cancel adds no notice; an error reads "The file couldn't be shared.". The ready panel stays in all three cases.
- **REC-012-R16**: An offered result MUST stay offered when the visual changes, the user pauses, the output is blacked out or the app goes to the background; a still and a recording can be offered at the same time, each in its own panel.
- **REC-012-R11**: If the copy cannot be made, no sheet opens, the notice reads "The file couldn't be shared." and the result stays offered.
- **REC-012-R12**: The app itself MUST NOT use the network; a share leaves the device only through the activity the user picks.
- **REC-012-R13**: The ready panel and its buttons MUST have accessibility labels (FR-070); on iPad the share sheet is anchored to the Share… button.
- **REC-012-R14**: DEBUG only: with `-uitestShareSimulation`, Share… makes the copy and shows "Simulate share completed" / "Simulate share cancelled" instead of the system sheet, and a probe reports the number of copies, what is offered and the last outcome. Release builds contain none of it.

### Key Entities

- **Offered result**: the still (format, encoded bytes) or the recording (temporary file) the user just made; one of each kind at most.
- **Share copy**: one temporary file per Share… tap, with its folder; lives only while its sheet is open.

## Success Criteria *(mandatory)*

- **REC-012-S1**: After a cancelled share, the original is still offered with the same bytes and the sharing folder is empty (unit and UI tests).
- **REC-012-S2**: After a completed share, the sharing folder is empty and the original is still offered (unit and UI tests).
- **REC-012-S3**: Leftover copies from an earlier run are deleted at launch (unit test).
- **REC-012-S4**: The excluded activities are exactly Save to Photos and Assign to Contact, and the app's Info.plist declares no Photos or Contacts usage string (unit test, privacy manifest check).
- **REC-012-S5**: On D1, AirDrop, Messages and Save to Files from the share sheet each deliver a playable file with the descriptive name, and the result is still offered afterwards (owner, device).

## Assumptions

- Recordings are the REC-003 files; this row changes only what happens after a recording or capture finishes.
- Temporary-folder copies of a video use the file system's copy (a clone on APFS, so no doubling of space in practice).
- What a receiving app or service does with a shared file is outside the app; the privacy policy says so.
- The Photos export (REC-011) and a recording library (REC-010) are separate rows.
