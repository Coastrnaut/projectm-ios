# Feature Specification: CMP-004 Blend Mode Library

**Feature Branch**: `feature/cmp-004` (spec directory `099-cmp-004-blend-mode-library`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement CMP-004 (Blend mode library) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Support normal, add, screen,
multiply, overlay and difference." Acceptance, verbatim: "Each mode matches reference pixel
equations within tolerance." Verification: unit tests, snapshots and GPU performance. Depends on
CMP-001 (integrated); builds on CMP-002 (layer stack), CMP-003 (opacity), CMP-005 (transforms) and
SCN-001 (scene format)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `CMP-004-R1…`, success criteria `CMP-004-S1…`, tasks `CMP-004-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `d964e8d`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| Layer contract | `LayerBlendMode` has one case, `normal` (premultiplied "over"). `LayerCompositeSettings.isSupportedByCompositor` is true only for `normal`; `Compositor.init` and `apply` throw `unsupportedCompositeSettings` for anything else. | No other mode can even be expressed in the contract. |
| Compositor | Every shown layer is drawn into one `rgba16Float` composite in one render pass, with fixed-function blending `one, oneMinusSourceAlpha` (premultiplied "over"). Layers are sanitized (non-finite → 0, colour ≥ 0, alpha 0…1) and multiplied by their CMP-003 opacity in the fragment shader; CMP-005 transformed layers are sampled bilinearly through the inverse placement. | Fixed-function blending cannot express multiply, overlay or difference within source-over: they need the backdrop in the shader. |
| Colour | Pictures and the composite are **linear light**, Rec. 709 primaries, D65, **premultiplied alpha**, `rgba16Float` (CMP-001 contract). The output pass writes composite × flash gain into the caller's format, which encodes (`bgra8Unorm_srgb` for the screen). All "over" blending happens in linear light. | No rule says in which space a blend function runs. |
| Scene format | SCN-001 (ADR-0028) stores `composite.blend` as **any string**, default `"normal"`. Any other string is kept verbatim on decode and encode and gives the warning `unsupportedBlendMode` ("…which this version draws as normal."), which SCN-012's repair report lists under "values adjusted" (note). The live-state adapter maps every layer to `.normal`; capture writes `"normal"`. ADR-0028 already says CMP-004 extends the capture switch and the list of drawn names. Every fixture and golden scene uses `"normal"`. | Known mode names are still reported as unsupported; a live round trip turns any other mode into `"normal"`. |
| Modulation "mix" | The "replace", "add" and "multiply" mixes in SCN-001/SCN-013 fixtures and QA-002 goldens are `ModulationMixMode` (how a parameter binding combines with the parameter's value), not layer blending. | None; out of scope. |
| Layers (CAM, MED, Text, spectra, materials, graphs, projectM) | None sets `compositeSettings`; all use the default (opacity 1, normal, identity). | None; every layer kind can take any mode through its stack entry. |
| UI | No screen chooses a layer's opacity, transform or blend; stacks come from code, scenes and show cues. | None required (Clarifications). |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative option that fits the constitution.

- Q: Which equations define the modes? → A: W3C Compositing and Blending Level 1: the separable
  blend function B(Cb, Cs) on straight (non-premultiplied) colours, combined with source-over
  alpha compositing. In premultiplied form, with cs = αs·Cs and cb = αb·Cb:
  co = cs·(1 − αb) + cb·(1 − αs) + αs·αb·B(Cb, Cs) and αo = αs + αb·(1 − αs) (CMP-004-R2, R3).
- Q: In which colour space does B run? → A: B runs on **sRGB-encoded** straight colours clamped to
  0…1, and its result is decoded back to linear light before the source-over terms, which stay in
  the compositor's linear premultiplied space (CMP-004-R4; ADR-0037). For opaque layers the shown
  pixel is exactly what browsers and design tools show for the same encoded colours (multiply of
  two 50 % greys is 25 % grey on screen); for partial alpha the coverage mix is linear, like every
  normal layer here, so `normal` keeps its current, bit-identical path. Rejected: B in linear light
  (screen and overlay then look far brighter than any designer expects); everything in encoded space
  (would change every existing normal composite and the goldens).
- Q: What does "add" mean? → A: The separable blend function B(Cb, Cs) = min(1, Cb + Cs) inside the
  same source-over formula (Photoshop's "Linear Dodge (Add)"), not Porter-Duff "plus"
  (CMP-004-R3). One formula for all six modes, the result alpha is source-over's like every other
  mode, add over a transparent backdrop equals normal, and the clamp keeps it in the encoded range.
  Rejected: Porter-Duff plus (co = cs + cb, αo = min(1, αs + αb)): its alpha differs from the other
  modes and it can brighten unbounded in the half-float composite.
- Q: How does opacity combine with a mode? → A: As CMP-003 defines it: the layer's premultiplied
  picture is multiplied by its opacity first (αs and cs both scale), then the mode's formula runs.
  Opacity 0 contributes nothing in every mode; opacity 1 is the plain mode (CMP-004-R5).
- Q: What happens to values outside 0…1? → A: The picture is sanitized as today. For B only, straight
  colours are clamped to 0…1 before encoding; the source-over terms keep the unclamped values
  (CMP-004-R4). Linear values above 1 (bright glows) therefore keep their brightness where the layers
  do not overlap, and B is defined everywhere. A pixel with alpha 0 has straight colour 0 (its B term
  is multiplied by αs·αb = 0 anyway).
- Q: Does the scene format change? → A: No. `composite.blend` already holds any string. The six names
  `normal`, `add`, `screen`, `multiply`, `overlay`, `difference` (exact, lower case) are now drawn and
  no longer warned about; any other string is still kept verbatim, still gives `unsupportedBlendMode`
  (listed by SCN-012's repair report) and is drawn as normal (CMP-004-R7). The format version stays
  1, so QA-004's migration matrix gains no row; a version-1 file written before this feature with
  `"blend": "screen"` now draws as screen, which is what its author asked for.
- Q: Is an unknown mode kept through a live round trip (load → capture)? → A: Yes. The live state
  remembers the unknown string per layer and capture writes it back while that layer is still drawn
  as normal (CMP-004-R8). Before this feature the string survived only decode → encode.
- Q: Is there a mode picker in the UI? → A: No. No screen chooses a layer's opacity, transform or
  mix today; stacks come from code, scenes and show cues. A picker belongs with the layer inspector
  row that edits a stack (CMP-002's editing UI); recorded so that row adds it (CMP-004-R9).
- Q: How is a non-normal mode drawn on the GPU? → A: The backdrop is read in the fragment shader.
  Each non-normal layer ends the current pass and draws one full-screen pass into a second composite
  texture, reading the backdrop and the picture and writing the formula's result without fixed-function
  blending; the two composites then swap (CMP-004-R6). Normal layers keep the current fixed-function
  path. Rejected: framebuffer fetch (programmable blending) is cheaper on Apple GPUs but the iOS
  Simulator and older Mac GPUs do not support it, and the tests must run there.
- Q: What tolerance proves "matches reference pixel equations"? → A: GPU result versus a plain-Swift
  reference computed from the same half-float inputs: at most 1e-3 per linear channel in the
  half-float composite (half-float spacing below 1 is at most 4.9e-4, plus float32 transfer-function
  error) and at most 1/255 per channel after 8-bit sRGB output encoding (CMP-004-S1, S2).

### Session 2026-11-14 (speckit-clarify)

- Q: Is there a GPU time limit per mode that the feature must meet? → A: No pass/fail limit on the
  Mac: the row's "GPU performance" is a measurement of a full-screen two-layer composite per mode
  (Release, Mac host), recorded with normal as the baseline and labelled "not device evidence"
  (CMP-004-S6). The owner's short-test rule forbids wall-clock assertions; a device budget belongs to
  a device stage.
- Q: Are new RenderGoldens images added for the modes? → A: No. The "snapshots" are the GPU read-back
  tests, which compare every pixel of a rendered backdrop × source grid with the reference equations
  (stronger than a stored image, and nothing to re-record). Existing goldens must stay unchanged
  (CMP-004-S4); adding a golden scene per mode would add six images for no extra coverage.
- Q: When a mode changes during an opacity fade, is the mode change animated? → A: No. The mode
  switches at the next frame (like a CMP-005 transform); a running opacity fade continues with the new
  mode (CMP-004-R6). Cross-fading between two modes would need two composites of the same layer.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Layers combine with the six standard modes (Priority: P1)

A scene author (or a show cue, or code) sets a layer's mix to add, screen, multiply, overlay or
difference. The visualizer combines that layer with everything below it exactly as the standard
equations say, so a spectrum in "screen" over a camera picture brightens it without hiding it, and
"difference" inverts what is under a white layer.

**Why this priority**: It is the row's observable behavior and its acceptance.

**Independent Test**: Render a backdrop pattern and a source pattern with each mode and compare every
pixel to the reference equations.

**Acceptance Scenarios**:

1. **Given** an opaque 50 % grey backdrop and an opaque 50 % grey layer (encoded values), **When**
   the layer's mode is multiply, screen, overlay, difference, add or normal, **Then** the shown
   pixel is 25 %, 75 %, 50 %, 0 %, 100 % or 50 % grey respectively (encoded), within tolerance.
2. **Given** any grid of backdrop colours, layer colours and alphas, **When** each mode is drawn,
   **Then** every composite pixel matches the reference within 1e-3 (linear) and every output pixel
   within 1/255 (8-bit sRGB).
3. **Given** a layer with a non-normal mode over a transparent area, **When** drawn, **Then** that
   area shows the layer exactly as normal mode would.

---

### User Story 2 - Modes work with opacity, transforms, fades and the rest of the stack (Priority: P1)

A layer in any mode can also be faded (CMP-003), moved or scaled (CMP-005), reordered (CMP-002) and
can sit anywhere in a stack of up to eight layers with other modes above and below it.

**Why this priority**: A mode that breaks opacity or transforms would be unusable in scenes.

**Independent Test**: The same layer at opacity 0, 0.5 and 1, and with a transform, in each mode,
compared with the reference.

**Acceptance Scenarios**:

1. **Given** a layer in any mode, **When** its opacity is 0, **Then** the output is bit-identical to
   the stack without it; **When** its opacity is 0.5, **Then** the result is the formula with the
   layer's colour and alpha halved.
2. **Given** a stack of only normal layers, **When** composited after this feature, **Then** every
   output byte is identical to before (the existing tests and goldens pass unchanged).
3. **Given** a stack edit that changes only a layer's mode, **When** applied, **Then** the new mode
   shows from the next frame and no layer is recreated.

---

### User Story 3 - Scenes keep and show modes (Priority: P2)

A scene file names a layer's mode. Opening it shows the mode; saving it writes the mode back; an
unknown mode from a newer version is kept, reported, and drawn as normal.

**Why this priority**: Scenes are how modes reach users today.

**Independent Test**: Decode a scene with each known mode and one unknown mode, load it into a live
state, capture it and encode it again.

**Acceptance Scenarios**:

1. **Given** a scene whose layers use the six names, **When** validated, **Then** no
   `unsupportedBlendMode` warning appears and the live stack carries those modes.
2. **Given** a layer with `"blend": "softLight"`, **When** loaded, **Then** the repair report lists
   it as a note, the layer draws as normal, and capture writes `"softLight"` back.

### Edge Cases

- Alpha 0 in the backdrop or the layer: straight colour is 0; the formula reduces to the other side.
- Non-finite or negative channels in a picture: sanitized to 0 before blending, as today.
- Linear values above 1: clamped for B only; non-overlapping coverage keeps them.
- A mode layer at the bottom of the stack (transparent backdrop): equals normal.
- Several mode layers in a row: each reads the result of everything below it.
- Mode string with different case (`"Screen"`): unknown, kept, warned, drawn as normal.
- A transformed mode layer: sampled exactly as a transformed normal layer, outside reads transparent.
- Reduce flashing: the composite flash guard runs on the finished composite, after every mode.

## Requirements *(mandatory)*

### Functional Requirements

- **CMP-004-R1**: The layer contract MUST offer six blend modes, `normal`, `add`, `screen`,
  `multiply`, `overlay` and `difference`, each with a stable lower-case name, and the compositor MUST
  draw every one of them (no mode is refused).
- **CMP-004-R2**: Every mode MUST composite as co = cs·(1 − αb) + cb·(1 − αs) + αs·αb·B(Cb, Cs),
  αo = αs + αb·(1 − αs), with cs, cb premultiplied and Cs, Cb straight colours (contract
  `contracts/blend-modes.md`).
- **CMP-004-R3**: The blend functions MUST be, per channel: normal B = Cs; multiply B = Cb·Cs;
  screen B = Cb + Cs − Cb·Cs; overlay B = HardLight(Cs, Cb), that is 2·Cb·Cs if Cb ≤ 0.5, else
  screen(Cs, 2·Cb − 1); difference B = |Cb − Cs|; add B = min(1, Cb + Cs).
- **CMP-004-R4**: B MUST run on sRGB-encoded straight colours clamped to 0…1 and its result MUST be
  decoded to linear light before the source-over terms, which run in the compositor's linear
  premultiplied space with the unclamped sanitized values.
- **CMP-004-R5**: A layer's CMP-003 opacity MUST scale its premultiplied picture before the formula;
  its CMP-005 transform MUST sample the picture as for a normal layer.
- **CMP-004-R6**: Normal layers MUST keep today's drawing path, so stacks of only normal layers give
  bit-identical output; non-normal layers MUST read the backdrop in the shader. The extra composite
  texture MUST come from the texture pool, be created only when a non-normal layer is first drawn at
  a size, and go back to the pool with the others. A mode change at `apply` MUST show from the next
  frame without recreating any layer.
- **CMP-004-R7**: The scene format MUST stay at version 1. Validation MUST warn `unsupportedBlendMode`
  only for names outside the six; the live state MUST carry the six modes; capture MUST write the
  mode's name.
- **CMP-004-R8**: An unknown mode string MUST be kept verbatim through decode → encode and through
  load → capture (while the layer is drawn as normal), and MUST appear in SCN-012's repair report.
- **CMP-004-R9**: No UI is added; the stack editing row adds a mode picker with the six names.
- **CMP-004-R10**: A plain-Swift reference of every equation MUST exist and build on Linux, so the
  tests compute expected pixels in the same space the GPU uses.

### Key Entities

- **Blend mode**: one of six named rules for combining a layer with what is below it.
- **Backdrop / source**: the composite so far (Cb, αb) and the layer's picture after opacity
  (Cs, αs), both premultiplied linear light in storage.
- **Blend reference**: the plain-Swift evaluation of the contract used by tests.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CMP-004-S1**: For every mode, on a grid of at least 5 colour levels (0, 0.25, 0.5, 0.75, 1) per
  side and 4 alpha pairs, every rendered composite channel is within 1e-3 of the reference.
- **CMP-004-S2**: The same frames written to an 8-bit sRGB output are within 1/255 per channel of
  the reference encoded to 8 bits.
- **CMP-004-S3**: The hand-checked values hold: multiply(0.5, 0.5) = 0.25, screen(0.5, 0.5) = 0.75,
  overlay at Cb = 0.5 equals multiply-by-2 (2·0.5·Cs = Cs), difference is symmetric, add saturates
  at 1, normal returns Cs.
- **CMP-004-S4**: Opacity 0 in any mode is bit-identical to the stack without the layer; normal-only
  stacks are bit-identical to before (all existing compositor tests and RenderGoldens pass unchanged).
- **CMP-004-S5**: Scene round trips keep every known and unknown mode (decode → encode and load →
  capture), and known modes give no warning.
- **CMP-004-S6**: The GPU time of a full-screen two-layer composite per mode is measured on the Mac
  (Release) and recorded; it is a measurement, not device evidence and not an assertion.

## Assumptions

- The composite stays linear `rgba16Float`; the output format does the final encoding (CMP-001).
- At most eight layers (CMP-002), so one extra full-screen pass per non-normal layer is affordable.
- Tests run on the Mac host and the iOS simulator (Metal) and the CPU parts on Linux; device timing
  is a later device stage, not part of this row.
