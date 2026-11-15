# Feature Specification: VIS-018 Geometric Tessellation

**Feature Branch**: `feature/vis-018` (spec directory `307-vis-018-geometric-tessellation`)

**Created**: 2026-11-15

**Status**: Draft

**Input**: User description: "Implement VIS-018 (Geometric tessellation) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Animate polygons and tilings with palette and symmetry controls." Acceptance, verbatim:
"Different tile counts remain aligned at all supported aspect ratios." P2, L, depends on ANL-002 (normalized bands,
integrated). Test: Metal, CoreGraphics; keep the projectM backend isolated; golden image + simulator + device GPU."

Identifiers in this feature carry the roadmap ID so they never collide with other features: requirements are
`VIS-018-R1…`, success criteria `VIS-018-S1…`, tasks `VIS-018-T01…`. Other features are cited by their own IDs:
FR-065 (what the app may store), FR-070 (accessibility); ACC-001 (Reduce Motion), ACC-003-R13 (colour-blind-safe
palette), ACC-012 (brightness below full white); VIS-001 (native visual contract and palettes); VIS-003-R12 (scene
capture); VIS-007 (band groups, mandala symmetry); VIS-013 to VIS-017 (the noise field generator and its modes);
ANL-002 (normalized bands); FX-019 (strobe safety envelope); SHD-011 (shader policy); QA-002 (golden images); FILE-005
(settings backup policy).

## Baseline: what exists today (audit of 2026-11-15, commit `72d33ec0`)

This is a gap row. The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Full-screen procedural visuals (VIS-013 noise field, VIS-014 kaleidoscope, VIS-015 tunnel, VIS-020 waterfall, VIS-011 fluid ink, VIS-012 reaction diffusion, VIS-017 SDF shapes) | One generator with one module-constant shader, one entry point per mode, a CPU mirror sampled for the FX-019 envelope, band-driven drive on the injected frame clock, shared palette, Reduce Motion, goldens. | No polygon tilings, no lattice, no tile count. |
| Mandala (VIS-007) | Rotational symmetry 3–12 and a mirror option for one repeated petal. | Symmetry of a single motif, not of a tiling's colouring. |
| Palettes (VIS-001, ACC-003-R13, UIX-011) | Built-in Spectrum, Ice, Mono; colour-blind-safe; user palettes. | No per-visual palette choice for a procedural visual. |
| `TessellationTests.swift` | VIS-001's bar vertex test (the word "tessellate" means triangulating bars). | Unrelated; no tiling. |

## Clarifications

### Session 2026-11-15

Answered by Claude under the owner's standing approval (owner rule 4); each answer is the conservative,
local-first option.

