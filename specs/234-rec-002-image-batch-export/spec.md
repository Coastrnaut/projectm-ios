# Feature Specification: REC-002 Image Batch Export

**Feature Branch**: `feature/rec-002` (spec directory `234-rec-002-image-batch-export`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (REC-002-T01-T11 verified on the Mac, simulator "REC2 iPhone 17", iOS 27.2; no
device claim). SnapshotBatchExportAcceptanceTests 4 and SnapshotBatchNamingTests 2 (2.6 s), SnapshotBatchExportUITests 1
(22-29 s).

**Input**: Roadmap row REC-002 (P2, depends on REC-001 and SCN-001, both integrated). Observable behavior, verbatim:
"Render selected scene snapshots to separate local files." Acceptance, verbatim: "Batch of five scenes produces five
correctly named files."

Identifiers carry the roadmap ID: requirements `REC-002-R1…`, success criteria `REC-002-S1…`, tasks `REC-002-T01…`,
research decisions `REC-002-D1…`. Other features are cited by their own IDs: REC-001 (Save Frame), REC-011 (Save to
Photos), REC-012 (Save… / Share…), REC-014 (export aspect presets), SCN-001 (scene document), SCN-002 (autosave),
SCN-008 (snapshots), SCN-009 (A/B compare), SCN-010 (undo history), SCN-015 (scene lock), QA-002 (golden scene
renders), VIS-001…VIS-009 (native visuals), FX-001 (glow), ACC-004 (announcer lanes), ACC-012 (sensory safety).

## Baseline (audit of 2026-11-14, commit `41703bde`)

| Existing piece | What it does today | Use in REC-002 |
|---|---|---|
| SCN-008 `SceneSnapshotCoordinator` | The current scene's named snapshots of the seven app-held glow and spectrum parameters; `read` gives the live value, `SceneSnapshotRecallPlan` validates a snapshot | The batch lists the usable snapshots; each image's values are the live values with the snapshot's usable values laid over them, computed without `write` |
| SCN-009 `SceneCompareCoordinator` | Applies a side's values to the live output, suspending autosave and history meanwhile | Its side rule (pre-Compare values overlaid with the snapshot's plan writes, D4) is reused; its suspend/restore is not needed, because the batch never writes the live scene at all |
| `NativeSpectrumHost` | The native visuals' generators (`makeGenerator`) and the FX-001 glow chain (`BloomEffect` in an `EffectChain`) drawing into the on-screen drawable | The same generators and glow chain draw each image into an offscreen texture |
| REC-001 `FrameImageEncoder`, `CapturedPixels` | Encodes a captured frame (8-bit sRGB BGRA top-down for the native spectra) to PNG; `inspect` reads it back | Encodes each image; tests read the files back |
| QA-002 `GoldenSceneRenderer` | Offscreen, fixed-time, seeded-audio render of an SCN-001 document's compositor layers (test package, not in the app) | Its determinism rules (fixed frame time, seeded synthetic audio, warm-up) are followed; the package itself is not linked into the app |
| REC-012 `ShareFileStore`, `ActivitySharePresenter` | Temporary copies in `<tmp>/Sharing`, the system share sheet without Save to Photos | The batch's Share… uses the same sheet rules for several files |
| REC-011 `PhotosSaveCoordinator` | Add-only Save to Photos of one still | The batch's Save to Photos adds the images one after the other through it |
| REC-014 `RecordingAspect` | Portrait 9:16, square, landscape 16:9 output shapes | The batch's size choice uses the same three shapes |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the conservative,
local-first option.

