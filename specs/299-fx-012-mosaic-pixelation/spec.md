# Feature Specification: FX-012 Mosaic Pixelation

**Feature Branch**: `feature/fx-012` (spec directory `299-fx-012-mosaic-pixelation`)

**Created**: 2026-11-15

**Status**: Implemented 2026-11-15 (FX-012-T01-T17 verified on the Mac and an own iOS 27.2 simulator; T18 `{device}` open)

**Input**: User description: "Implement FX-012 (Mosaic pixelation) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable
behavior, verbatim: "Reduce spatial resolution into square or hexagonal blocks." Acceptance, verbatim: "Block size one
equals original frame; larger sizes are visibly discrete." P2, effort M, depends on VIS-001 (integrated)."

Identifiers in this feature carry the roadmap ID: requirements `FX-012-R1…`, success criteria `FX-012-S1…`, tasks
`FX-012-T01…`, research decisions `FX-012-D1…`. Other features are cited by their own IDs: CMP-001 (the compositor),
FX-002 (tone map), FX-003 (colour grade), FX-006 (chromatic split; ADR-0104), FX-007 (directional blur; ADR-0106),
FX-008 (radial blur; ADR-0107), FX-009 (Trails), FX-010 (echo feedback, built in parallel), FX-019 (flash guard), FX-020
(effect chains; ADR-0054), ACC-005 (accessible sliders), PERF-004 (texture pool), PERF-009 (pipeline archive), SHD-011
(shader policy; ADR-0024), FILE-005/FILE-011 (backup and erase policy), RenderGoldens (QA-002).

## Baseline: the audit (2026-11-15, commit `115d1f53`)

**No mosaic or pixelation effect exists.** Searching the packages, the app and the ADRs for mosaic or pixelate finds
nothing.

**Spatial output effects today.** The compositor-backed visuals (Camera, Photo, Video, Text) share CMP-001's output
chain: layers → composite (linear premultiplied, half float) → FX-020's reorderable effects in `OutputEffectOrder`
(Trails, Color, Chromatic split, Directional blur, Radial blur) → FX-019 flash guard → output pass (grade, FX-002 tone
map). FX-006, FX-007 and FX-008 set the pattern this feature follows: an own pass writing one pooled picture while
active, walked in `Compositor.encodeOutputEffects`, its shader a module constant spliced into the reviewed compile site
in `Compositor.init` and listed in `CompositorShaderSources.archived`; a non-neutral Color listed before an active
spatial effect is folded into FX-020's grade pass right before it; scenes store the entry only while it is on.

## Clarifications

### Session 2026-11-15 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human interaction); each
answer is the conservative option.

- Q: In what unit is the block size? → A: Whole pixels of the picture being processed, 1…64 (default 8). Block size 1
  is the original frame, bit for bit: it runs no pass at all. Applied to FX-012-R2, R4.
- Q: Which colour does a block show? → A: The colour of the one pixel at the block's centre, read exactly (no
  filtering, no averaging). Every output value is then an input value, the cost is one read per pixel whatever the
  size, and the result can be checked exactly. Applied to FX-012-R3, R6.
- Q: Where is the grid anchored? → A: At the frame's top-left corner: square blocks start at pixel (0, 0); the first
  hexagon is centred on the top-left corner. Partial blocks at the right and bottom edges take the centre pixel clamped
  to the frame. Applied to FX-012-R3, R5.
- Q: Which hexagon orientation? → A: Pointy-top hexagons in horizontal rows (every other row shifted by half a cell);
  the block size is the distance between neighbouring cell centres in a row, so rows are 0.866 × size apart. Applied
  to FX-012-R5.
- Q: Where does it apply? → A: The compositor-backed visuals (Camera, Photo, Video, Text), on every output, as a
  reorderable entry of the FX-020 effect chain ("Mosaic", stored kind `fx.mosaic`), appended after the radial blur. The
  native spectra and projectM are unchanged. Applied to FX-012-R1, R7.

### Session 2026-11-15 (speckit-clarify)

Five questions, each answered by Claude with the recommended option (owner rule 4).

- Q: Should the block size follow the display scale (points) instead of pixels? → A: No: pixels of the composite
  picture. Every output of a frame (screen, external display, recording, capture) reads the same composite, so they
  agree; the roadmap's "block size one" is a pixel. The 64-pixel cap gives about 18 blocks across a phone picture.
  Applied to FX-012-R2.
- Q: Do the sensory safety profile or Reduce flashing limit the mosaic? → A: No cap: it only copies existing colours,
  adding no brightness; the flash guard still judges the shown frame. Applied to the Assumptions.
