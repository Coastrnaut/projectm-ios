# Feature Specification: MED-006 Image Slideshow

**Feature Branch**: `feature/med-006` (spec directory `127-med-006-image-slideshow`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (MED-006-T01-T21 verified on the Mac host, the Linux shape and the iOS 27.2 simulator; device task T22 `{device}` open; report `docs/test-reports/image-slideshow.md`)

**Input**: User description: "Implement MED-006 (Image slideshow) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Cycle selected local images by
time or beat events." Acceptance, verbatim: "Five-image fixture follows saved ordering and timing
mode." Verification: simulator fixture media + device picker. Depends on MED-001 (integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `MED-006-R1…`, success criteria `MED-006-S1…`, tasks `MED-006-T01…`. Other
features are cited by their own IDs: MED-001 (photo layer, `PhotoStore`, pickers), FILE-008
(content-addressed photo folder and its references), CMP-013 (render caching of the still photo
layer), CMP-014 (scene transition bus), ACC-001 (motion policy), ANL-005 (beat tracker), ANL-006
(tempo confidence), SHOW-011 (tap tempo), ANL-007 (kick events), FX-019 (composite flash guard),
ACC-012 (sensory safety profile), FILE-005 (library backup), FILE-011 (local data erase), SCN-001,
SCN-002, SCN-010 (scenes, autosave, undo), SHOW-001 (show cues), ACC-005 (accessible parameters).

## Baseline: what exists today (audit of 2026-11-14, commit `4ca79b86`)

The row's gap status is "Gap candidate". The audit confirms the gap: the Photo visual shows one
picture and nothing cycles.

| Area | Behaviour today | Gap for this row |
|---|---|---|
| Stored photo (MED-001) | `PhotoStore` keeps one current photo: identifier in `settings.photo.id`, the sanitized copy in Application Support/Photos. Import reads the picked file once, strips metadata and writes it atomically. | Only one picture can be chosen. |
| Photo folder (FILE-008, ADR-0043) | Content-addressed: payloads `<sha256>.png|jpg` plus `references.json` mapping identifiers to payloads; equal pictures share one payload. Making a new photo current releases every reference sharing the previous photo's payload; Remove releases every reference sharing the current one; at most 32 references per payload. | Other references (slides) would be released by those two operations if they shared the photo's payload. |
| Photo layer (MED-001, CMP-006, CMP-013) | `ImageLayerSource`: setting `content` drops the current image at once (transparent frames while the new file loads on a background queue). The layer declares itself still (content = the load generation, parameters = the fit generation), so the compositor reuses its picture until one of them changes. | A slide change would show transparent frames while the next picture decodes; nothing loads a picture ahead. |
| Pickers (MED-001, FILE-013) | `PhotosPicker` (out of process, no photo library permission) and `fileImporter`, one image each. | No multiple selection. |
| Tempo (ANL-005, ANL-006, SHOW-011) | `TempoCoordinator.snapshot` gives BPM, period and a beat anchor (the last tap, or the analysis's latest beat); `readout` says manual, stable, uncertain or searching. The analysis follows the Photo visual's own pipeline while Photo is shown. | No consumer turns beats into slide changes. |
| Kick events (ANL-007) | A kick energy detector exists in the analysis packages; the Photo visual's layers receive no events (its audio context has an empty event list). | Not wired to the Photo visual. |
| Transitions (CMP-014, ADR-0042) | A transition bus blends two compositors' composites for scene changes. | No transition inside one layer. |
| Flash safety (FX-019, ACC-012) | The Photo visual's compositor runs the composite flash guard on every shown frame with the profile's envelope (`SafetyClamp`). | A slide change is a full-frame change that the guard already sees; nothing limits how often slides change. |
| Backup (FILE-005) | `settings.photo.id` is included; every resolving reference in the Photos folder is backed up (at most 64 photos). | No slideshow key. |
| Erase (FILE-011) | "Photos and videos" removes the Photos and Videos folders and the photo and video keys. | No slideshow key. |
| Scenes (SCN-001, MED-003/004 pattern) | Photo scenes carry a `photo` asset with the store identifier; unknown asset fields are kept verbatim. | No slideshow field. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the conservative, local-first option.

- Q: How many pictures can a slideshow hold? → A: Up to 20. Each slide is its own FILE-008
  reference in the Photos folder (an equal picture shares one payload), so 20 slides plus the
  current photo stay well inside FILE-005's 64-photo backup limit and FILE-008's 32 references per
  payload (MED-006-R1).
- Q: What timing modes exist? → A: Two: **Time** (a fixed number of seconds per slide, 2 to 60,
  default 5) and **Beats** (every 1, 2, 4, 8 or 16 beats of the tempo grid, default 4). Kick events
  (ANL-007) are not offered: kicks are irregular, would need a new event path into the Photo
  visual, and would change pictures in bursts; the beat grid is steadier and already exists
  (MED-006-R4, R5).
- Q: What happens in Beats mode when the tempo is uncertain or searching? → A: The slideshow falls
  back to the Time interval until the tempo is stable or manual again, so it never freezes during
  a quiet intro and never follows a doubtful grid. A tapped (manual) tempo counts as reliable
  (MED-006-R6).
- Q: How fast may slides change? → A: Never faster than the safety floor: 1 s between changes with
  the Standard profile, 2 s with Reduced (or Reduce flashing on), 3 s with Strict (in general
  (4 − flashes per second) seconds from ACC-012's effective limits). A change the floor blocks waits
  for the next beat (Beats) or happens when the floor allows (Time). Every shown frame still passes
  the composite flash guard (MED-006-R7).
- Q: Cut or crossfade? → A: A cut. A crossfade would make the still photo layer redraw every frame
  of the fade (losing CMP-013's caching), the CMP-014 bus blends whole compositors (twice the GPU
  work for one layer), and a cut is one transition the flash guard already limits. With Reduce
  Motion there is therefore nothing to reduce: every change is a cut either way (MED-006-R8).

### Session 2026-11-14 (speckit-clarify)

Five questions, each answered by Claude with the recommended option (owner rules 4 and 9).

- Q: Which slide shows first, and what happens to the shown slide when the list is edited? → A: The
  first slide of the saved order whenever the Photo visual is created or Slideshow is turned on (the
  position is not saved). Reordering keeps the shown picture on screen (the position follows it);
  removing the shown picture shows the one that took its place at once; adding pictures changes
  nothing on screen (MED-006-R3).
- Q: What happens to the running timer when the mode, seconds or beats change? → A: The shown slide
  stays; its slide time and beat count restart from the change, so a settings edit never causes an
  immediate change (MED-006-R4, R5).
- Q: Which slideshow edits are scene edits (autosave and undo)? → A: On/off, order, mode, seconds
  and beats are part of the scene and each change is one undo step (the seconds slider coalesces like
  other sliders); adding and removing pictures change stored files, so they are not undone (like the
  MED-001 photo), and an undo can only reorder pictures that are still stored (MED-006-R12).
- Q: What does a slide whose copy cannot be loaded do? → A: Identifiers that no longer resolve are
  dropped from the list when it is read; a copy that resolves but fails to decode shows the
  transparent fallback until the next scheduled change (no notice per slide; the safety floor still
  applies), so one damaged picture never stops the slideshow (MED-006-R3).
- Q: How do UI tests seed a slideshow without the system pickers? → A: DEBUG only, `-uitestSeedPhoto
  slideshow5` imports five solid-colour 64 × 48 pictures (red, green, blue, yellow, magenta) through
  the real slide import, turns Slideshow on in Time mode at 2 s, and the probe `slideshowProbe` reads
  "<shown index> changes=<n>" (MED-006-R15).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Cycle several pictures on a timer (Priority: P1)

A host shows holiday pictures behind the spectrum at a party. In Settings → Photo they choose five
pictures at once from Photos, turn on Slideshow and leave Time at 5 seconds. The Photo visual now
shows the pictures in the order they were chosen, one every five seconds, and starts over after the
last.

**Why this priority**: It is the row's observable behaviour and half of its acceptance criterion.

**Independent Test**: With five solid-colour fixture pictures and an injected clock, play 25 s in
Time mode at 5 s: the shown slide index goes 0, 1, 2, 3, 4 and back to 0 at exactly 5 s steps.

**Acceptance Scenarios**:

1. **Given** five stored slides and Time 5 s, **When** 5 s elapse, **Then** the next slide in the
   saved order shows.
2. **Given** the last slide, **When** its time ends, **Then** the first slide shows again.
3. **Given** a slideshow, **When** the app is relaunched, **Then** the same order and mode apply.
4. **Given** the visualizer is paused or in the background, **When** time passes, **Then** the
   slideshow holds and continues where it was when shown again.

---

### User Story 2 - Change pictures on the beat (Priority: P1)

A VJ wants the pictures to change with the music. They choose Beats and "Every 4 beats". With a
stable or tapped tempo the picture changes on every fourth beat; while the tempo is searching the
slideshow keeps going on the Time interval.

**Why this priority**: The other half of the observable behaviour ("or beat events").

**Independent Test**: With five fixture slides, inject a steady beat grid and step the clock across
beats: the slide changes on beats 4, 8, 12… in the saved order. Mark the tempo uncertain: changes
follow the Time interval instead.

**Acceptance Scenarios**:

1. **Given** Beats every 4 and a stable tempo, **When** four beats pass, **Then** the next slide
   shows on the fourth beat.
2. **Given** an uncertain or searching tempo, **When** time passes, **Then** slides follow the Time
   interval.
3. **Given** a very fast tempo and Every 1 beat, **When** beats come faster than the safety floor,
   **Then** slides change no more often than the floor allows, always on a beat.

---

### User Story 3 - Arrange the slideshow (Priority: P2)

The host reorders the pictures, removes one and adds two more from Files. Later they clear the
slideshow, and the pictures' copies leave the device.

**Why this priority**: Saved ordering is part of the acceptance; managing the list makes it usable.

**Independent Test**: Reorder, remove and clear through the coordinator: the saved order changes
accordingly and a removed slide's reference is released (its payload deleted when nothing else
shares it).

**Acceptance Scenarios**:

1. **Given** slides A B C D E, **When** E is moved to the front, **Then** the order E A B C D is
   saved and followed.
2. **Given** a slide, **When** it is removed, **Then** its copy is released and the rest keep their
   order.
3. **Given** 20 slides, **When** more are chosen, **Then** the extra pictures are refused with a
   notice and nothing else changes.

---

### User Story 4 - Keep the slideshow in scenes and backups (Priority: P2)

The VJ saves a scene with the slideshow in Beats mode, changes it, and recalls the scene: the saved
order and mode come back. A library backup restored on a new phone brings the slides back; "Photos
and videos" erase removes them.

**Why this priority**: Scenes and backups are how saved state travels in the app.

**Independent Test**: Round-trip a scene document and a FILE-005 backup in tests; erase removes the
key and the folder.

**Acceptance Scenarios**:

1. **Given** a scene captured with order C A B and Beats 2, **When** the order is changed and the
   scene restored, **Then** order C A B and Beats 2 apply.
2. **Given** a backup, **When** it is restored, **Then** the slideshow key and every slide picture
   are restored.
3. **Given** "Photos and videos" erase, **When** it completes, **Then** no slide or slideshow
   setting remains.

### Edge Cases

- One slide: it shows without changes (no cycling, no flash).
- No slides, or Slideshow off: the single stored photo shows exactly as in MED-001.
- A slide whose copy is missing or damaged: it is skipped (the slideshow continues with the
  others); the stored list drops identifiers that no longer resolve.
- A stored value that is malformed, has duplicate or non-canonical identifiers, more than 20
  entries, or out-of-range timing: read as the nearest valid value (duplicates and extras dropped,
  timing clamped); an unreadable value reads as no slideshow.
- Choosing a new photo or Remove Photo: slides are never released by it, even when they share the
  photo's picture.
- A scene naming slides that are no longer stored: those are ignored; current slides the scene does
  not name keep their place after the named ones (a restore never deletes or adds pictures).
- A pause longer than 1 s (background, pause, presentation loss): adds no slide time.
- Beats mode with no beat anchor (no phase): treated as an unreliable tempo (Time fallback).

## Requirements *(mandatory)*

### Functional Requirements

- **MED-006-R1**: The user MUST be able to keep an ordered slideshow of 1 to 20 local pictures,
  each a sanitized copy in the app's photo folder (MED-001 import rules, FILE-008 references), chosen
  several at once from Photos (no photo library permission) or Files.
- **MED-006-R2**: The user MUST be able to reorder, remove one, and clear all slides; removing or
  clearing MUST release the slides' references (a payload no other reference shares is deleted).
- **MED-006-R3**: With Slideshow on and at least one slide, the Photo visual MUST show the slides in
  the saved order, wrapping after the last, starting from the first slide whenever the visual is
  created or Slideshow is turned on; reordering keeps the shown picture, removing it shows its
  successor at once; a slide that fails to decode shows the transparent fallback until the next
  change; with Slideshow off or empty, MED-001's single photo shows.
- **MED-006-R4**: In Time mode a slide MUST stay for the chosen seconds (2…60, whole seconds) of
  shown time; slide time MUST accumulate only while the visual runs, ignoring steps over 1 s or ≤ 0;
  changing the mode, seconds or beats MUST restart the shown slide's time and beat count without a
  change.
- **MED-006-R5**: In Beats mode a slide MUST change on the beat at which N beats (1, 2, 4, 8 or 16)
  have passed since the last change, counting beats of the tempo grid only while the visual runs.
- **MED-006-R6**: Beats mode MUST use the tempo only when it is stable or manual and has a phase;
  otherwise it MUST follow the Time interval, and beat counting restarts when the tempo is reliable
  again.
- **MED-006-R7**: Two slide changes MUST never be closer than the safety floor of
  (4 − f) seconds, where f (1…3) is the effective flashes per second of the sensory safety
  profile raised by Reduce flashing; every frame MUST still pass the composite flash guard.
- **MED-006-R8**: A slide change MUST be a cut: the frame after a change shows the new picture in
  full, never a transparent frame or a blend; this holds with Reduce Motion on or off.
- **MED-006-R9**: The next slide MUST be decoded ahead of its change, off the main thread, so the
  change shows on the frame it is due; the still layer's cached picture MUST be invalidated exactly
  once per slide change.
- **MED-006-R10**: Slideshow on/off, order, mode, seconds and beats MUST be saved in the app's
  settings and restored after relaunch; the setting MUST be included in FILE-005 backups (the slide
  pictures are already backed up as photos), removed by FILE-011's "Photos and videos" erase, and
  listed in the UI tests' reset and the device privacy check's allowed keys.
- **MED-006-R11**: Choosing a new photo, Remove Photo and FILE-008's reference trimming MUST NOT
  release a slide's reference.
- **MED-006-R12**: Photo scenes (autosave, undo history) and show cues MUST record the slideshow as
  an optional field of the photo asset, without a format version change; restoring MUST apply its
  on/off, mode and timing and reorder the stored slides by it (named ones first, in the scene's
  order; others after, unchanged); an absent field MUST turn the slideshow off; a malformed field
  MUST read as absent; older apps MUST carry it verbatim. On/off, order, mode, seconds and beats
  changes MUST each be one undo step; adding or removing pictures MUST NOT be undoable.
- **MED-006-R13**: Settings → Photo MUST offer a Slideshow area: an on/off switch, the slide list
  with thumbnails (reorder, swipe to delete, VoiceOver actions Move up / Move down / Delete), Add
  from Photos (multiple), Add from Files (multiple), Clear Slideshow, a mode picker, a seconds
  slider with ACC-005 accessible-parameter behaviour, a beats picker and help text; changes MUST be
  announced through the shared announcer; no animation outside the motion policy; usable at
  accessibility text sizes.
- **MED-006-R14**: The slideshow schedule MUST be testable without a graphics device on every
  platform the packages' tests run on (injected clock and beat grid).
- **MED-006-R15**: DEBUG diagnostics MUST expose the shown slide index and the count of changes, and
  a DEBUG launch argument (`-uitestSeedPhoto slideshow5`) MUST seed five solid-colour slides through
  the real import path with Slideshow on in Time mode at 2 s, so UI tests can check order without the
  system pickers.

### Key Entities

- **Slideshow settings**: on/off, ordered slide identifiers (≤ 20), mode (Time or Beats), seconds,
  beats.
- **Slide**: one FILE-008 reference in the Photos folder.
- **Slideshow schedule**: the current index, accumulated slide time, beats counted since the last
  change and time since the last change (for the safety floor).
- **Beat grid**: period and anchor of the tempo, and whether it is reliable.

## Privacy review *(Constitution, Privacy; extends MED-001's review)*

| Question | Answer |
|---|---|
| What is stored? | Sanitized copies (pixels only, no metadata) of the chosen pictures in the app's own folder, and one settings value with their identifiers and the timing. |
| Is a photo library permission needed? | No: the system picker runs out of process and hands over copies. |
| Is anything sent or analysed? | No. The beat grid comes from the existing on-device tempo analysis. |
| Where can the pictures go? | Into the user's own library backup file (FILE-005) and the device backup, like the MED-001 photo. |
| App Store privacy label | Unchanged: Data Not Collected. |

Result: the review passes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MED-006-S1** (the acceptance, Time): with five fixture slides saved in order 2, 0, 4, 1, 3 and
  Time 5 s on an injected clock, the shown slide follows that order at exactly 5 s steps over two
  full cycles, and the shown pixels are each slide's colour.
- **MED-006-S2** (the acceptance, Beats): with the same five slides in Beats every 2 and an injected
  steady grid, the slide changes exactly on beats 2, 4, 6… in the saved order.
- **MED-006-S3** (the acceptance, saved): the order and mode survive a save and reload of the
  settings and a scene round trip (capture, change, restore).
- **MED-006-S4**: With an uncertain or searching tempo, Beats mode changes slides at the Time
  interval; 0 changes are taken from the unreliable grid.
- **MED-006-S5**: Over any 10 s of injected beats at 240 BPM with Every 1 beat, changes are never
  closer than the floor (1 s Standard, 2 s Reduced, 3 s Strict).
- **MED-006-S6**: A prepared slide change renders the photo layer exactly once and shows no
  transparent frame; frames after it reuse the cached picture.
- **MED-006-S7**: Removing a slide releases its reference; a new photo or Remove Photo releases no
  slide; backup includes and erase removes the slideshow.
- **MED-006-S8**: In a DEBUG UI test on the simulator with five seeded slides, the slide index probe
  advances in the saved order within 30 seconds of test time.
- **MED-006-S9** (device stage): on D1, five pictures chosen at once in the real Photos picker
  cycle in order in Time and Beats modes.

## Assumptions

- One slideshow per app (like the one stored photo); scenes record its arrangement, not separate
  picture sets. Scene archives (FILE-001) carry only the single photo; slides named by an imported
  scene that are not on the device are ignored.
- Shuffle is not offered (the order is the user's; a later row can add a seeded shuffle).
- Ken Burns (MED-007) and animated images (MED-008) are separate rows.
- Device picker behaviour with multiple selection (MED-006-S9) is verified only in the final
  device stage.
