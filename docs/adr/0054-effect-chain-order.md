# ADR-0054: Trails and Color Are the Reorderable Output Effects; Flash Safety and the Tone Map Stay Last

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: FX-020 (`specs/142-fx-020-effect-chains`)
- **Constitution**: VI (modular boundaries), VII (no per-frame allocation), VIII (default output bit-identical),
  X (evidence-based quality); photosensitivity (FX-019, ACC-012)
- **Builds on and amends**: ADR-0047 (FX-002 tone map at output: unchanged), ADR-0050 (FX-003 grade before the tone
  map, guard measures the graded output: the grade may now also run before Trails), ADR-0051 (FX-009 Trails before
  the grade and the guard: now the default order, not the only one), ADR-0028 (SCN-001 scene document: optional
  `effects` section, no version bump), ADR-0010 (FX-001 effect contract: glow stays inside its layer)
- **Number**: 0054 (0052 and 0053 were taken by parallel features at commit time); 0015, 0016, 0025, 0026, 0031, 0045 and 0046 stay unused.

## Context

The roadmap row FX-020 asks to "save ordered filter stacks with parameters in scene documents", with the acceptance
"reorder effects and reload; rendered order and values persist". The audit found the compositor's output chain fixed in
code: composite → Trails (FX-009, only while active) → flash guard (FX-019, measures the graded, tone-mapped frame) →
output pass (FX-003/FX-004 grade, FX-002 tone map, × the guard's gain). FX-001's glow is not in that chain: it runs
inside the spectrum layers and its values are already scene parameters. Grade and Trails were global settings, not
part of scenes.

## Decision

1. **Reorderable**: Trails (`fx.trails`) and Color (`fx.grade`, the grade with hue). Default order Trails → Color
   (today's).
2. **Fixed after every reorderable effect**: the tone map (FX-002) and the flash guard (FX-019 with ACC-012's limits,
   gain applied last), in today's arrangement. They are not part of the order type, so no setting or file can move
   them; scene entries that name them (`fx.flashGuard`, `fx.toneMap`) are kept, ignored and reported.
3. **Glow stays per layer** (FX-001): moving it to the output chain would change every spectrum scene and FX-001's
   luminance model. Per-layer chains are left to a later row; unknown kinds such as `fx.bloom` in `effects` are kept.
4. **Rendering Color first**: only when Trails are active and the grade is not neutral, a `cmp_grade_pass` writes the
   graded composite into one pooled picture that Trails read; the guard and outputs then use the neutral grade block,
   so the grade runs once and the guard still measures the shown frame. Every other case runs the existing fused output
   pass, so the default order, and any order with one effect inactive, is bit-identical to before FX-020. CMP-014's
   bus never gets a graded scene (`encodeScene` skips the pass; the bus grades itself).
5. **Trails history resets** when the order changes or the Color-first pass starts or stops, so a trail never mixes
   graded and ungraded frames.
6. **Scenes** carry an optional `effects` list (`kind`, `enabled`, `parameters`, unknown fields kept), at most 16
   entries; absent means today's order and leaves the current values alone. The app writes the list only when the
   opened scene had one or the chain is not the default, so existing scenes save byte-identically.

## Consequences

- One extra full-screen pass and one pooled picture only in the Color-first, Trails-on, graded case.
- Grade and Trails values travel with scenes that carry a chain; scenes without one behave as before.
- The device GPU check of both orders is FX-020-T19 `{device}`.
