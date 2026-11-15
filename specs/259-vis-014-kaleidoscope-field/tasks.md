# Tasks: VIS-014 Kaleidoscope Field

**Input**: `specs/259-vis-014-kaleidoscope-field/` (spec, plan, research, data-model, contracts/kaleidoscope.md)

## Phase 1: Shared fold (VIS-014-R3, R4, R6)

- [ ] VIS-014-T01 `KaleidoscopeFold` (CPU mirror, constants) and `KaleidoscopeFoldShader.function` in `Packages/VisualGenerators/Sources/VisualGenerators/KaleidoscopeFold.swift` (research D2).
- [ ] VIS-014-T02 [P] `KaleidoscopeFoldTests`: identity below 2 wedges; continuity across every boundary and axis and the ±π wrap for N = 2, 5, 6, 24 (K2); rotation and mirror invariance (K3); Linux shape.

## Phase 2: User Story 1 + 2 - the folded field (VIS-014-R1, R2, R4-R8)

- [ ] VIS-014-T03 `NoiseFieldConfiguration.wedges` and `kaleidoscope(wedges:…)`; `NoiseFieldDrive` spin and rotation (research D3).
- [ ] VIS-014-T04 `NoiseFieldFlashAreas` folds its sample points; `NoiseFieldGenerator` appends the fold function and writes wedges and rotation into the former padding.
- [ ] VIS-014-T05 [P] `KaleidoscopeDriveFlashTests`: silence and full bass settle to 0.1 and 0.4 rad/s, never above 0.4, half with Reduce Motion; rotation never backwards and ≤ 1 s per frame; no rotation when unfolded; bursts alternating with silence within the envelope in all 17 areas with Reduce flashing on and off (S3, S4).
- [ ] VIS-014-T06 `KaleidoscopeRenderTests` (GPU): N-fold rotation and mirror symmetry for N = 5 and 6 and the other count's rotation rejected (S1); seam test across every boundary and axis, square and non-square (S2); GPU agrees with the CPU fold; Noise Field digests unchanged (K4).
- [ ] VIS-014-T07 `KaleidoscopeGoldenTests` + goldens (macOS host, iOS Simulator) (S5).

## Phase 3: User Story 3 - the app (VIS-014-R9, R11, R12)

- [ ] VIS-014-T08 Visual choice `kaleidoscope`, key `settings.kaleidoscope.wedges`, Wedges stepper, host style and in-place update, accessibility value, scene capture as no layer; key in `ALLOWED_KEYS`, FILE-005 policy, UI-test reset.
- [ ] VIS-014-T09 [P] `KaleidoscopeAppTests` (setting persists and falls back, style mapping, value text, in-place wedge change, switching to Noise Field turns the fold off) and existing list tests updated; `LibraryBackupAppTests` passes.
- [ ] VIS-014-T10 [P] `KaleidoscopeUITests`: choose Kaleidoscope, Wedges offered, Bars not, raise Wedges, value "7 wedges…", source started once (< 30 s).

## Phase 4: Polish

- [ ] VIS-014-T11 Touched package suites, Linux shape, repo checks, privacy manifest and network symbol scans, type-check budget.
- [ ] VIS-014-T12 {device} On D1 with music, Kaleidoscope holds the display's frame rate on the PERF-001/007 overlay and shows no seam at 2, 7 and 24 wedges.

## Dependencies

T01 → T02, T03, T04; T03-T04 → T05-T07; T04 → T08 → T09, T10; all → T11. T12 needs a device.

## Analyze notes (speckit-analyze, 2026-11-14)

- Coverage: every R1-R13 maps to a task (R3, R4, R6 T01-T02, T06; R1, R2, R5, R7, R8 T03-T06; R10 T07; R9, R11,
  R12 T08-T10; R13 T06 (K4 digests), T11). S1-S7 each have a test task. No constitution conflict.
- Fix applied: the non-square edge case is covered by the golden (256 × 192) and the seam test's non-square run
  in T06 (the fold centre is the frame centre, the shorter side sets the scale).
- Fix applied: T11 also runs the Noise Field goldens and render tests, since S5 requires them unchanged.