- Q: Is Mosaic a global setting or a per-scene value? → A: Both, like FX-006 to FX-008: a global setting the visuals
  use, which a scene or effect-chain preset with an `fx.mosaic` entry overwrites when opened; a scene without one
  leaves it alone. Applied to FX-012-R9, R10.
- Q: How is the shape stored and shown? → A: A Square/Hexagon segmented choice; stored as the string `square` or
  `hexagon` in settings (anything else reads as square) and as `shape` 0 or 1 in the scene entry (≥ 0.5 reads as
  hexagon, like FX-006's `radial`). Applied to FX-012-R8, R10.
- Q: What does VoiceOver say for the block size? → A: "Block size", the whole number ("8"), one pixel per swipe; the
  on-screen readout is "8 px". Applied to FX-012-R8.

### Session 2026-11-15 (speckit-analyze)

- Finding A1 (coverage): R9's "removed by the UI-test reset" had no check; T12 names the reset and T14 runs
  `SettingsTests`. Finding A2 (consistency): R5's "pixel containing the centre" is ⌊centre⌋, as in contract C2; the
  hexagon tests compare only pixels whose four neighbours share the cell (ties at borders may round differently on
  the GPU), as in S3/S4. Finding A3: no settings key may contain "focus", "exposure" or "whitebalance" (CAM-005 and
  siblings); the `settings.mosaic.*` keys do not.

### Session 2026-11-15 (speckit-implement)

- Q: Where do the `fx.mosaic` read and write rules live? → A: In a new `SceneEffectChain+Mosaic.swift` (one case per
  switch in `SceneEffectChain.swift`), to keep edits to the shared file small while FX-010 adds its own kind; the
  scene module's source-safety list names the new file. Applied to FX-012-R10.

### Session 2026-11-18 (QA-011 device run)

- Q: FX-012-T18 read no change at all for 8 px squares on D2 and D3; is the mosaic off on iPads? → A: No, the test sampled
  every 8th pixel, which is exactly the centre pixel each 8 px block shows, so where the composite is the screen's pixel
  grid every sample was unchanged. Every 3rd pixel reads 0.010 on D2's and 0.011 on D1's screenshots of that run; the
  0.003 limit for 8 px is unchanged.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Pixelate the picture (Priority: P1)

A performer shows the Photo visual and turns on Settings → Mosaic: the picture becomes a grid of flat-coloured
squares. A Block size slider sets how coarse the grid is, and a Shape choice switches between squares and hexagons.

**Why this priority**: it is the roadmap row's subject.

**Independent Test**: show random content at block size 8 (squares): every 8 × 8 block is one colour and neighbouring
blocks differ; with hexagons every cell is one colour.

**Acceptance Scenarios**:

1. **Given** Mosaic on with squares at size 8, **When** random content is shown, **Then** every 8 × 8 block counted
   from the top-left corner shows one colour, the colour of its centre pixel, and adjacent blocks differ.
2. **Given** hexagons at size 12, **When** random content is shown, **Then** every pixel well inside a hexagonal cell
   shows that cell's colour.
3. **Given** the values set, **When** the app is relaunched, **Then** the same values are applied.

---

### User Story 2 - Block size one is the picture (Priority: P1)

A performer who leaves Mosaic off, or sets the block size to 1, sees exactly the picture the app showed before.

**Acceptance Scenarios**:

1. **Given** the effect off, or on at block size 1 in either shape, **When** any frame (random content) is shown,
   **Then** every output pixel is bit-identical to the output without this feature, and no extra picture memory is
   held.

---

### User Story 3 - Part of the effect chain and scenes (Priority: P2)

The performer reorders Mosaic on the Effect order screen, saves a scene and an effect-chain preset, and gets the same
mosaic back when the scene or preset is opened.

**Acceptance Scenarios**:

1. **Given** a scene saved with Mosaic on, **When** it is opened, **Then** its values and position are restored; a
   scene without a Mosaic entry leaves the current values as they are (FX-020's rule).
2. **Given** a scene from before this feature, **When** it is opened and saved, **Then** it renders and encodes
   exactly as before.

### Edge Cases

- Values missing, not numbers, NaN or out of range: off, the default, or the nearest limit; a fractional size is
  rounded to the nearest whole pixel.
- Block size larger than the frame: the whole frame shows one or a few colours, all from inside the frame.
- Partial blocks at the right and bottom edges, and hexagon cells whose centre lies outside the frame: they take the
  nearest pixel inside the frame.
- A frame smaller than 2 pixels in either direction: passes through.
- Non-finite picture values: copied like any other value (FX-002 handles them downstream).
- Transparent areas: colour and alpha are copied together, so premultiplied colour stays valid.
- A size change (rotation, external display) re-grids from the new top-left corner.
- Visuals that are not compositor-backed: unchanged; the help text names the visuals.

## Requirements *(mandatory)*

### Functional Requirements

- **FX-012-R1**: Mosaic (on/off, off by default) applies to the compositor-backed visuals (Camera, Photo, Video,
  Text) on every output of a frame: screen, external display, recording and still capture.
- **FX-012-R2**: Block size is a whole number of pixels, 1…64 (default 8, VoiceOver step 1). Shape is Square
  (default) or Hexagon.
- **FX-012-R3**: Square: pixel (x, y) belongs to block (⌊x ÷ N⌋, ⌊y ÷ N⌋) and shows the pixel at
  (min(bx × N + ⌊N ÷ 2⌋, width − 1), min(by × N + ⌊N ÷ 2⌋, height − 1)), N the block size.
- **FX-012-R4**: The mosaic is active only when on, the block size is at least 2 and the frame is at least 2 × 2;
  otherwise no pass runs and the output is bit-identical to the output before this feature.
- **FX-012-R5**: Hexagon: pointy-top cells, centre spacing N within a row and 0.866 × N between rows, one cell centred
  on the frame's top-left corner; the pixel centre (x + ½, y + ½) belongs to the nearest cell centre (hexagonal
  rounding); it shows the pixel containing that cell's centre, clamped to the frame.
- **FX-012-R6**: Each output pixel costs one exact read whatever the size or shape; every output value equals an input
  value.
- **FX-012-R7**: Mosaic is an FX-020 reorderable output effect (`fx.mosaic`), appended after Radial blur in the
  standard order; merged after FX-010 (2026-11-15), the standard order is Trails, Color, Chromatic split, Directional
  blur, Radial blur, Echo, Mosaic. Its position is honoured; the flash guard and the tone map always run after it.
- **FX-012-R8**: Settings has a "Mosaic" section: an on/off toggle, a Block size slider ("8 px") with ACC-005 spoken
  values, a Square/Hexagon choice, and help text. The Effect order screen lists it with its own on/off switch.
- **FX-012-R9**: The values are saved on the device, restored at launch, included in library backups, erased with the
  other settings, checked on read, and removed by the UI-test reset.
- **FX-012-R10**: Scenes and effect-chain presets store Mosaic as an `fx.mosaic` entry (`size`, `shape`) in FX-020's
  `effects` list, written only while it is on; out-of-range values are clamped and reported; scenes without it encode
  byte-identically.
- **FX-012-R11**: An active mosaic uses one pooled picture at output size and one full-screen pass per frame, no
  per-frame allocation; the picture returns to the pool when the mosaic turns inactive, the size changes or the visual
  is released.
- **FX-012-R12**: A plain-software reference of the block and cell assignment and of the output exists, testable
  without a GPU (Linux), and the GPU output matches it.
- **FX-012-R13**: The shader is a module constant added to the compositor's existing reviewed compile site and to the
  pipeline-archive key sources; no new compile site, no user-authored shader.

### Key Entities

- **Mosaic setting**: on/off, block size (whole pixels), shape (square or hexagon).
- **Cell**: a square block or hexagonal cell; its centre pixel gives its colour.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FX-012-S1**: Off, and on at block size 1 in both shapes, are bit-identical to the output without the feature on
  random content; all existing RenderGoldens pass unchanged.
- **FX-012-S2**: Squares at size 8 on random content: every 8 × 8 block (anchored at the top-left) is one uniform
  colour equal to its centre pixel, and every pair of adjacent blocks differs.
- **FX-012-S3**: Hexagons: every sampled pixel whose neighbours lie in the same cell (by the software reference) shows
  that cell's colour, and the cells' colours are uniform.
- **FX-012-S4**: The GPU output equals the software reference exactly for squares, and for hexagons at every pixel
  away from cell borders.
- **FX-012-S5**: A scene and a preset with Mosaic round-trip to the same values; a scene from before the feature
  encodes byte-identically.
- **FX-012-S6**: A user can find Mosaic, turn it on, change the block size and the shape (UI test under 30 s); the
  values survive a relaunch (setting test with a reloaded store).
- **FX-012-S7**: The device frame rate with Mosaic on is checked in the last stage (`{device}`).

## Assumptions

- The compositor, FX-002, FX-003, FX-006 to FX-009, FX-019 and FX-020 are as integrated; FX-010 is built in parallel
  and adds its own effect kind; the merge reconciles the order.
- The mosaic only copies existing colours, adding no brightness; it needs no ACC-012 cap and the flash guard judges the
  shown frame.
- Live audio-reactive modulation of the block size is not wired.
