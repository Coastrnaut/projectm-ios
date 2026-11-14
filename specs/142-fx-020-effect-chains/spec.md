# Feature Specification: FX-020 Effect Chain Presets

**Feature Branch**: `feature/fx-020` (spec directory `142-fx-020-effect-chains`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement FX-020 (Effect chain presets) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Save ordered filter stacks with parameters in scene documents."
Acceptance, verbatim: "Reorder effects and reload; rendered order and values persist." Priority P1, effort M,
depends on FX-001 (integrated). Verification: snapshot, shader unit and device GPU (last stage)."

Identifiers in this feature carry the roadmap ID so they never collide with other features: requirements
are `FX-020-R1…`, success criteria `FX-020-S1…`, research decisions `FX-020-D1…`, tasks `FX-020-T01…`.
Other features are cited by their own IDs: FX-001 (glow/bloom), FX-002 (tone map), FX-003/FX-004 (colour
grade, hue), FX-009 (Trails), FX-019 (flash guard), ACC-012 (sensory safety caps), SCN-001 (scene
document), SCN-002 (autosave), SCN-010 (undo), SCN-012 (repair report), QA-003 (image diff), QA-004
(migration matrix), FILE-005/FILE-011 (backup and erase of settings).

## Baseline: what exists today (audit of 2026-11-14, branch point `09621948`)

The row's gap status is "Gap candidate". The audit confirms a gap: the order of the output effects is
fixed in code and no scene stores an effect.

| Area | Today |
|---|---|
| Compositor output chain | `Compositor.encodeFrame` (Packages/Compositor): layers → composite → FX-009 Trails pass (`cmp_trails`, only while active) → FX-019 composite flash guard (measures the graded, tone-mapped frame) → output pass `cmp_output` = FX-003/FX-004 grade (`cmp_grade`), FX-002 tone map (`cmp_tone_map`), × the guard's gain. Order is fixed: Trails, then grade, then tone map, with the guard's gain applied last. ADR-0047 (tone map at output), ADR-0050 (grade before tone map, guard measures graded output), ADR-0051 (Trails replace the composite for the guard and every output). |
| FX-001 glow | Not in the compositor output chain. `BloomEffect` runs inside the spectrum layers (`SpectrumLayerSource`, `NativeSpectrumHost`) through FX-001's `EffectChain` (VisualGenerators). Its four values are MOD-001 parameters (`effect.bloom.*`) already saved in every scene's `parameters`. FX-001 also defined `EffectChainDescription` (ids such as `fx.bloom`, unknown ids kept, at most 16 entries) as the intended format for this row. |
| Grade and Trails in the app | Global settings, not part of scenes (`ColorGradeSetting`, keys `settings.colorGrade.*`; `MotionFeedbackSetting`, keys `settings.feedback.*`). The grade has no on/off switch (neutral = off). ACC-012 caps both (`effectiveGrade`, `MotionFeedback.limited(by:)`). They reach only the compositor-backed visuals (Camera, Photo, Video, Text). |
| Scene document | SCN-001 version 1. Optional top-level sections are added without a version bump (CMP-011 `groups`, written only when not empty, so older scenes stay byte-identical); unknown top-level fields are kept verbatim in `extra`. QA-004's meta-test checks the decode error and migration tables, not the fields. |
| Repair report | SCN-012 `SceneRepairReport` classifies every `SceneIssue.Code` (exhaustive switch). |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Which effects can the user reorder? → A: The two output effects that run on the finished picture before safety: Trails (FX-009) and Color (the FX-003 grade with FX-004 hue, one effect). The flash guard (FX-019, with ACC-012's limits) and the tone map (FX-002) are fixed stages that always run after every reorderable effect, in today's order. Glow (FX-001) stays inside the spectrum layers, where it is already saved with the scene's parameters; it is not part of the output chain (it acts on one layer, not on the finished picture). Recorded in an ADR.
- Q: When does the order change the picture? → A: Only when both Trails and Color are active. With either of them off the two orders give the same picture, and the app renders exactly as today (bit for bit).
- Q: What does a scene store? → A: An optional `effects` list: one entry per effect with its kind, an on/off flag and its parameters, in the order applied. Absent means today's order with no change to the current Trails and Color values (as today, where scenes do not touch them). The app writes the list only when the chain is not the default (Trails off, Color neutral and on, default order) or when the scene it opened had one, so existing and default scenes save exactly as before.
- Q: What happens to entries this version cannot run? → A: Kinds it does not know (including `fx.bloom` written by a later version, or a misspelt kind) are kept verbatim at their position and reported by the repair report; entries naming a fixed stage (flash guard, tone map) are kept but never move safety or the tone map, and are reported; a second entry of the same kind is kept but ignored and reported. None of these refuse the scene.
- Q: What is a chain preset and where is it kept? → A: A named copy of the chain (order, on/off flags, parameters) saved on this device in the app's settings. Applying it sets the current chain. Presets are included in library backups (FILE-005) and removed by "Erase local data" (FILE-011) with the other settings. At most 32 presets; saving a name that exists replaces it.
- Q: Does Color get an on/off switch? → A: Yes, so the chain can turn an effect off without losing its values. Off means neutral output; it is on by default, so nothing changes for existing users.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - My effect order is part of the scene (Priority: P1) — MVP

A VJ uses Trails and a strong Color grade on a photo scene. Applying Color before Trails gives softer,
tinted trails; after Trails, the trails take the grade's contrast. They choose Color first, the scene
saves, and when they reopen it the next day the picture is drawn in the same order with the same values.

**Why this priority**: It is the row's acceptance.

**Independent Test**: Render a fixture with the chain Trails → Color, reorder to Color → Trails, save the
scene, read it back from disk and render again: the order and values persist, the picture equals
rendering Color → Trails directly, and it differs from Trails → Color.

**Acceptance Scenarios**:

1. **Given** a chain Trails → Color with distinct values, **When** it is reordered to Color → Trails, saved to a file and read back, **Then** the restored chain lists Color then Trails with the same values and flags.
2. **Given** that restored chain, **When** the same frames are rendered, **Then** the output equals Color → Trails rendered directly (exactly) and differs from Trails → Color.
3. **Given** the app with Trails on and a non-neutral Color, **When** the user moves Color above Trails in Settings › Effect order, **Then** the order is kept after the scene is saved and restored.

---

### User Story 2 - Safety and the tone map always come last (Priority: P1)

Whatever a scene file says, the flash guard and the tone map run after every reorderable effect, so a
file cannot make the picture brighter or flashier than safety allows.

**Why this priority**: Constitution and FX-019/ACC-012 safety.

**Independent Test**: Decode a scene whose `effects` list puts the flash guard and tone map first; the
live order has only Trails and Color, and the rendered output equals the same chain without those entries.

**Acceptance Scenarios**:

1. **Given** an `effects` list `[flash guard, tone map, Color, Trails]`, **When** the scene loads, **Then** Color runs before Trails, safety and the tone map run last, and the report lists the two fixed entries.
2. **Given** any order, **When** a frame is drawn, **Then** the flash guard measures the frame exactly as shown.

---

### User Story 3 - Old, default and future scenes keep working (Priority: P1)

Scenes without an effect list open and render exactly as before. A scene from a newer version with an
effect this version does not know opens; the unknown entry is reported and saved back unchanged.

**Why this priority**: Scenes are stored, shared and backed up; they must not lose data.

**Independent Test**: Encode and decode scenes with and without `effects`; render with the default chain
and with no chain set and compare bit for bit.

**Acceptance Scenarios**:

1. **Given** a scene without `effects`, **When** it is decoded and re-encoded, **Then** the bytes are unchanged and the renderer uses today's order.
2. **Given** an entry `{"kind": "fx.kaleidoscope", …}` between Color and Trails, **When** the scene is opened and saved again, **Then** the entry is written back verbatim at the same position and the repair report lists it as unknown content.

---

### User Story 4 - I keep named chains (Priority: P2)

The VJ saves their chain as "Soft trails" and later applies it to another scene with one tap.

**Why this priority**: The "presets" half of the row; useful but not the acceptance.

**Independent Test**: Save a chain under a name, change the chain, apply the preset: the chain equals the
saved one; the preset list survives encoding and decoding.

**Acceptance Scenarios**:

1. **Given** a chain, **When** it is saved as "Soft trails" and later applied, **Then** the order, flags and values are those saved.
2. **Given** a preset named "Soft trails", **When** another chain is saved under the same name, **Then** it replaces the old one.

### Edge Cases

- Both orders are equal when Trails or Color is off: the app then renders the default single-pass path.
- An `effects` list that is empty: today's order, nothing reported.
- A known entry without parameters: its defaults (Color neutral; Trails 0.20 s); missing `enabled` means on.
- Parameter values out of range or not numbers: clamped or replaced by the default, and reported as adjusted; NaN is not writable JSON.
- More than 16 entries: the scene is refused like any other over-limit list (`tooMany`).
- A preset applied while the sensory safety profile caps Trails or gain: the caps still apply (the preset sets the user values).
- Reordering resets the Trails history (the next frame starts clean), as any change of what the history holds.

## Requirements *(mandatory)*

### Functional Requirements

- **FX-020-R1**: The reorderable output effects MUST be exactly Trails (`fx.trails`) and Color (`fx.grade`); the default order MUST be Trails, then Color (today's).
- **FX-020-R2**: The renderer MUST apply the reorderable effects in the chosen order; the flash guard and the tone map MUST always run after them, and the guard MUST measure the frame as shown.
- **FX-020-R3**: With the default order, or whenever Trails or Color is inactive, the output MUST be bit-identical to the renderer before this feature.
- **FX-020-R4**: A scene document MUST be able to carry an optional `effects` list of entries `{kind, enabled, parameters}` in application order, without a format version change; absent MUST encode and decode byte-identically to today.
- **FX-020-R5**: Known entries MUST restore their order, flag and parameters (Color: temperature, lift, gamma, gain, saturation, hue; Trails: halfLife), clamped to their ranges with an adjustment warning.
- **FX-020-R6**: Unknown kinds, fixed-stage kinds and repeated kinds MUST be kept verbatim at their position, never change the live order or safety, and be reported by the repair report as warnings.
- **FX-020-R7**: Saving MUST write the live order and values into the known entries while keeping every other entry at its position.
- **FX-020-R8**: The app MUST store the order and Color's on/off switch as settings, apply them to every compositor-backed visual (Camera, Photo, Video, Text) from the next frame, and include them in scenes per the Clarifications rule; opening a scene with a list MUST apply it, without one MUST restore the default order.
- **FX-020-R9**: Settings MUST offer an Effect order screen listing Trails and Color with on/off switches, reordering (Edit, drag, and VoiceOver "Move up"/"Move down" actions), the fixed stages shown as not movable, and chain presets (save with a name, apply, delete).
- **FX-020-R10**: Chain presets MUST be stored locally (at most 32, names at most 60 characters, a repeated name replaces), included in settings backups and removed by "Erase local data".
- **FX-020-R11**: The scene model, the preset format and the order model MUST build and pass their tests on Linux; repository checks MUST pass. No networking, permission or usage string.
- **FX-020-R12**: A UI test MUST reorder the effects in under 30 s.

### Key Entities

- **Effect chain entry**: kind (text), enabled (bool), parameters (name → number), unknown fields (kept).
- **Effect chain**: ordered entries (at most 16).
- **Output effect order**: the live order of the reorderable effects.
- **Chain preset**: name plus an effect chain.

## Privacy review *(Constitution, Privacy)*

- Presets and the order are effect settings on this device; no personal data, no network, no new permission.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FX-020-S1**: Reorder → save to a file → reload → render equals the reordered chain rendered directly (exact) and differs from the original order (the row's acceptance).
- **FX-020-S2**: With the default order or with Trails or Color inactive, the output is bit-identical to the renderer with no chain set.
- **FX-020-S3**: A scene listing safety or the tone map first renders exactly as the same chain without them.
- **FX-020-S4**: Scenes without `effects` re-encode byte-identically; unknown entries round-trip at their position and are reported.
- **FX-020-S5**: Save and apply of a preset round-trips order, flags and values.
- **FX-020-S6**: A UI test reorders the effects in under 30 s; all repository checks and touched package tests pass.

## Assumptions

- Per-layer filter chains (glow on other layers, several glows) are a later row; the entry format leaves room for them.
- Device GPU verification is the `{device}` task in the last stage; simulator results are never device evidence.
