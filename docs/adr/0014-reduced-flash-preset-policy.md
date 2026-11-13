# ADR-0014: Reduced flash preset policy

- **Status**: Accepted 2026-11-13 (decided by Claude under the owner's best-judgement rule, owner
  rule 4; feature ACC-002)
- **Date**: 2026-11-13
- **Spec**: `specs/030-acc-002-reduced-flash-preset-policy/` (research ACC-002-D1 to D7)
- **Constitution**: VI, IX, X; Privacy
- **Related**: ADR-0011 (strobe safety envelope), ADR-0007 (preset library)

## Context

FX-019 limits flashes in every rendered frame, but only after a scene is on screen and only by
dimming. Nothing told the app, before loading, that a preset is built to strobe, so Reduce
flashing did not change which scenes the app picks.

## Decisions

1. **A text screen, not a render sweep** (ACC-002-D1). Flash risk is decided from each preset's
   per-frame equations by three named rules (`toggle-driven`, `toggle-flip`, `luma-flicker`) with
   fixed thresholds (ACC-002-D2): flicker sources are `rand`, `frame % N` (N ≤ 20), and `sin`/`cos`
   of `time × K` (K ≥ 18) or of `frame`; a source inside a term scaled by a literal below 0.1
   (FX-019's transition threshold) is damped. It is a pre-load layer; FX-019 stays the guarantee.
2. **Two executions, one fixture set** (ACC-002-D7). `scripts/preset_flash_risk.py` screens the
   bundled library during the index build; `PresetLibrary.PresetFlashRisk` screens imported and
   edited presets on the device. Both must match `FlashFixtures/expected.json`, checked by the
   script tests and the package tests.
3. **The index field** (ACC-002-D6). Flagged records carry `"flash": [rule ids]`; unflagged ones
   carry nothing. The index `version` stays 1 because the field is optional and additive (this
   overrides the default of bumping the version for a schema change).
4. **The preference is Reduce flashing** (ACC-002-D5). No new setting. With it on: Next,
   Previous, Random, warm-up and the launch preset skip flagged presets; an explicit choice shows
   a "May flash" warning with Load Anyway / Cancel before anything loads; rows show a "May flash"
   mark (symbol and words). With it off: unchanged. The warning's answer is never stored.
5. **Honest limits** (ACC-002-D4). Shaders, custom shapes and waves, per-pixel and init code are
   not read; flicker through variables is not followed. Unflagged presets are never called safe.

## Consequences

- 92 of the 14,576 pack files (before de-duplication) are flagged; none of the 28 Included
  presets, so the pre-purchase experience is unchanged. In the shipped index 83 of 12,847 presets
  (0.65 %) are flagged; the screen adds about 5 s to a full index rebuild.
- Rule changes rebuild the index (the stamp hashes the classifier) and must update the fixtures.
- ACC-012 (sensory safety profile) can reuse the verdict and rule ids for finer per-user limits.