- Q: Where does the tiling live: a new generator, or one more mode of an existing one? → A: One more mode of the noise field generator (`NoiseFieldConfiguration.tessellation`, a settings value; nil = off, on forces every other mode off), drawn by its own entry point in that generator's module-constant shader, exactly as VIS-012, VIS-015 and VIS-017. No new shader compile site, no compliance or ADR change; the new text joins the PERF-009 archive key automatically. Rejected: a separate generator with its own `makeLibrary(source:)` (a reviewed compile-site change under SHD-011 / ADR-0066), and CPU geometry on the flat-shape pass (thousands of polygons per frame and a second, differently rounded path to keep aligned) (VIS-018-R1).
- Q: What exactly does "aligned" mean, for every tile count and aspect ratio? → A: Tile size s = (shorter side in pixels) / N for tile count N, so one lattice period along x is exactly s at every aspect ratio. Rules, all checked in tests: **A1 centred** — the frame centre is a 180° symmetry centre of the drawn tiling: the pixel mirrored through the frame centre lies in the tile whose centre is the mirror of the first tile's centre (≤ 0.01 px); the centre is a hexagon centre (hexagons, trihexagonal), a vertex (triangles), an octagon centre (truncated square), and for squares a tile centre when N is odd and a vertex when N is even. **A2 exact size** — the tiles' period along x is s, so the shorter side holds exactly N periods (squares: exactly N whole squares edge to edge across the shorter side, in either orientation). **A3 equal tiles** — every tile of one shape is a translate of one prototype; in pixels, among tiles wholly inside the frame, the bounding boxes of one shape differ by at most 1 px in width and height for squares and at most 2 px for shapes with slanted edges (a pixel-centre grid can miss a corner narrower than one pixel; decided 2026-11-15 after the first per-pixel run showed 2 px spreads on triangles and hexagons), and each tile's pixel count is within half its perimeter (px) of its exact area. **A4 no gaps or overlaps** — every pixel belongs to exactly one tile, and that tile's polygon contains the pixel centre (≤ 0.001 tile units), its edge distance agrees with the polygon (≤ 0.001 tile units). **A5 same pattern at every aspect ratio** — a point at the same offset from the centre in units of the shorter side lies in the same tile (same integer lattice coordinates and shape) at every aspect ratio. **A6 seams do not drift** — moving between aspect ratios, or animating, never moves a seam: the lattice depends only on the output size and N (no time, no audio term), and the GPU's tile at every pixel equals the CPU's (pixels within 0.01 px of a seam excluded) (VIS-018-R3, R4; S1, S2).
- Q: What does the symmetry control act on, given that a periodic tiling cannot be rotated to an arbitrary order and stay aligned? → A: On the colouring and brightness, not the lattice. Each tile's look is a function of its centre's polar position about the frame centre through a smooth order-k function (mirror on: 0.5 + 0.5·cos kθ; mirror off: 0.5 + 0.3·cos kθ + 0.2·sin 2kθ, which has no mirror axis) plus a radius term; tiles that are k-fold rotations (and, mirrored, reflections) of each other are therefore identical with no wedge seams. Orders 1 (none), 2, 3, 4, 6 (default 6); mirror default off (as VIS-007's mandala). The lattice stays fixed, so alignment never depends on symmetry. Rejected: folding the lattice into wedges (breaks A3/A4 at wedge seams) (VIS-018-R5).
- Q: How do palette and audio move it, and how is it kept calm and finite? → A: Palette choice Spectrum (default), Ice or Mono (VIS-001's built-in palettes, reused); the shared colour-blind-safe (ACC-003-R13) or a custom (UIX-011) palette wins when set. Palette position = triangle wave of (0.5·symmetry value + 0.06·radius + drift), continuous so the drift's wrap shows no jump. VIS-007's groups of the ANL-002 bands, sanitized: swell = low (attack τ 0.08 s, release τ 0.3 s) sets the seam inset from 25 % of each tile's inradius (silence) down to 8 % (full bass; depth × 0.5 with Reduce Motion); drift speed 0.02 + 0.04 × mid turns/s (≤ 0.06), travelling-light speed 0.25 + 0.25 × high turns/s (≤ 0.5), both × 0.5 with Reduce Motion, smoothed τ 0.5 s, advanced on the injected frame clock (≤ 0.25 s per frame, never backwards) and wrapped to [0, 1); the light dims tiles by at most 20 %; brightness 0.45 + 0.3 × overall (≤ 0.75, ACC-012), τ 0.25 s. Every value is NaN-guarded and clamped to 0…1. The FX-019 estimate samples the same tile function at the 64 points, each sample the tile's area-mean (colour × lit fraction (1 − inset)²) (VIS-018-R6, R7, R8, R9).
- Q: How does the app name and store it? → A: Visual choice "Tessellation" (stored `tessellation`), keys `settings.tessellation.tiling` (`triangle`/`square`/`hexagon`/`trihexagonal`/`truncatedSquare`, else `hexagon`), `settings.tessellation.tiles` (Int 2…16, else 6), `settings.tessellation.symmetry` (Int 1, 2, 3, 4 or 6, else 6), `settings.tessellation.mirror` (Bool, absent → off), `settings.tessellation.palette` (`spectrum`/`ice`/`mono`, else `spectrum`). Controls: Tiling picker (`tessellationTilingPicker`), Tiles stepper (`tessellationTilesStepper`), Symmetry segmented picker (`tessellationSymmetryPicker`), Mirror toggle (`tessellationMirrorToggle`), Palette segmented picker (`tessellationPalettePicker`, disabled while the colour-blind-safe palette is on). Accessibility label "Tessellation visualization", identifier `tessellation`, value "<Tiling>, <N> tiles, <symmetry>, <Palette> palette, <glow>" (e.g. "Hexagons, 6 tiles, 6-fold symmetry, Spectrum palette, Glow off"; "mirrored 6-fold symmetry", "no symmetry"). Every change applies in place from the next frame (same generator, the motion keeps going). No SCN-001 layer kind, as VIS-017 (VIS-018-R10, R12, R13).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Watch a tiling move with the music (Priority: P1)

A user chooses "Tessellation" and sees the screen filled edge to edge with polygon tiles (hexagons by default)
separated by thin dark seams. Bass makes the tiles swell so the seams narrow; the colours drift slowly across the
palette; a soft ring of light travels out from the centre.

**Why this priority**: It is the roadmap row's observable behaviour ("animate polygons and tilings").

**Independent Test**: Render the tiling with fixture bands at fixed times; tiles are visible with seams; more bass
narrows the seams within a bound; time drifts the colours.

**Acceptance Scenarios**:

1. **Given** the visual running with silence, **When** a frame is drawn, **Then** the whole frame is covered by tiles separated by dark seams.
2. **Given** a bass-heavy input, **When** the drive settles, **Then** the seams narrow but never vanish, and the tiles stay in place.
3. **Given** a fixed time and band timeline, **When** rendered, **Then** the frame matches the committed golden image (macOS host and iOS Simulator), and two renders are identical.

---

### User Story 2 - Change the tile count and keep the tiling aligned (Priority: P1)

The user picks a tiling (triangles, squares, hexagons, or the semi-regular trihexagonal and octagon-and-square
patterns) and a tile count. Whatever the count and whatever the screen shape (phone in portrait or landscape, iPad,
an external display, an ultra-wide window, a square window), the tiling stays centred and evenly sized, with no gaps,
overlaps or drifting seams.

**Why this priority**: The roadmap row's acceptance criterion.

**Independent Test**: For every tile count and every supported aspect ratio, classify pixels into tiles on the CPU and
on the GPU and check the alignment rules defined in Clarifications.

**Acceptance Scenarios**:

1. **Given** any tiling, tile count and supported aspect ratio, **When** a frame is drawn, **Then** the tiling is aligned (rules A1–A6 in Clarifications).
2. **Given** a tile count change while running, **When** the next frame is drawn, **Then** it uses the new count without restarting the animation.

---

### User Story 3 - Shape the colours with palette and symmetry (Priority: P2)

The user chooses a palette (Spectrum, Ice, Mono) and a symmetry (none, 2, 3, 4 or 6-fold, optionally mirrored). The
tiles' colours repeat that many times around the centre.

**Acceptance Scenarios**:

1. **Given** symmetry 6 on hexagons, **When** a frame is drawn, **Then** tiles that are 60° rotations of each other about the centre have the same colour and brightness.
2. **Given** mirror on, **When** drawn, **Then** tiles that are mirror images across a symmetry axis have the same colour.
3. **Given** the colour-blind-safe palette (ACC-003-R13) is on, **When** drawn, **Then** it wins over the tessellation's own palette choice.

---

### User Story 4 - Safe and calm when asked (Priority: P2)

The tiles never flash, their brightness stays below full white, and Reduce Motion slows the drift and the travelling
light and softens the swelling.

**Acceptance Scenarios**:

1. **Given** bass bursts alternating with silence, **When** drawn with Reduce flashing on and off, **Then** no area exceeds the strobe envelope's transition budget.
2. **Given** Reduce Motion on, **When** settled, **Then** the drift speed, the travelling light's speed and the swell depth are half.

---

### User Story 5 - Choose it in Settings (Priority: P2)

The user chooses "Tessellation" in Settings, sets its options, and the choices are remembered.

**Acceptance Scenarios**:

1. **Given** the visualizer running, **When** the user chooses Tessellation, **Then** it replaces the visual without restarting the audio source.
2. **Given** options chosen, **When** the app is relaunched, **Then** they are restored; a stored value out of range falls back to the default.

### Edge Cases

- Output size 0: nothing drawn. Very thin or very wide outputs: the shorter side still sets the tile size.
- Pixels exactly on a seam belong to exactly one tile (a deterministic tie rule), so no pixel is in two tiles or none.
- Bands absent, NaN or negative: read as silence; above 1: read as 1. Long frame gaps or time going backwards: at most a bounded step of motion per frame, never backwards.
- A symmetry that the tiling itself does not have (for example 6-fold on squares): the colouring still follows the order, but only tiles that are exact rotations of each other are guaranteed equal.
- Switching to and from the other noise-field modes keeps the generator; the tessellation's motion starts at rest.

## Requirements *(mandatory)*

### Functional Requirements

- **VIS-018-R1**: The tessellation MUST be a native visual under VIS-001's generator contract and the shared host; the projectM backend is untouched.
- **VIS-018-R2**: Five tilings MUST be offered: triangles (3.3.3.3.3.3), squares (4.4.4.4), hexagons (6.6.6), trihexagonal (3.6.3.6) and truncated square (4.8.8, octagons and squares).
- **VIS-018-R3**: A tile count from 2 to 16 (default 6) MUST set the tile size from the output's shorter side.
- **VIS-018-R4**: For every tiling, tile count and supported aspect ratio the tiling MUST be aligned as defined in Clarifications (A1–A6).
- **VIS-018-R5**: Symmetry order 1 (none), 2, 3, 4 or 6 (default 6) and a mirror option (default off) MUST shape each tile's colour and brightness from its centre's position, so tiles related by that rotation (and reflection when mirrored) about the frame centre look identical.
- **VIS-018-R6**: A palette choice Spectrum (default), Ice or Mono MUST colour the tiles; the shared colour-blind-safe or a custom palette wins when set.
- **VIS-018-R7**: Audio drive (ANL-002 bands, VIS-007 groups): low narrows the seams within a bound, mid speeds the colour drift within a cap, high speeds the travelling light within a cap, overall brightens within a cap below full white (ACC-012); smoothed on the injected frame clock; Reduce Motion halves the drift and light speeds and the swell depth.
- **VIS-018-R8**: Every output value MUST be finite and within 0…1 for any band input, time or output size.
- **VIS-018-R9**: Flash safety: every frame passes FX-019's envelope over all 17 areas, estimated from a CPU mirror of the same tiles.
- **VIS-018-R10**: The app MUST offer "Tessellation" as a Visual choice (stored `tessellation` under `settings.visual`) with five keys (tiling, tile count, symmetry, mirror, palette; out-of-range values fall back to the defaults). Glow shared; Bars hidden. The keys are FR-065 user settings, in the FILE-005 backup policy, the device privacy allow list, and reset by `-uitestResetNotice`.
- **VIS-018-R11**: A golden image of the tessellation MUST be compared under QA-002's rule per platform class (macOS host, iOS Simulator).
- **VIS-018-R12**: Scene capture records the visual as no native layer (as VIS-003-R12).
- **VIS-018-R13**: Accessibility (FR-070): one element labeled "Tessellation visualization", identifier `tessellation`, whose value names the tiling, tile count, symmetry, palette and glow; every option control has an identifier.
- **VIS-018-R14**: The other native visuals MUST NOT change behaviour: their tests and goldens pass; the package builds in the Linux shape.

### Key Entities

- **Tessellation settings**: tiling, tile count, symmetry order, mirror, palette.
- **Lattice placement**: tile size and the frame centre's position in the tiling, derived from the output size and tile count.
- **Tile (cell)**: integer lattice coordinates and a shape index; centre; distance from a point to the tile's edge.
- **Drive state**: swell, colour drift, travelling-light phase, brightness.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **VIS-018-S1**: For all 5 tilings × all 15 tile counts × 6 aspect ratios (phone portrait and landscape, iPad 4:3, 16:9, 21:9, square), rules A1, A2 and A5 hold at a grid of sample points, and A3, A4 hold over every pixel for representative counts and ratios (the full per-pixel sweep is an on-demand bench).
- **VIS-018-S2**: On the GPU, every pixel's tile equals the CPU's tile (pixels within 0.01 px of a seam excluded) for every tiling at representative tile counts and all 6 aspect ratios.
- **VIS-018-S3**: With extreme inputs (NaN, ±infinity, 10⁶ band values, a 10⁹ s time), every pixel of a floating-point render is finite and within 0…1.
- **VIS-018-S4**: Two GPU renders from scratch are identical, and the goldens pass on the macOS host and the iOS Simulator.
- **VIS-018-S5**: Bass bursts alternating with silence stay within the transition budget in all 17 areas with Reduce flashing on and off.
- **VIS-018-S6**: One UI test of at most 30 s chooses the visual and changes an option with the source started once; the settings persist (unit test); the keys are in every list.
- **VIS-018-S7**: New package tests take a few seconds in total; every existing test passes; the package builds in the Linux shape.

## Assumptions

- Bands come from the native host's own analysis (ANL-002), as for every native visual.
- Supported aspect ratios: phone portrait (1179 × 2556) and landscape, iPad 4:3 (2048 × 1536), 16:9 external display (1920 × 1080), 21:9 (2520 × 1080), square (1080 × 1080); the rules hold for any size, these are the tested ones.
- Simulator results are not device evidence; the frame rate and look on D1 are `{device}` work.
- Five new setting keys; no network; the privacy manifest does not change.
- projectM stays the default visual.
