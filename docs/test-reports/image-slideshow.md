# MED-006 Image slideshow — test report (2026-11-14)

Spec: `specs/127-med-006-image-slideshow/`. Branch `feature/med-006`. Host: the Mac Studio (Xcode 27.2,
iOS 27.2 simulator "MED6 iPhone 17", created for this run and deleted afterwards). Simulator results
are never device evidence (Constitution X).

## Audit (baseline `4ca79b86`)

- MED-001 keeps one current photo (`settings.photo.id`); FILE-008 made the Photos folder
  content-addressed (references → payloads). Making a new photo current and Remove Photo released every
  reference sharing the photo's payload, which would have deleted a slide that shared it.
- The photo layer (`ImageLayerSource`) dropped its picture as soon as `content` changed (transparent
  frames while the next file decoded); nothing decoded ahead. It is a CMP-013 still layer.
- The tempo coordinator already gives a period, a beat anchor and a readout (manual, stable,
  uncertain, searching); the Photo visual's own pipeline feeds the analysis while Photo is shown.
- ANL-007 kick events do not reach the Photo visual (empty event list in its audio context).

## Design as built

- **Model** (`ImageLayer/Slideshow.swift`, plain Swift, Linux): `SlideshowSettings` (on/off, ≤ 20
  slides, mode Time or Beats, seconds 2…60 default 5, beats 1/2/4/8/16 default 4; sanitized on every
  path) and `SlideshowSchedule` (ticked per shown frame; steps over 1 s or ≤ 0 add nothing).
- **Modes**: Time changes when the slide's shown time reaches the seconds; Beats changes on the beat at
  which N grid beats have passed. **Beat and uncertainty rule**: the grid is used only for a manual or
  stable tempo with a phase; uncertain, searching or no phase falls back to the Time interval, and beat
  counting restarts when the grid is reliable again. Kicks are not offered.
- **Rate cap and safety**: no two changes closer than (4 − f) s, f = the effective flashes per second
  (`SafetyClamp`, Reduce flashing included): 1 s Standard, 2 s Reduced, 3 s Strict. A blocked beat change
  waits for the next beat. Slides are drawn by the same photo layer in the same compositor, so the
  composite flash guard and the profile's envelope see every frame. Changes are cuts (no crossfade),
  so Reduce Motion has nothing to reduce.
- **Prepared ahead**: `ImageLayerSource.preload` decodes the next slide on the layer's load queue; a
  `content` change to that URL adopts it synchronously: one render, no transparent frame, the CMP-013
  key changes exactly once.
- **Storage**: each slide is a FILE-008 reference in the Photos folder made by MED-001's sanitizer
  (`PhotoStore.stage`); the arrangement is `settings.photo.slideshow` (JSON). `PhotoStore` keeps slide
  references when a photo becomes current, when trimming and on Remove Photo. Removing or clearing
  releases the references.
- **Backup and erase**: the key is in FILE-005's included keys (the pictures are backed up as photos);
  FILE-011's "Photos and videos" erase removes the key and the folder; `AppSettings.allKeys` and
  `ALLOWED_KEYS` list it.
- **Scenes**: optional `slideshow` object on the photo asset (no version change); autosave, undo and
  show cues carry it; a restore reorders stored slides (named ones first) and never adds or deletes
  pictures; an absent field turns the slideshow off; scenes of other visuals leave it alone.
- **UI**: Settings → Photo → Slideshow section (switch, thumbnail rows with swipe delete, Edit Order,
  VoiceOver Move Up / Move Down / Delete, Add from Photos and Files with multiple selection, Clear,
  Change picker, ACC-005 seconds slider, beats picker, help text); announcements through the shared
  announcer (kind `library`).

## Results

| Check | Result |
|---|---|
| Acceptance, Time (package): five slides saved as 2, 0, 4, 1, 3, Time 5 s, 1 ms ticks | indices 1, 2, 3, 4, 0, 1, 2, 3, 4, 0 at exactly 5 s, 10 s … 50 s |
| Acceptance, Beats (package): Every 2 beats on a 120 BPM grid | changes exactly on beats 2, 4, … 20, in order |
| Acceptance, pixels (Metal): the five solid colours in the saved order through the compositor | every change: exactly one layer render, the next frame shows the new colour in full (no transparent or mixed frame), later frames reused; the cache key changes once per change |
| Acceptance, app: five fixture pictures imported through the real path, order and Time 3 s saved, relaunch | the relaunched coordinator shows the saved order every 3 s over two cycles; Beats every 2 after a relaunch changes once per second (2 beats at 120 BPM) |
| Acceptance, scene round trip | autosave document and show cue: order, Beats, 8 beats and on/off restored after changing them; a cue reorders named slides first and keeps the set |
| Uncertain tempo | nil grid → every 4 s (Time); readouts uncertain/searching/no phase give no grid; stable/manual do |
| Safety floor, 240 BPM Every 1 beat over 10 s | gaps ≥ 1 s / 2 s / 3 s for f = 3 / 2 / 1, each on a beat; Time 2 s under Strict changes every 3 s |
| FILE-008 | a removed slide's reference released and its unshared payload deleted; a new photo and Remove Photo (sharing slide payloads) release no slide; Clear leaves no payload |
| Limit | 25 picked → 20 kept, notice "A slideshow holds at most 20 pictures."; unresolved IDs dropped on read |
| Backup and erase | backup contents carry the key and both slide pictures; "Photos and videos" erase removes the key and the folder |
| UI test (simulator, `-uitestSeedPhoto slideshow5`) | `slideshowProbe` reached 3 changes with index = changes mod 5 at every reading; 13.3 s |

## Commands (durations on the Mac Studio)

- `swift test --package-path Packages/Compositor`: 432 tests, 6 skipped, 0 failures (10.4 s of tests, 17.6 s total); `SlideshowTests` 7 and `SlideshowLayerTests` 2.
- Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE --filter SlideshowTests`): 7 tests, 0 failures, 0.003 s.
- `swift test --package-path Packages/SceneFormat`: 117 tests, 0 failures (3.0 s); `Packages/LibraryBackup`: 44 tests, 0 failures (1.8 s).
- `projectM-iOSTests` on the simulator: 587 tests, 0 failures (36.0 s of tests, 63 s wall); `SlideshowTests` 6/6, each ≤ 0.11 s.
- UI: SlideshowUITests 1/1 (13.3 s); PhotoLayerUITests 1/1 (30.5 s, unchanged test).
- `check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog` (no Photos library key), `check_status_events`: OK; `test_scripts.py`: 153 tests OK (1 skipped); `check_privacy_manifest.py` on the Debug app: OK.
- Long-body flags (`-warn-long-function-bodies=300 -warn-long-expression-type-checking=150`): no warning in the new or changed MED-006 code (the few 160-177 ms warnings are in files this feature does not touch, or `VisualizerView.body` line 58, which predates it).
- PosterBoard reports: 25 before, 25 after.

## Not verified here

- `{device}` MED-006-T22 (S9): five pictures chosen at once in the real Photos picker and two from
  Files on D1, cycling in order in Time and Beats (tapped tempo) modes, order and mode after relaunch.
- The Settings section's controls were compiled and type-checked but not driven by a UI test (the
  pickers cannot be automated; the UI test uses the DEBUG seed).
