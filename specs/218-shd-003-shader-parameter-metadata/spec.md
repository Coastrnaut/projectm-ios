# Feature Specification: SHD-003 Shader Parameter Metadata

**Feature Branch**: `feature/shd-003` (spec directory `218-shd-003-shader-parameter-metadata`)
**Created**: 2026-11-14
**Status**: Draft
**Input**: User description: "Implement SHD-003 (Shader parameter metadata) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Define typed sliders and enums for
bundled shader variants." Acceptance, verbatim: "Inspector builds controls directly from validated
metadata." P1, depends on MOD-001 (integrated: Packages/ParameterGraph, ADR-0012)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `SHD-003-R1…`, success criteria `SHD-003-S1…`, tasks `SHD-003-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `0002a60`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| Bundled shader variants | SHD-001 (ADR-0018) ships five procedural materials (Gradient Field, Plasma, Noise Flow, Ring Tunnel, Starfield). Each material's parameters are Swift calls (`continuous(…)`, `color(…)`) in `ProceduralMaterialCatalog.swift`; parameter *i* is uniform slot *i* of one module-constant Metal source, by convention only. SHD-002 graphs and the native spectra use their own fixed settings. | Parameters are code, not data; nothing checks that a declared parameter matches the slot the shader reads (a color read as a number, or a slot the shader reads that no parameter fills). No material offers a choice (enum) or an on/off value. |
| MOD-001 catalog | `ParameterDescriptor` (ID, display name, group, unit, kind continuous / integer / boolean / enum / color, range, default, step, modulation policy) and `ParameterRegistry` validation. SceneArchiveService registers the material descriptors with the visual catalog. | Nothing to change: metadata must produce these descriptors. |
| Inspectors | UIX-003's parameter inspector shows one registry parameter whose app setting it knows (seven IDs, hand-mapped). CMP-015's layer inspector lists a material layer (`Material (plasma)`) read-only with its composite values; its "Layer Settings" lists only spectrum values, hand-coded per kind. | No inspector shows a material's own parameters, and nothing builds controls from parameter metadata generically. |
| Expressions | SHD-009 maps formulas onto registry parameters (opcodes are unrelated to metadata). | None. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: What is the metadata, and where does it live? → A: One declarative, data-only document per bundled shader variant (each SHD-001 material), written as JSON text in the module that authors the shader, next to it, and read with a strict reader. It names the variant, its summary and its parameters; each parameter has an ID, a label, a kind (`float`, `int`, `bool`, `enum`, `color`), a range and step for numbers, a unit, a default, enum cases for enums and its uniform slot. It holds no expressions, code, paths or file names. Rejected: keeping Swift calls (code, not data; nothing can reject an unknown key) and loading files from the bundle at run time (a resource and a failure path for content that never changes).
- Q: What does validation check? → A: Unknown keys at every level; missing required keys; wrong value types; supported schema version; known kinds and units; well-formed, unique parameter IDs and enum case IDs; labels 1-64 characters; finite numbers; minimum below maximum; default within range (integers also on a step); step positive and at most the range; enum with 2-16 cases and a default that is one of them; colors with four components in 0…1; at most eight parameters; slot *i* declared at position *i*; and a required speed and audio reactivity per material. Against the shader source: every slot the variant's fragment function reads is declared, and a slot read as a vector (`.rgb`) is a color while a slot read as one component (`.x`) is a number, choice or switch. Each failure is one typed error naming the document, the parameter and the key.
- Q: Which variant gets the first enum, and does it change what users see today? → A: Gradient Field gains "Shape" (`material.gradient.shape`, Linear or Radial, default Linear). Linear is the current picture, so every SHD-001 golden stays as recorded; Radial blends the two colors from the centre outward with a slow breathing of the boundary (bounded like the rotation). No other material changes. Rejected: adding a switch that blinks or a choice that changes brightness abruptly (flash risk).
- Q: How are validated parameters registered? → A: The catalog builds every material's MOD-001 descriptors from its validated metadata (float → continuous, modulatable by default; int, bool, enum and color → manual with external control allowed), with the same IDs, ranges, defaults and units as SHD-001. The existing registry checks run on top. Bundled metadata that fails validation is a programming error caught by unit tests in CI, so the app never ships it.
- Q: Which inspector builds the controls, and can people change values today? → A: The CMP-015 layer inspector's material layer gains a "Material settings" section: one control per metadata parameter, in metadata order, made by one generic builder (slider for numbers with a fractional step, stepper for integers, picker for enums, toggle for switches, color well for colors), each with the parameter's label, range, step, unit-formatted value and spoken value. No control is written per shader. This version keeps material layers in scenes but does not draw them (CMP-015), so the controls show the scene's values (or defaults) and are disabled with the existing read-only reason; the row that draws materials enables them. Rejected: a Debug-only material screen (no user sees it) and making undrawn values editable (people would change something they cannot see).
- Q: Does UIX-003's single-parameter inspector (the sheet opened from a Settings control) also list material parameters? → A: No. It edits app settings through hand-mapped targets, and no Settings control edits a material; material parameters appear only in the layer inspector's generated section. A later row that adds material settings can open the same generated controls. Rejected: adding material IDs to `inspectableIDs` (they have no app setting to write).
- Q: What does each generated control speak as its value? → A: UIX-003's text for the descriptor (`ParameterValueText.spoken`): numbers with their unit ("35 percent", "0.12 per second"), whole numbers as numbers, choices by case label ("Linear"), switches "On"/"Off", colors as their four components. The visible value uses UIX-003's display text. One formatter for both inspectors keeps them consistent.
- Q: How is "a parameter change takes effect" shown on the GPU? → A: A 64 × 64 render of Gradient Field at defaults and with Shape set to Radial through the metadata-built control's value: the pictures differ (centre versus corner brightness order reverses), and the Radial picture's signature is stored as a golden like SHD-001's (tolerance 0.02 per channel).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Each bundled shader variant declares its parameters as checked data (Priority: P1)