- Q: What is a "scene snapshot" here? → A: An SCN-008 snapshot of the current scene. Each image shows the current scene with that snapshot's usable values laid over the live values (the same state SCN-009 Compare or a recall would show). The user selects which snapshots to export; all usable ones are selected at first.
- Q: How is each image rendered? → A: Offscreen, never on the live output: the current native visual's generator and the glow chain draw one frame into an offscreen texture at the chosen size, at a fixed frame time (1 s), with seeded synthetic audio (a fixed band shape and a fixed waveform), Reduce flashing and the sensory safety profile as set. The same inputs give the same pixels.
- Q: Which visuals are supported? → A: The native visuals (Circular and Linear Spectrum, Oscilloscope, Lissajous, Radial Waveform, Beat Rings, Mandala, Particle Fountain, Particle Orbit). projectM, Camera, Photo, Video and Text are not rendered offscreen in this version: the export sheet says "Image export works with the native visuals. Choose one in Settings › Visual." and Export is disabled. Event-driven visuals (Beat Rings, the particle visuals) draw their resting picture, since the synthetic audio carries no beats.
- Q: Which sizes? → A: Landscape 1920 × 1080 (default), Portrait 1080 × 1920 and Square 1080 × 1080, chosen in the sheet each time (not stored).
- Q: How are files named? → A: `<NN>-<name>.png`: NN is the image's 1-based position in the batch, zero-padded to two digits; name is the snapshot name made safe: letters and digits of any script, spaces, hyphens, underscores and parentheses are kept; path separators, other punctuation, emoji, symbols and control characters each become a hyphen; runs of hyphens or spaces collapse to one; leading and trailing spaces, hyphens and dots are trimmed; at most 48 characters; an empty result becomes "Snapshot". A name already used in the batch (compared ignoring case) gets " (2)", " (3)"… before ".png".
- Q: Where do the files go? → A: Into a new temporary folder that only the batch uses; nothing is written to the library. When the batch finishes, the sheet offers Save… (the system folder picker; all files at once), Share… (the system share sheet with all files, without Save to Photos or Assign to Contact, as REC-012) and Save to Photos (add-only, REC-011). Done deletes the temporary folder; leftovers from a killed app are deleted at the next launch.
- Q: Progress and cancel? → A: The sheet shows "Rendering 2 of 5" with a progress bar and Cancel. Cancel stops after the image being rendered, deletes the temporary folder and leaves no files; "Export cancelled" is shown and announced.
- Q: Does exporting change the scene? → A: No. Exporting never writes the live parameter values, the scene file, its backup, the snapshot list or the undo history, and it works while the scene is locked (SCN-015) because it edits nothing. It is refused while Compare is active (the live values are a preview then): "Finish Compare first."
- Q: Announcements? → A: "Exported 5 images", "Export cancelled" and failures on the library lane (ACC-004).

### Session 2026-11-14 (speckit-clarify)

- Q: What happens to the live scene if it changes while a batch renders (a cue fires, MIDI moves the glow)? → A: Nothing reaches the batch: the visual, its options, Reduce flashing, the safety profile and every image's values are captured when Export is tapped, so the files show the scene as it was then.
- Q: What does a new export do while an earlier batch is still offered? → A: It replaces it: the earlier batch's temporary folder is deleted before the new one renders (one batch at a time).
- Q: If Save to Photos is refused or fails part-way, what is kept? → A: The images already added stay in Photos; saving stops at the first refusal or failure with REC-011's notice, says how many were added ("Saved 2 of 5 to Photos."), and the batch stays offered.
- Q: Does rendering block the interface? → A: No. Each image is rendered and encoded off the main thread; the sheet stays responsive and Cancel takes effect after the image in progress (at most one image of work).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Export a set of looks as images (Priority: P1)

A VJ has saved five snapshots of the glow and spectrum settings and wants a still of each for a set list or for social
posts. They open Export Images…, keep all five selected, tap Export and save the five PNGs to a folder.

**Why this priority**: This is the roadmap row: selected snapshots rendered to separate local files.

**Independent Test**: With five snapshots, exporting produces exactly five PNG files of the chosen size, named
`01-<name>.png` … `05-<name>.png`, and the scene is unchanged.

**Acceptance Scenarios**:

1. **Given** five usable snapshots and the Circular Spectrum, **When** the user exports all five at Landscape, **Then** five files `01-…png` to `05-…png` exist, each a PNG of 1920 × 1080.
2. **Given** snapshot names "Dawn/Dusk", "Dawn:Dusk", "🌅🌅", "Sunset 🌅" and "...", **When** they are exported, **Then** the files are `01-Dawn-Dusk.png`, `02-Dawn-Dusk.png`, `03-Snapshot.png`, `04-Sunset.png` and `05-Snapshot.png`.
3. **Given** an export finished, **Then** the scene file, its backup, the snapshot list, the undo history and the live values are exactly as before.

---

### User Story 2 - Cancel a running export (Priority: P1)

The user starts a long export and changes their mind.

**Independent Test**: Cancel during the second image leaves no files.

**Acceptance Scenarios**:

1. **Given** an export of five images rendering the second, **When** the user taps Cancel, **Then** rendering stops, the temporary folder is gone and "Export cancelled" is shown.

---

### User Story 3 - Choose snapshots and size (Priority: P2)

