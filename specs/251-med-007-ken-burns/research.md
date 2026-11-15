# Research: MED-007 Image Ken Burns

- **MED-007-D1 Where the crop is applied.** Decision: in the photo layer's own sampling: the crop rectangle is
  the content that CMP-006's `LayerFitPlacement` fits (content size = crop size in image pixels), then mapped back
  into image coordinates (`origin + c · size`). Rationale: one texture lookup, exact texel mapping (a 1:1 crop
  samples texel centres), the user's fit and anchor still apply, and CMP-005's transform, opacity and blend stay
  after it as before. Alternatives: animate the CMP-005 layer transform (rejected: scales the picture, so edges
  show transparent beyond the image, and it is the user's own control); a separate crop pass (rejected: an extra
  texture and pass per frame).
- **MED-007-D2 Shader bounds.** The fragment's transparent test changes from "outside 0…1" to "outside the crop
  rectangle" (`bounds` uniform = origin, origin + size; (0,0,1,1) without Ken Burns, so the drawing is unchanged).
  Fill never reaches the test; fit's bars stay transparent instead of showing image outside the crop.
- **MED-007-D3 Interpolation and exactness.** Edges interpolate linearly with the eased fraction; `u` comes from
  integer nanoseconds (`Double(elapsed) / Double(duration)`), and the endpoints are returned as the stored values
  without arithmetic (SHOW-008's rule "at a key time, the stored sample itself"). Linear interpolation of a convex
  set keeps every intermediate rectangle inside the image. Smoothstep is monotonic on 0…1 (derivative 6u(1−u) ≥ 0).
  Alternative: geometric (log) interpolation of size for constant perceived zoom speed (rejected for now: the
  position then drifts non-linearly; linear is predictable and exactly testable).
- **MED-007-D4 Clock.** `KenBurnsPlayhead`: on the first frame after a restart elapsed = 0; each later frame adds
  `round(frameDuration · 1e9)` ns (the frame clock already clamps a frame to 0.1 s), saturating at the duration.
  Rationale: the injected clock, no jump after a pause, no wall clock. Alternative: presentation time minus a start
  time (rejected: jumps after a pause or suspension).
- **MED-007-D5 Caching (CMP-013).** `renderDependencies`: moving → `time: true` (non-cacheable); holding → still
  with `parameters = parameterGeneration`, bumped on fit, movement and Reduce Motion changes. The playhead advances
  only in `render`, so a reused frame never skips time. The frame that first reaches the end renders (its key was
  nil), and the next one is the first reused.
- **MED-007-D6 Restart.** The layer restarts the playhead whenever the held picture's load generation changes
  (new photo, slide change, scene restore) or the movement changes; the transparent loading frames do not count.
- **MED-007-D7 Slideshow duration.** The app sets the layer's movement with the duration replaced by the dwell:
  Time → `seconds`, Beats → `beats × period` from the reliable grid (else `seconds`). Updated on every slide
  change and settings edit; equal values do not restart (the movement is `Equatable`).
- **MED-007-D8 Scene field.** Optional object `kenBurns` on the `photo` asset carried in `SceneAsset.extra`
  (MED-003/MED-004/MED-006 pattern), so older versions keep it verbatim and no version or decoder change is needed.
  Rectangles as named objects (`x`, `y`, `width`, `height`) for readability; `durationMilliseconds` integer 2000…60000;
  `easing` `linear` | `easeInOut`. Anything else reads as absent (SCN-012 then reports nothing: the field is optional).
- **MED-007-D9 Custom editor.** Zoom (100…400 %) and centre position (0…100 % of the free range) per end, mapped to
  an image-shaped rectangle: size = 1 / zoom, origin = position · (1 − size). Sliders are accessible by construction
  (ACC-005 helper); dragging rectangles on a preview is out of scope (not needed for the acceptance, harder to make
  accessible).
- **MED-007-D10 Storage.** `settings.photo.kenBurns`, absent = off, JSON of `KenBurnsMotion` (same keys as the
  scene field). A preference: backed up (FILE-005 included keys), erased with Settings, not with media.