A developer adding or changing a bundled shader variant writes its parameters as a small data document
next to the shader. Before the app can ship, checks reject any document with an unknown key, a default
outside its range, a duplicate ID, a bad enum or a slot that does not match what the shader reads, with
an error that names the variant, the parameter and the problem.

**Why this priority**: It is "validated metadata", the input of the acceptance.

**Independent Test**: Validate each bundled document (all pass); validate one document per class of
mistake (each fails with its precise error).

**Acceptance Scenarios**:

1. **Given** the five bundled documents, **When** they are validated, **Then** all pass and describe the
   same parameters (IDs, ranges, defaults, units) as SHD-001 plus Gradient Field's Shape.
2. **Given** a document with an unknown key `colour` in parameter 2, **When** it is validated, **Then**
   it is rejected with an error naming the key and parameter 2.
3. **Given** a document whose default is outside its range, whose enum default is not a case, whose IDs
   repeat, or whose color is declared on a slot the shader reads as a number, **When** it is validated,
   **Then** each is rejected with its own error.

---

### User Story 2 - Validated parameters are registered in the parameter catalog (Priority: P1)

Every validated parameter becomes a MOD-001 parameter with a stable ID, range, default, unit and
modulation policy, so scenes, modulation, MIDI/OSC and the inspector see it like any other parameter.

**Why this priority**: The roadmap row depends on MOD-001; everything downstream reads the registry.

**Independent Test**: Build the registry from the catalog; it validates and contains every metadata
parameter with the documented values.

**Acceptance Scenarios**:

1. **Given** the catalog, **When** its registry is built, **Then** it holds 29 parameters (SHD-001's 28
   plus `material.gradient.shape`) with no validation issue.
2. **Given** `material.gradient.shape`, **When** a value `radial` is set on a Gradient Field layer,
   **Then** the next frame draws the radial shape; an unknown case is refused and the value stays.

---

### User Story 3 - The inspector builds controls from the metadata (Priority: P1)

Someone inspecting a material layer sees that material's settings: a slider per number, a stepper for
whole numbers, a picker for choices, a toggle for switches and a color well for colors, each labelled and
spoken as the metadata says, in metadata order.

**Why this priority**: It is the row's acceptance.

**Independent Test**: For every material, the control list the inspector builds equals its metadata
(kinds, labels, ranges, steps, enum options) and each control's accessibility value is the formatted
current value; the app shows those controls for the seeded `material.plasma` layer.

**Acceptance Scenarios**:

1. **Given** Plasma's metadata, **When** the inspector builds its controls, **Then** it gets five
   sliders labelled as the metadata with the metadata's ranges and steps, in order.
2. **Given** Gradient Field, **When** the controls are built, **Then** Shape is a picker with Linear and
   Radial, and the two colors are color wells.
3. **Given** the seeded scene with a Plasma layer, **When** the layer's detail opens, **Then** the
   Material settings section shows one control per Plasma parameter with its label and value, disabled
   with the read-only reason.

---

### Edge Cases

- Metadata that is not JSON, has a number where text is expected, or is a different schema version: rejected
  with a precise error, never partly accepted.
- An enum default that is a case's label instead of its ID: rejected ("default is not a case ID").
- An integer range whose default is not on a step: rejected.
- A parameter that the shader never reads (speed and audio reactivity drive the motion on the CPU): allowed;
  a slot the shader reads that no parameter declares: rejected.
- A scene that stores an unknown enum case or a value of the wrong kind for a material parameter: the
  inspector shows the default for that control (it never crashes), as MOD-001 stores refuse such values.
- Labels at accessibility text sizes: each control stays one accessible element with label and value.

## Requirements *(mandatory)*

### Functional Requirements

- **SHD-003-R1**: Every bundled shader variant (each SHD-001 material) MUST declare its parameters in one
  data-only metadata document authored next to its shader: schema version, variant ID, display name,
  summary and an ordered parameter list (ID, label, kind `float`/`int`/`bool`/`enum`/`color`, unit,
  minimum, maximum, step, default, enum cases with ID and label, uniform slot). No other content is
  allowed.
