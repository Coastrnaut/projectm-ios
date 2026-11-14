# Feature Specification: SHD-004 Shader Variant Switching

**Feature Branch**: `feature/shd-004` (spec directory `231-shd-004-shader-variant-switching`)
**Created**: 2026-11-14
**Status**: Draft
**Input**: User description: "Implement SHD-004 (Shader variant switching) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Select among precompiled visual shader
variants at runtime." Acceptance, verbatim: "Switching preserves scene and falls back on unsupported GPU."
P1, depends on SHD-001 (integrated: Packages/Compositor/Sources/ProceduralMaterials, ADR-0018)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `SHD-004-R1…`, success criteria `SHD-004-S1…`, tasks `SHD-004-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `96ee68c7`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| Materials (SHD-001) | Five curated materials. Each is one fragment function (`mat_<name>`) of one module-constant Metal source (`ProceduralMaterialShaders.source`), compiled once per layer in `ProceduralMaterialLayer.prepare`, which builds exactly one pipeline. Goldens: one 18-value signature per material (`MaterialRenderTests`). | One implementation per material; nothing can choose another. |
| Metadata (SHD-003) | One data-only JSON document per material with a `variant` key (= the material name), name, summary and parameters; a strict validator; a slot cross-check of the fragment function (`check(source:function:)`), run in tests and in `prepare`. | The document describes exactly one variant; there is no list of alternatives and no GPU requirement. |
| Scenes (SCN-001, CMP-015) | A material layer is stored as `{"kind": "material", "content": {"material": "material.<name>"}, …}`; its values are in the scene's parameters. Unknown layer fields are kept verbatim (`extra`). The app keeps material layers in scenes but does not draw them; the CMP-015 layer inspector shows SHD-003's generated "Material settings", disabled. RenderGoldens' scene harness draws material layers from scenes. | No field records which implementation a layer uses. |
| GPU capability | No code checks a GPU family (`supportsFamily` is not used anywhere); ANGLE and the compositor assume one Metal device. | Nothing decides whether an implementation can run on the device, and nothing falls back. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- (filled by /speckit-clarify)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A material offers alternative precompiled implementations (Priority: P1)

A developer adds an alternative implementation of a material (a lower-cost one, or a more detailed one
that needs a newer GPU) by writing one more fragment function in the reviewed shader source and listing
it in that material's metadata with a label and, if needed, the GPU family it requires. Checks reject a
variant list that is malformed, repeats an ID, names an unknown GPU family, gives the default variant a
requirement, or names a function whose slot reads do not match the material's parameters.

**Why this priority**: The variants are what is switched.

**Independent Test**: Validate every bundled document (all pass, with the expected variants); validate
one document per class of mistake (each fails with its own error).

**Acceptance Scenarios**:

1. **Given** the bundled metadata, **When** it is validated, **Then** Plasma lists Standard and Detailed
   (Detailed requires Apple GPU family 9), Noise Flow lists Standard and Low cost, and every other
   material lists only Standard; every variant's function passes the slot check.
2. **Given** a document whose first variant is not the document's own variant, whose variant IDs repeat,
   or whose variant requires an unknown family, **When** it is validated, **Then** each is rejected with
   its own error.

---

### User Story 2 - Switching the variant keeps the scene (Priority: P1)

Someone switches a material layer from Standard to Detailed (or Low cost) and back. The picture changes
to the selected implementation from the next frame, with no pause; every parameter value, the motion
phase and the layer's composite settings stay as they were; the saved scene differs only in the layer's
variant field.

**Why this priority**: It is the first half of the acceptance ("switching preserves scene").

**Independent Test**: On the GPU, drive a Plasma layer, switch variants, read back each variant's picture
(golden signature per variant), and compare parameter values and motion before and after; encode the
scene before and after switching and compare bytes.

**Acceptance Scenarios**:

1. **Given** a Plasma layer with non-default values drawn for 30 frames, **When** Detailed is selected,
   **Then** the next frame matches Detailed's golden-signature path, every parameter value and the motion
   phase are unchanged, and no pipeline is created during the switch.
2. **Given** a scene with that layer, **When** its variant is set and the scene re-encoded, **Then** the
   bytes equal the original except for the layer's `materialVariant` field; selecting Standard again gives
   back the original bytes.
3. **Given** a scene with a variant, **When** it is decoded, turned into live state and captured again,
   **Then** the variant survives (round trip byte-equal).

---

### User Story 3 - An unsupported variant falls back safely (Priority: P1)

On a GPU that lacks the family a variant requires (or when a scene names a variant this version does not
know), the layer draws the material's Standard variant, says why in a notice, never crashes or goes
blank, and keeps the stored choice so the scene still asks for it on a capable device.

**Why this priority**: The second half of the acceptance ("falls back on unsupported GPU").

**Independent Test**: With an injected GPU capability that lacks family 9, select Detailed: the layer
draws Standard's picture, reports the unsupported notice naming the family, and keeps `selectedVariant`
= Detailed; a scene naming `plasmaUltra` validates with an `unknownMaterialVariant` warning and draws
Standard.

**Acceptance Scenarios**:

1. **Given** a capability without family 9, **When** a Plasma layer is prepared with Detailed selected,
   **Then** it renders the Standard picture, its notice is "unsupported (requires Apple GPU family 9)",
   and the selection is still Detailed.
2. **Given** a scene whose material layer names an unknown variant, **When** it is validated, **Then** a
   warning `unknownMaterialVariant` is reported at `$.layers[i].materialVariant` and the scene still opens.

---

### User Story 4 - The inspector offers the variants (Priority: P2)

Someone inspecting a material layer that has more than one variant sees a "Variant" picker in its
Material settings, built from the metadata (labels in order), showing the stored choice, and a note when
the stored choice is not supported on this device.

**Why this priority**: Visible control; material layers are not drawn by the app in this version, so
like SHD-003's controls the picker is shown read-only.

**Independent Test**: For Plasma, the inspector model's variant options equal the metadata; for Gradient
Field (one variant) there is no picker; the app shows the picker for the seeded Plasma layer.

**Acceptance Scenarios**:

1. **Given** the seeded Plasma layer, **When** its detail opens, **Then** the Material settings section
   has a "Variant" picker with Standard and Detailed, showing Standard, disabled with the read-only reason.

---

### Edge Cases

- A scene's `materialVariant` that is not text: dropped with a `droppedField` warning, the layer drawn
  with Standard.
- `materialVariant` on a non-material layer: kept verbatim as an unknown field, unused.
- A variant whose pipeline fails to build on the device: the layer falls back to Standard with a
  "pipeline unavailable" notice. If Standard itself fails, the layer is unavailable (SHD-001 behaviour:
  the compositor's transparent fallback).
- Selecting a variant before the layer is prepared: prepare builds every supported variant, so the first
  frame already draws the choice.
- Switching every frame: no allocation or pipeline creation in render; only the cached pipeline changes.

## Requirements *(mandatory)*

### Functional Requirements

- **SHD-004-R1**: A material's metadata document MAY list its variants in an optional `variants` array
  (2 to 4 entries; absent = one implicit variant, the document's `variant`, labelled "Standard"). Each
  entry has `id` (well-formed, unique, starting with the document's `variant`), `label` (1-64 characters)
  and an optional `requires` naming an Apple GPU family (`apple7`, `apple8`, `apple9`). The first entry is
  the default: its ID MUST equal the document's `variant` and it MUST NOT have a requirement. Unknown keys
  are rejected. All variants share the document's parameters (same IDs, ranges, defaults, slots).
- **SHD-004-R2**: Every variant's fragment function (`mat_<variant id>`) MUST exist in the module's
  constant shader source and pass SHD-003's slot check against the shared parameters, in the unit tests
  and when a layer is prepared.
- **SHD-004-R3**: The bundled catalog MUST offer Plasma "Detailed" (`plasmaDetailed`, requires `apple9`)
  and Noise Flow "Low cost" (`noiseFlowLite`, no requirement); each obeys SHD-001's safety rules (motion at
  most one cycle per unit of phase, output clamped, finite, opaque). Every Standard picture stays as
  recorded (SHD-001 goldens unchanged).
- **SHD-004-R4**: A material layer MUST hold a selected variant (nil = default) that can be changed at any
  time between frames without changing its parameter values, motion state, composite settings or layer
  identity, and without creating a pipeline at render time: `prepare` builds and caches the pipelines of
  the default and every supported variant.
- **SHD-004-R5**: The layer MUST decide its drawn variant from the selection, the metadata and an
  injectable GPU capability: the selection if it is known, supported and its pipeline built; otherwise the
  default variant, with a notice (`unknownVariant`, `unsupported(requires:)`, `pipelineUnavailable`). The
  selection itself is kept.
- **SHD-004-R6**: The scene format MUST store a material layer's selected variant as the optional layer
  field `materialVariant` (text), written only when a non-default variant is selected, with no version
  bump; decode, live state and capture MUST carry it so a round trip is byte-equal. Validation MUST warn
  `unknownMaterialVariant` for a variant the material does not list.
- **SHD-004-R7**: The scene renderer used for goldens (RenderGoldens) MUST draw a material layer with its
  stored variant.
- **SHD-004-R8**: The layer inspector MUST show a "Variant" picker for a material with more than one
  variant, built from the metadata, with accessibility identifier `materialVariant`; read-only while the
  app does not draw material layers, with a note when the stored choice is unsupported on this device.
- **SHD-004-R9**: No shader is compiled from scene, metadata or other external text: variants are
  functions of the reviewed module constant (SHD-011, `MaterialSourceSafetyTests`).

### Key Entities

- **Material variant**: one precompiled implementation of a material: ID, label, optional GPU family
  requirement, fragment function.
- **GPU capability**: which Apple GPU families the device supports (injectable for tests).
- **Variant resolution**: the drawn variant and an optional notice, derived from selection, metadata and
  capability.
- **Scene layer `materialVariant`**: the stored selection.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SHD-004-S1**: All five bundled documents validate with the variants of R3, and each of at least five
  classes of invalid variant list is rejected with its own error.
- **SHD-004-S2**: On the GPU, each of the seven variants (five Standard, Detailed, Low cost) renders valid
  pixels and matches its golden signature within 0.02 per channel; Detailed and Low cost differ from their
  Standard.
- **SHD-004-S3**: Switching a variant keeps 100% of the layer's parameter values and its motion phase, and
  the re-encoded scene differs from the original only in `materialVariant` (byte-equal after removing it).
- **SHD-004-S4**: With a capability lacking the required family, the layer draws the Standard picture
  (signature within 0.02), reports the notice and keeps the selection; no crash.
- **SHD-004-S5**: Unit tests run in under 10 s each, the package suites under one minute, the UI test
  under 30 s.

## Assumptions

- "Precompiled" means built before use: variant pipelines are built in `prepare` (off the render path) and
  cached; the build Mac has no Metal Toolchain (ADR-0009), so the module constant is compiled at prepare
  time as in SHD-001.
- The app does not draw material layers in this version (CMP-015, SHD-003), so the switch and fallback
  are proven in the package on the GPU and the inspector picker is read-only.
- D1 (A16) and D3 (A16) are Apple GPU family 8; D2 (M5) supports family 9. The device check of the
  fallback and the Detailed picture is a `{device}` task.
- No new UserDefaults keys.
