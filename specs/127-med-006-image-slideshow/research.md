# Research: MED-006 Image Slideshow

Decisions made by Claude under the owner's standing approval (owner rules 4 and 9), each the
conservative, local-first option.

## MED-006-D1 — Where the slides live

- **Decision**: Each slide is one FILE-008 reference in the existing Photos folder, created by
  `PhotoStore.stage` (MED-001's bounded read, `ImageSanitizer`, atomic write, `intern`). A new
  `SlideshowStore` keeps the ordered identifiers and timing in one UserDefaults value,
  `settings.photo.slideshow` (JSON). Removing a slide calls `folder.release([id])`.
- **Rationale**: no second folder, no second sanitizer, backup (FILE-005 backs up every resolving
  reference of the folder), erase (FILE-011 deletes the folder), launch reconcile and the 32-per-payload
  limit all apply unchanged. Equal pictures share one payload for free.
- **Protection**: `PhotoStore.makeCurrent`, `remove` and `trim` release references sharing the photo's
  payload. They now pass the slideshow's identifiers (read from the same defaults) in `keeping`, so a
  new photo or Remove Photo never deletes a slide (MED-006-R11).
- **Alternatives**: a `Slides` folder (duplicates FILE-005/008/011 work and a new backup path);
  storing the slideshow inside `settings.photo.id` (breaks MED-001 readers).

## MED-006-D2 — Schedule model (plain Swift, every platform)

- **Decision**: `SlideshowSchedule` in `ImageLayer` (plain Swift, Linux shape): the slide count,
  the shown index, accumulated slide time, time since the last change, beats counted since the last
  change, and the last tick time. `tick(now:beats:)` returns the new index when a change is due.
  Steps over 1 s or ≤ 0 add nothing (MED-002-R9's rule), so pause, background and presentation loss
  hold the slideshow.
- **Time mode**: change when slide time ≥ seconds and since-change ≥ floor.
- **Beats mode, reliable grid**: beats in (last tick, now] are counted with the grid's
  `nextBeat(atOrAfter:)`; change on the first beat at which count ≥ N and since-change ≥ floor.
- **Rationale**: integer nanoseconds, injected clock and grid: exact, deterministic tests.

## MED-006-D3 — Uncertain or searching tempo

- **Decision**: The app passes a grid only when `TempoCoordinator.readout` is `.manual` or `.stable`
  and the snapshot has a period and an anchor; otherwise nil, and Beats mode follows the Time rule.
  On the switch back to a reliable grid the beat count restarts from 0 (slide time keeps counting
  while unreliable, so the fallback is seamless).
- **Rationale**: never follow a doubtful grid; never freeze in a quiet intro. Holding was rejected
  (a searching tempo in silence would stop the show indefinitely).

## MED-006-D4 — Safety floor

- **Decision**: floor = (4 − f) s, f = `SafetyClamp.limits.flashesPerSecond` (1…3; Reduce flashing
  already lowers it to at most 2): Standard 1 s, Reduced 2 s, Strict 3 s. Applied in both modes.
  The composite flash guard (FX-019, with the profile's envelope from `applyReduceFlashing`) still
  runs on every shown frame because slides are drawn by the same photo layer in the same compositor.
- **Rationale**: a cut is a full-frame transition; the floor keeps slide changes at most 1 per second
  (far below 3 flashes per second, which needs 6 transitions), and stricter profiles widen it.
- **Alternatives**: 1000 / f ms (333 ms at Standard: photographic cuts that fast are flash-like);
  a fixed 2 s (needlessly slow for Standard).

## MED-006-D5 — Cut, prepared ahead

- **Decision**: `ImageLayerSource.preload(_ url:)` decodes the next slide on the layer's existing
  load queue into a one-entry prepared slot. Setting `content = .file(url)` with a prepared texture
  for that URL adopts it synchronously (one generation bump, state `.ready`), so the frame after the
  change draws the new picture: one render, no transparent frame; CMP-013 then reuses it. Without a
  prepared texture the old behaviour applies (transparent while loading). The schedule's next index
  is preloaded right after each change and when the slideshow starts.
- **Crossfade rejected** (spec Clarifications): CMP-013 caching lost during the fade, CMP-014 bus
  needs a second compositor, more transitions for the flash guard. Reduce Motion: nothing to reduce.

## MED-006-D6 — Tick location

- **Decision**: `PhotoVisualHost.beforeFrame` (a closure called at the start of each display-link
  frame, before compositing) calls `AppCoordinator.slideshowTick()`, which reads
  `MonotonicClock.nowNanoseconds()` (the clock the tempo grid uses) and the tempo, ticks
  `SlideshowCoordinator`, and on a change sets the host's content and preloads the next slide. No
  allocation on frames without a change.
- **Rationale**: the slideshow runs exactly while the Photo visual runs (pause, background,
  presentation loss and Settings follow the host's rules), and the tick is on the main actor where
  the tempo coordinator lives.

## MED-006-D7 — Scene field

- **Decision**: optional object `slideshow` on a `photo` asset:
  `{"enabled": bool, "storeIDs": [canonical UUID…] (≤ 20), "mode": "time"|"beats", "seconds": 2…60,
  "beats": 1|2|4|8|16}`. Malformed (not an object, wrong types, bad mode) reads as absent; IDs that
  are not canonical are dropped; values out of range clamp (seconds) or read as the default (beats).
  The photo asset is written when a photo is stored or the slideshow has slides (storeID = the photo,
  else the first slide). Restore: on/off, mode, seconds and beats applied; stored slides reordered
  (named ones first in the scene's order, the rest after); absent field → Slideshow off.
- **Rationale**: SCN-001's carried-unknown-fields rule (as MED-003 `loop`, MED-004 `speedPercent`):
  no version change; a restore never deletes or adds files.

## MED-006-D8 — Backup and erase

- **Decision**: `settings.photo.slideshow` joins `LibrarySettingsPolicy.includedKeys` (the photos are
  already backed up as references) and `LibraryErasePolicy`'s media keys and the media category's
  owned keys; `AppSettings.allKeys` (UI-test reset) and `ALLOWED_KEYS` list it.
- **Rationale**: slides are the user's photos like MED-001's, which FILE-005 includes. 20 slides +
  photo stay under the 64-photo limit.

## MED-006-D9 — Settings UI

- **Decision**: new `SlideshowSection` view file mounted by `SettingsView.photoSection`'s owner as a
  second section under Photo when the Photo visual is chosen: Toggle "Slideshow"; rows with a 44 pt
  thumbnail (ImageIO thumbnail off the main actor) and "Picture n"; `.onDelete`; `.onMove` while an
  "Edit Order" button turns the section's edit mode on; VoiceOver actions Move Up / Move Down /
  Delete per row; PhotosPicker with `maxSelectionCount` = remaining capacity; Files importer with
  `allowsMultipleSelection`; Clear Slideshow; a menu Picker Time/Beats; a seconds Slider (2…60,
  step 1) with `.accessibleParameter` (unit seconds); a beats menu Picker; help footer.
  Announcements (added, removed, cleared, moved) go through the shared announcer (kind `library`).
- **Rationale**: matches the existing photo section; ACC-005 for the continuous value; no animation.

## MED-006-D10 — Kicks and shuffle out of scope

- Kicks (ANL-007): the Photo visual's audio context carries no events, and kick-triggered cuts come
  in bursts. Shuffle: not needed for the acceptance; a later row can add a seeded shuffle.
