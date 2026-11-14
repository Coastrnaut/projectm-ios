# Research: FX-020 Effect Chain Presets

All decisions taken by Claude under owner rules 4 and 9 (2026-11-14).

## FX-020-D1: Which effects are reorderable

- **Decision**: Trails (FX-009) and Color (FX-003 grade with FX-004 hue, one effect). Fixed after them:
  the flash guard (FX-019, ACC-012 limits) and the tone map (FX-002). Glow (FX-001) is not in the output
  chain.
- **Rationale**: These are the only effects that act on the finished picture. The guard must measure the
  frame as shown and may only darken (ADR-0049, FX-019); ADR-0047 puts the tone map at output, where the
  display range is decided. Glow runs inside the spectrum layers on one layer's picture, before the
  composite; its values are already scene parameters (`effect.bloom.*`).
- **Alternatives**: moving glow to the output chain (changes every spectrum scene's look and FX-001's
  luminance model, rejected); letting the tone map move (values above 1 would reach grading and trails in
  undefined ways, rejected).

## FX-020-D2: How Color-first is rendered

- **Decision**: When Color is ordered first, Trails are active and the grade is not neutral, a
  `cmp_grade_pass` writes the graded composite (`cmp_grade`, no tone map) into a pooled `rgba16Float`
  picture; Trails run on it; the guard and the outputs use the neutral grade block (`flags 0`, so
  `cmp_display` = tone map only). In every other case the existing single-pass output is used.
- **Rationale**: Without Trails the two orders are the same operator, and the fused pass avoids a
  half-float round trip, so FX-020-R3 (bit-identical) holds. The guard still measures exactly the shown
  values (grade already in the frame, tone map in `cmp_display`).
- **Alternatives**: always splitting the grade into its own pass (costs a pass and changes rounding for
  every graded frame, rejected).

## FX-020-D3: Order changes reset Trails

- **Decision**: Changing the order resets the Trails history (next frame = the composite only).
- **Rationale**: The history holds graded or ungraded frames depending on the order; mixing them would
  double-grade or un-grade the trail for a second.

## FX-020-D4: Scene field

- **Decision**: Optional top-level `effects` array of `{kind, enabled, parameters}`; written only when
  non-nil; ≤ 16 entries (`tooMany`, like FX-001's `EffectChainDescription` limit); `kind` must be a
  string, `enabled` a boolean when present, `parameters` an object when present (else `malformed`).
  Unknown entry fields are kept. Kinds follow FX-001's stable dotted ids (`fx.bloom` style).
- **Rationale**: Same pattern as CMP-011 `groups` (no version bump, QA-004 matrix unchanged); absent
  stays byte-identical.

## FX-020-D5: Reading entries

- **Decision**: In document order: the first entry of each known kind sets that effect's position, flag
  and parameters; later entries of the same kind → `duplicateEffect`; fixed-stage kinds →
  `fixedEffectStage`; other kinds → `unknownEffectKind`. All are warnings, kept verbatim, ignored for
  rendering. Known kinds missing from the list keep their standard relative position after the listed ones
  and their current values. Parameters: missing → default; not a finite number → default with
  `valueClamped`; out of range → clamped with `valueClamped`; unknown parameter names are kept.
- **Rationale**: Nothing in a file can refuse a scene over an effect, and nothing can move safety.

## FX-020-D6: Writing entries

- **Decision**: Walk the stored list (if any); each known entry (first of its kind) is replaced by the
  live entry for its kind in live order; every other entry stays at its index; known kinds the list did
  not have are appended in live order. Live entries write all parameters (finite numbers) and `enabled`;
  unknown parameter names of a replaced entry are kept.
- **Rationale**: Unknown and future entries survive load → save at their position (FX-020-R6, R7).

## FX-020-D7: When the app writes the list

- **Decision**: When the opened scene had a list, or when the live chain is not the default (order not
  standard, Trails on, Color off, or Color not neutral).
- **Rationale**: Existing and default scenes save exactly as before (FX-020-R4); scenes that were never
  given effects do not suddenly carry the global grade.

## FX-020-D8: Presets

- **Decision**: One UserDefaults value `settings.effectChain.presets`: canonical JSON
  `{"version":1,"presets":[{"name":…,"effects":[…]}]}` using the scene entry format; ≤ 32 presets; names
  trimmed, 1…60 characters; saving an existing name (case-insensitive) replaces it in place; unreadable
  data reads as no presets and is not overwritten until the user saves. Included in FILE-005 backups and
  FILE-011 erase via `LibrarySettingsPolicy.includedKeys`.
- **Rationale**: Small, local, already covered by the settings backup and erase machinery; the scene entry
  format keeps unknown kinds in presets too.

## FX-020-D9: Color on/off

- **Decision**: `settings.colorGrade.enabled` (absent → on); off makes `effectiveGrade` neutral, keeping
  the values. ACC-012 caps still apply on top.

## FX-020-D10: UI

- **Decision**: Settings row "Effect order" (value: "Trails → Color") opening `EffectChainView`: a List of
  two rows (name + Toggle) with `.onMove` and an `EditButton`, each row with accessibility actions "Move
  up"/"Move down"; footer "Always last: Flash safety, then Tone map."; a Presets section with "Save
  current as preset…" (alert with a text field), one row per preset (tap applies; swipe deletes).
  Announcements through the existing announcer lane used by Settings.
