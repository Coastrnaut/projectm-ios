# Tasks: VIS-013 Noise Field

**Input**: `specs/252-vis-013-noise-field/` (spec, plan, research, data-model, contracts/noise-field.md)

## Phase 1: Shared noise (VIS-013-R2)

- [X] VIS-013-T01 Move SHD-006's CPU noise core to `Packages/VisualGenerators/Sources/VisualGenerators/SeededNoise.swift` with `SeededNoiseShader.functions`; make `NoiseTextureReference` call it (VIS-013-D1). — Verified 2026-11-14: swift test ProceduralMaterialsTests 66 passed (MaterialNoiseTests digests unchanged)
- [X] VIS-013-T02 [P] `SeededNoiseTests` (VisualGenerators): hash and fBm values pinned, seed changes values, Linux shape. — Verified 2026-11-14: swift test --filter SeededNoise (4 passed, host and -DVISUAL_NO_METAL shape)
- [X] VIS-013-T03 [P] `SharedNoiseSourceTests` (ProceduralMaterialsTests): the material literal contains `SeededNoiseShader.functions`; `MaterialNoiseTests` digests and `NoiseTextureReferenceTests` still pass. — Verified 2026-11-14: swift test --filter ProceduralMaterialsTests (66 passed incl. SharedNoiseSourceTests, MaterialNoiseTests)

## Phase 2: User Story 1 + 2 - the field (VIS-013-R1, R3, R5-R8)

- [X] VIS-013-T04 `NoiseFieldConfiguration` and `NoiseFieldDrive` (pure Swift) per data-model.md. — Verified 2026-11-14: NoiseFieldDriveTests 5 passed (host and Linux shape)
- [X] VIS-013-T05 `NoiseFieldFlashAreas` (8 × 8 samples → 17 areas, preallocated). — Verified 2026-11-14: NoiseFieldFlashTests 2 passed
- [X] VIS-013-T06 `NoiseFieldGenerator` (Metal fragment pass through `NativePipelineArchive`). — Verified 2026-11-14: NoiseFieldRenderTests 3 passed on the host GPU
- [X] VIS-013-T07 [P] `NoiseFieldDriveTests`: silence and full bands settle to S2's values, brightness ≤ 0.8, smoothing on frame time, drift bounded and never backwards, Reduce Motion halves drift and band warp, non-finite bands. — Verified 2026-11-14: NoiseFieldDriveTests 5 passed
- [X] VIS-013-T08 [P] `NoiseFieldFlashTests`: bursts alternating with silence stay within the transition budget in all 17 areas, Reduce flashing on and off (S3). — Verified 2026-11-14: NoiseFieldFlashTests (worst 1 transition per window, limits 4/6)
- [X] VIS-013-T09 `NoiseFieldRenderTests` (GPU): same seed/settings/clock/fixture bands twice → identical bytes; per-GPU digest; different seed differs in > 10 % of pixels; GPU vs CPU mirror within 0.02 at sample points; more octaves → more high-frequency energy (S1, S4). — Verified 2026-11-14: NoiseFieldRenderTests 3 passed; digest recorded for Apple M5 Max
- [ ] VIS-013-T10 `NoiseFieldGoldenTests` + goldens (macOS host, iOS Simulator) (S5).

## Phase 3: User Story 3 - the app (VIS-013-R4, R9, R11, R12)

- [ ] VIS-013-T11 Visual choice `noiseField`, three keys, Settings section (Frequency, Octaves, Seed + New Seed), host style and generator, accessibility value, scene capture as no layer; keys in `ALLOWED_KEYS`, FILE-005 policy, UI-test reset.
- [ ] VIS-013-T12 [P] `NoiseFieldAppTests` (settings persist and fall back, style mapping, value text, New Seed deterministic, keys in lists) and existing list tests updated; `LibraryBackupAppTests` passes.
- [ ] VIS-013-T13 [P] `NoiseFieldUITests`: choose Noise Field, controls offered, Bars not, choose High, value "High frequency…", source started once (< 30 s).

## Phase 4: Polish

- [ ] VIS-013-T14 Full touched package suites, Linux shape, repo checks, privacy manifest and network symbol scans, type-check budget.
- [ ] VIS-013-T15 {device} On D1 with music, Noise Field holds the display's frame rate on the PERF-001/007 overlay.

## Dependencies

T01 → T02, T03, T04-T06; T04-T06 → T07-T10; T06 → T11 → T12, T13; all → T14. T15 needs a device.

## Analyze notes (speckit-analyze, 2026-11-14)

- Coverage: every R1-R13 maps to a task (R2 T01-T03; R1, R3, R5-R8 T04-T09; R10 T10; R4, R9, R11, R12 T11-T13;
  R13 T03, T14). S1-S7 each have a test task. No constitution conflict.
- Fix applied: the unknown-GPU path of T09 prints the digest and skips only the digest comparison (the
  twice-rendered equality and seed checks still run), matching spec Clarifications Q5.
- Fix applied: edge case "time going backwards" and "frame gap > 1 s" are asserted in T07.