- **SHD-003-R2**: The reader MUST reject unknown keys at every level, missing required keys, wrong value
  types, unsupported schema versions, unknown kinds and units, and keys that do not apply to the kind
  (for example `cases` on a float), each with a typed error naming the document, the parameter position
  or ID, and the key.
- **SHD-003-R3**: Validation MUST reject: malformed or duplicate parameter IDs; malformed or duplicate
  enum case IDs; labels empty or longer than 64 characters; non-finite numbers; minimum not below maximum;
  defaults outside the range or (integers) off a step; steps not positive or larger than the range; enums
  with fewer than 2 or more than 16 cases or a default that is not a case ID; colors without exactly four
  components in 0…1; more than eight parameters; a slot that is not the parameter's position; a material
  without its `speed` and `audioReactivity` parameters.
- **SHD-003-R4**: Validation against the shader MUST reject a document when the variant's fragment
  function reads a slot no parameter declares, reads a color's slot as a single component, or reads a
  non-color slot as a vector. This check MUST run in the unit tests and when a material layer is prepared
  (a failing layer reports itself unavailable instead of drawing).
- **SHD-003-R5**: The catalog MUST build every material's MOD-001 descriptors from its validated metadata:
  IDs `material.<variant>.<parameter>`, group = the material, float → continuous (step hint, modulatable
  by default), int → integer (manual), bool → boolean (manual), enum → enumeration (manual), color →
  color (manual), all with external control allowed. The SHD-001 IDs, ranges, defaults and units MUST be
  unchanged.
- **SHD-003-R6**: Gradient Field MUST gain the enum parameter Shape (`material.gradient.shape`; cases
  `linear` "Linear" and `radial` "Radial"; default `linear`). Linear MUST draw exactly the SHD-001 picture;
  Radial MUST blend the two colors by distance from the centre with a boundary that moves at most one cycle
  per unit of phase.
- **SHD-003-R7**: A generic control builder MUST turn a validated variant and the current values into an
  ordered list of controls, one per parameter: `slider` (float), `stepper` (int), `picker` (enum, with its
  cases in order), `toggle` (bool), `color` (color); each with the parameter ID, label, range and step
  (numbers), unit, default and current value (falling back to the default when the stored value is
  missing, of the wrong kind or an unknown case). No code may name a particular shader or parameter.
- **SHD-003-R8**: The layer inspector MUST show a "Material settings" section for a material layer with
  the builder's controls, each with an accessibility label (the parameter's label), value (the formatted
  value, UIX-003's spoken text) and identifier `materialControl.<parameter ID>`. While the version does
  not draw material layers the controls MUST be disabled and the row's read-only reason shown.
- **SHD-003-R9**: The metadata MUST stay data: no field is evaluated, compiled, loaded or used as a path;
  the shader source stays the module constant reviewed under SHD-011 (`check_compliance.py`).

### Key Entities

- **Shader parameter metadata document**: one variant's declarative parameter list (R1).
- **Shader parameter spec**: one validated parameter: ID, label, kind with range/step/default/cases, unit,
  slot.
- **Validated shader metadata**: a document that passed R2-R3 (and R4 where the shader is known); the only
  input of the descriptor mapping and the control builder.
- **Shader slot usage**: the slots one fragment function reads and how (vector or one component).
- **Shader parameter control**: one generated inspector control (R7).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SHD-003-S1**: All five bundled documents validate, and the registry built from them has 29 parameters
  whose values equal SHD-001's documented table plus Shape.
- **SHD-003-S2**: Each of at least 12 classes of invalid metadata (R2-R4) is rejected with its own error
  case, and the error text names the parameter and key.
- **SHD-003-S3**: For every material, the inspector's control list equals its metadata on kind, label,
  range, step, unit, enum options and order (100% of 29 parameters), and each accessibility value is the
  formatted current value.
- **SHD-003-S4**: On the GPU, setting Shape to Radial changes the next frame (the Radial signature matches
  its golden within 0.02 per channel and differs from Linear's), and Linear still matches SHD-001's golden.
- **SHD-003-S5**: The app shows the generated controls for the seeded Plasma layer (UI test under 30 s).
- **SHD-003-S6**: Unit tests for this feature run in under 10 s each; the Compositor package suite stays
  under one minute.

## Assumptions

- The only bundled shader variants with user-facing parameters today are the five SHD-001 materials;
  SHD-004 (variant switching) will reuse the same metadata for its variants.
- Material layers are not drawn by the app in this version (CMP-015), so live editing and its GPU effect
  are proven in the package (GPU snapshot), not in the app.
- No new UserDefaults keys and no new scene fields are needed (the new parameter is an optional scene
  parameter with a default).
- Device verification (one look at the inspector on D1) is a `{device}` task left open.
