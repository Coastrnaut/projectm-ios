# Feature Specification: MED-008 Animated Image Support

**Feature Branch**: `feature/med-008` (spec directory `257-med-008-animated-images`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement MED-008 (Animated image support) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Decode local animated images with frame timing limits." Acceptance, verbatim:
"Animated fixture loops and large file respects memory budget." Priority P2, depends on MED-001 (photo layer)."

Identifiers in this feature carry the roadmap ID: requirements `MED-008-R1…`, success criteria `MED-008-S1…`,
research decisions `MED-008-D1…`, tasks `MED-008-T01…`. Other features are cited by their own IDs: MED-001 (photo
layer), MED-006 (image slideshow), MED-007 (Ken Burns), MED-013 (media relinking), MED-014 (safe media decoder),
CMP-013 (render caching), PERF-005 (prewarm scheduler), FILE-008 (content-addressed media folder), SCN-001 /
SCN-014 (scene format, scene packs), ACC-001 (Reduce Motion), FR-072 / ACC-012 (Reduce flashing, sensory safety).

## Baseline: what exists today (audit of 2026-11-14, commit `5fb23871`)

| Question | Today |
|---|---|
| Import | `PhotoStore.stage` reads the picked file (bounded, security scoped) and `ImageSanitizer.sanitize` re-encodes the **first picture only** as a pixels-only PNG (alpha) or JPEG 0.9. An animated GIF or APNG becomes a still. |
| Decoder | `ImageIODecoder` (MED-001, hardened by MED-014): size limit, structure sniff (PNG, JPEG, HEIF), ImageIO type and status, pixel-count limit, upright thumbnail at most 4096 px, 8-bit sRGB RGBA. "Animation is MED-008" is noted in its header. |
| Layer | `ImageLayerSource` decodes one picture on a background queue into a mipmapped sRGB texture; `render` never loads. MED-006 `preload` fills a one-entry prepared slot; PERF-005 adopts a prewarmed texture. |
| Frame clock | MED-007's `KenBurnsPlayhead` counts injected frame durations (each ≤ 0.1 s) from the first drawn frame of the held picture. |
| Caching | CMP-013: the photo layer is still (content = load generation, parameters = a generation) except while a Ken Burns movement runs (time dependency). |
| Memory budgets | PERF-005's prewarm budget by device class (< 4 GiB: 48 MB, < 8 GiB: 96 MB, else 192 MB); REC-014's `RecordingOutputCap` by physical memory. No budget for decoded animation frames (none exist). |
| Storage paths | Photos, slides and scene assets are `.png`/`.jpg` payloads in the FILE-008 folder; scene archives, relinking (MED-013) and backups accept exactly these extensions; the archive content check sniffs the PNG structure (ancillary chunks skipped). |
| Reduce Motion / flashing | `settings.systemReduceMotion` reaches the photo layer (`reduceMotion`, MED-007); `PhotoVisualHost.reduceFlashing` drives the composite flash guard. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option, recommended option first.

- Q: Which files are animated, and how are they decoded? → A: ImageIO (`CGImageSource`) only: a file is animated when it holds more than one picture and its first picture carries a frame delay in the GIF, PNG (APNG), HEICS or WebP dictionary. Any other multi-picture file (a HEIC with several images, a multi-page TIFF) stays a still of its first picture, as today (MED-008-R1).
- Q: What is stored when an animation is imported? → A: A pixels-only re-encoding, like every photo: an animated PNG (`.png`) holding, per frame, the upright sRGB pixels and the frame's original (unclamped) delay, with loop count 0, and no other property (no comment, XMP, location or camera data). APNG keeps alpha and is lossless; storing `.png` keeps the photo folder, scene archives, scene packs, relinking and backups unchanged. Logos (always still PNG, MED-010) keep the first frame (MED-008-R2).
- Q: Which limits apply on import? → A: The MED-001/MED-014 limits (40 MB file, structure, 100 M pixels per picture), plus: at most 600 frames (later frames are dropped), a stored longest side of at most 2048 px, and at most 32 M stored pixels in all frames together (frames × width × height); frames are scaled down uniformly to fit. If the re-encoded copy is still over 40 MB it is re-encoded at half the pixels, at most twice, then refused as too large (MED-008-R3).
- Q: How are frame delays clamped? → A: Delays are first rounded to 0.1 ms (files and ImageIO keep them as 32-bit floats, so 0.2 s reads as 0.2000000030 s and would drift against the frame clock). Then the browser rule: a missing, non-finite or shorter-than-20 ms delay plays as 100 ms; a delay over 60 s plays as 60 s. With Reduce flashing on (the setting or a stricter sensory profile, as the frame context carries it to every layer), no frame lasts less than 334 ms, so the animation changes at most 3 times a second (at most 1.5 alternations a second, below the 3 Hz flash limit); the composite flash guard still applies on top (MED-008-R4).
- Q: Is the file's loop count honoured? → A: No: an animation always loops. A visual layer runs for minutes; an animation that stops after its loop count looks like a frozen still, and the video layer (MED-002/003) loops as well. The stored copy writes loop count 0 (MED-008-R5).
- Q: How is the shown frame chosen? → A: As a pure function of the elapsed frame time: elapsed starts at 0 on the first drawn frame of the held picture and adds each injected frame duration (MED-007's playhead); the frame is the one whose clamped interval contains elapsed modulo the total duration. The same elapsed time always gives the same frame, and the frame at t plus the total duration equals the frame at t (MED-008-R6).
- Q: What does Reduce Motion do? → A: The first frame is shown and held; the layer is cached as a still (MED-008-R7).
- Q: How is memory bounded? → A: Frames are decoded on demand on a background queue, never all at once at full size. Decoded frames live in a cache with a byte budget by device class (physical memory under 4 GiB: 32 MB; under 8 GiB: 64 MB; otherwise 128 MB). Every decode reserves four frame sizes (the ImageIO bitmap, the straight pixels, the texels and the new texture) for the one decode in flight. The decoded frame size is the stored size scaled down so that two resident frames (frame 0, kept for Reduce Motion, and the frame on screen) plus the reserve fit; when every frame plus the reserve fits, all frames stay resident (decoded once), otherwise the least recently used frame is evicted (never frame 0 nor the frame on screen). The cache's accounted bytes (resident plus reserve) never exceed the budget, and it records its peak. The budget is per animated picture; at most two exist at once (the shown photo and a slide decoded ahead) (MED-008-R8).
- Q: What is drawn when the next frame is not decoded yet? → A: The last drawn frame stays on screen (no transparent frame, no wait on the render thread); the missing frame and the one after it are requested. Frame textures have one level (no mipmaps), so a frame decode needs no GPU work (MED-008-R9).
- Q: How does render caching treat an animation? → A: While animating (more than one frame, Reduce Motion off) the photo layer declares a time dependency and renders every frame; with Reduce Motion it is still (MED-008-R10).
- Q: Do slideshows, Ken Burns, prewarm and scenes work with animations? → A: Yes, without new settings. A slide may be animated (preload decodes its first frame and prepares the animation); Ken Burns pans and zooms the animated picture; a prewarmed first frame (PERF-005) is shown at once and the animation attaches when its probe finishes; a scene's photo asset stays a `photo` with a `.png` payload, so scenes, archives, packs and relinking carry animations unchanged and the asset kind does not change (MED-008-R11).
- Q: Any new settings or UI? → A: None. No new UserDefaults key, no new Settings row. The Photo visual's VoiceOver value says "Animated photo W × H, N frames" for an animation (MED-008-R12).
- Q: How is acceptance proven? → A: On the Mac with injected frame times through the real compositor: a generated 4-frame GIF (ImageIO `CGImageDestination`, no binary assets) imported to APNG loops (the frame at t + total equals the frame at t) and follows the clamped delays; a generated 200-frame 2048 × 2048 APNG (hand-written chunks, tiny file) plays through every frame while the cache's peak accounted bytes stay under a 16 MB test budget and no frame is decoded at full size; Reduce Motion shows the first frame; plus plain-Swift timing and cache tests, a scene archive check, and one app test on the private simulator (MED-008-S1 to S6).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - An animated GIF plays behind the spectrum (Priority: P1)

A performer imports an animated GIF (or APNG, animated HEIC, animated WebP) as the photo; it plays on the Photo
visual and loops for as long as it is shown.

**Why this priority**: This is the roadmap row: decode local animated images with frame timing limits.

**Independent Test**: Import a generated animated GIF, render the photo layer through the compositor with injected
frame times, and read back the frames.

**Acceptance Scenarios**:

1. **Given** an animated GIF picked as the photo, **When** it is imported, **Then** the stored copy is an animated PNG with the same frames and delays and no metadata.
2. **Given** the animation shown, **When** frames are drawn at injected times, **Then** each frame shows the animation frame whose clamped interval contains the elapsed time, and the frame at t + the total duration equals the frame at t.
3. **Given** a frame delay of 10 ms in the file, **When** it plays, **Then** that frame lasts 100 ms.
4. **Given** a still picked as the photo, **When** it is shown, **Then** it behaves exactly as before.

### User Story 2 - A huge animation stays within memory (Priority: P1)

A performer imports a long, large animation. The app shows it without running out of memory.

**Independent Test**: A generated 200-frame 2048 × 2048 animation plays through every frame while the frame cache's
accounted bytes stay within a test budget.

**Acceptance Scenarios**:

1. **Given** an animation whose decoded frames would far exceed the budget, **When** it plays through, **Then** the frame cache never accounts more than its budget and every frame is shown.
2. **Given** the same, **When** a frame is decoded, **Then** it is decoded at a reduced size, never at full size for every frame.

### User Story 3 - Sensory safety (Priority: P1)

With Reduce Motion on, the animation holds its first frame; with Reduce flashing on, it never changes faster than
three times a second.

**Acceptance Scenarios**:

1. **Given** Reduce Motion on, **When** frames are drawn, **Then** every frame shows the first animation frame and the layer is cached as a still.
2. **Given** Reduce flashing on and 100 ms frames, **When** it plays, **Then** each frame lasts 334 ms.

### User Story 4 - Animations everywhere a photo goes (Priority: P2)

Slides, Ken Burns, scenes, scene archives and packs carry animations without new choices.

**Acceptance Scenarios**:

1. **Given** an animated slide, **When** it becomes the shown slide, **Then** it animates.
2. **Given** a scene with an animated photo exported to an archive, **When** the archive's content is checked, **Then** the animated PNG passes and keeps its frames.

### Edge Cases

- A single-picture GIF or APNG: a still.
- A multi-image HEIC without frame delays: a still of the first picture.
- Frames of different sizes (GIF sub-frames): ImageIO composes full canvas frames; the canvas size is the picture size.
- More than 600 frames: the first 600 are kept.
- A damaged frame in the middle: import refuses the file as damaged; at play time a frame that fails to decode keeps the last frame on screen.
- The copy over 40 MB after re-encoding: re-encoded smaller twice, then refused as too large.
- Reduce flashing turned on while playing: the next frame boundary follows the slower timing from the same elapsed time.
- The app paused or in the background: the elapsed time does not jump (frame durations ≤ 0.1 s).
- A content change while frames decode: stale decodes are dropped.

## Requirements *(mandatory)*

### Functional Requirements

- **MED-008-R1**: The app MUST recognise an animated image (more than one picture with a frame delay) in GIF, APNG, HEICS and WebP through public ImageIO only; other multi-picture files MUST remain stills.
- **MED-008-R2**: Importing an animation MUST store a pixels-only animated PNG (frames, delays, loop count 0) carrying no metadata; logos MUST stay still.
- **MED-008-R3**: Import MUST apply the existing limits plus a frame cap, a stored side cap and a total stored-pixel cap, scaling frames down to fit, and MUST refuse a copy that cannot be brought under the file size limit.
- **MED-008-R4**: Frame delays MUST be clamped (under 20 ms or missing → 100 ms; over 60 s → 60 s; Reduce flashing → at least 334 ms).
- **MED-008-R5**: An animation MUST loop indefinitely.
- **MED-008-R6**: The shown frame MUST be a pure function of the elapsed frame time from the injected frame clock.
- **MED-008-R7**: With Reduce Motion on, the layer MUST show the first frame without animating.
- **MED-008-R8**: Decoded frames MUST stay within a byte budget by device class, decoding on demand at a size that fits the budget, never all frames at full size.
- **MED-008-R9**: The render thread MUST NOT wait for a decode; a frame not yet decoded MUST leave the last drawn frame on screen.
- **MED-008-R10**: While animating, the photo layer MUST NOT reuse a cached picture; under Reduce Motion it MUST be cacheable.
- **MED-008-R11**: Slides, Ken Burns, prewarm, scenes, archives, packs and relinking MUST accept animated photos with no new asset kind.
- **MED-008-R12**: No new setting MUST be added; VoiceOver MUST name an animated photo and its frame count.
- **MED-008-R13**: The timing, frame selection and cache model MUST be plain Swift that builds and is tested on Linux.

### Key Entities

- **Animation timeline**: clamped frame delays, their total, frame index for an elapsed time.
- **Frame cache**: decoded frames by index with byte accounting, a budget, a pinned shown frame and a peak.
- **Animated picture**: the decoded-frame source of one stored animation (its ImageIO source, timeline and cache).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MED-008-S1**: A generated animated fixture loops: for every sampled t, the frame drawn at t + total duration equals the frame at t, and frame boundaries fall at the clamped delays.
- **MED-008-S2**: A generated 200-frame 2048 × 2048 animation plays every frame with the cache's peak accounted bytes ≤ the budget, and each decoded frame smaller than the source.
- **MED-008-S3**: Under Reduce Motion every frame equals the first animation frame and the layer renders once, then is reused.
- **MED-008-S4**: The imported copy is an animated PNG with the source's frame count and delays and no metadata.
- **MED-008-S5**: An animated photo passes the scene archive content check and keeps its frames; the scene asset kind is unchanged.
- **MED-008-S6**: Every new unit test runs in under 10 s (most under 2 s); the app test runs in under 30 s.

## Assumptions

- ImageIO on iOS 26+ reads GIF, APNG, HEICS and WebP animations and writes APNG (verified on the Mac's SDK by the tests; HEICS and WebP reading are not exercised by generated fixtures because the simulator's encoders may be missing).
- Real-device memory and smoothness on D1 are a `{device}` task.