The user exports only two snapshots, square.

**Acceptance Scenarios**:

1. **Given** five snapshots, **When** the user deselects three and picks Square, **Then** two files `01-…png`, `02-…png` of 1080 × 1080 are produced, numbered in list order.

### Edge Cases

- No usable snapshot: "Export Images…" is disabled ("Save a snapshot first").
- An unusable snapshot (kept from a newer app or damaged) is listed as "Can't be used" and cannot be selected.
- A snapshot value for an unknown parameter is skipped as in a recall.
- projectM or a media visual shown: the sheet explains and Export is disabled.
- Compare active: Export is refused with "Finish Compare first."
- A render or write failure: the batch stops, its folder is deleted, "Export failed" is shown; nothing partial is offered.
- The app is backgrounded during an export: the export continues if iOS allows; a killed app's temporary folder is deleted at the next launch.
- Save… cancelled: the images stay offered until Done.
- A cue, MIDI or other live change during an export: the files still show the state captured at Export.
- Save to Photos refused or failing part-way: "Saved N of M to Photos." with REC-011's notice; the batch stays offered.

## Requirements *(mandatory)*

### Functional Requirements

- **REC-002-R1**: Settings › Visual MUST offer "Export Images…" under the snapshot rows, enabled when the scene has at least one usable snapshot, opening a sheet that lists the snapshots (usable ones selectable, all selected at first) and a size choice (Landscape 1920 × 1080, Portrait 1080 × 1920, Square 1080 × 1080).
- **REC-002-R2**: Each image's values MUST be the live values of the snapshot parameters with the snapshot's usable values laid over them (SCN-008's recall plan, SCN-009's side rule); other scene state (visual choice and its options) is the live one.
- **REC-002-R3**: Each image MUST be rendered offscreen by the current native visual's generator and the glow chain at the chosen size, at a fixed frame time with seeded synthetic audio, Reduce flashing and the sensory safety profile applied; identical inputs MUST give identical pixels.
- **REC-002-R4**: When projectM, Camera, Photo, Video or Text is shown, the sheet MUST say that image export works with the native visuals and Export MUST be disabled.
- **REC-002-R5**: Files MUST be named `<NN>-<safe name>.png` by the rule in Clarifications, unique within the batch ignoring case.
- **REC-002-R6**: Files MUST be written to a new temporary folder used only by that batch; Done deletes it and the app deletes leftover batch folders at launch.
- **REC-002-R7**: The sheet MUST show progress ("Rendering N of M") and Cancel; Cancel or a failure MUST delete the batch folder so no file remains, and nothing partial is offered.
- **REC-002-R8**: A finished batch MUST offer Save… (all files to a folder the user picks), Share… (the system sheet with all files, without Save to Photos and Assign to Contact) and Save to Photos (add-only, one image after the other, stopping at the first refusal with REC-011's notice).
- **REC-002-R9**: Exporting MUST NOT write the live values, the scene file, its backup, the snapshot list or the undo history; it MUST work while the scene is locked and MUST be refused while Compare is active.
- **REC-002-R10**: Outcomes MUST be announced on the library lane (ACC-004).
- **REC-002-R11**: No new stored setting, scene field, permission or network use.
- **REC-002-R12**: The batch MUST capture the visual, its options, Reduce flashing, the safety profile and every image's values when Export is tapped, and render off the main thread; a new export replaces an offered batch.

### Key Entities

- **Batch item**: position, snapshot name, file name, the parameter values to render.
- **Batch**: items, size, temporary folder, state (idle, rendering N of M, finished with files, cancelled, failed).

## Success Criteria *(mandatory)*

- **REC-002-S1**: A batch of five snapshots produces exactly five files with the expected names (tricky names included), each a valid PNG of the requested size.
- **REC-002-S2**: After an export the scene file and backup are byte-identical, and the snapshot list, undo history and live values are unchanged.
- **REC-002-S3**: Cancel during the batch leaves zero files.
- **REC-002-S4**: Two renders of the same snapshot give identical pixels.
- **REC-002-S5**: The UI test exports five snapshots and sees five named files in under 30 s on the simulator.

## Assumptions

- Snapshots hold only the seven app-held parameters SCN-008 captures; whole-scene export from the show's cue list is out of scope.
- Offscreen projectM rendering (a second engine and EGL context) and media visuals are out of scope for this version.
- Simulator results are never device evidence (Constitution X); no device task is required.
