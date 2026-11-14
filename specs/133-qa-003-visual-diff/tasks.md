# Tasks: QA-003 Visual Diff Tolerances

**Input**: Design documents from `specs/133-qa-003-visual-diff/` (spec, plan, research, data-model,
contracts/image-diff.md, quickstart)

**Tests**: requested by the spec (acceptance pair, boundaries, determinism, goldens still pass).

All paths are relative to `Packages/RenderGoldens/` unless they start with `specs/` or `docs/`.

## Phase 1: Setup

- [ ] QA-003-T01 Confirm the baseline: run `swift test --package-path Packages/RenderGoldens` on the host and record the pass count before any change (QA-003-S4 baseline)

## Phase 2: Foundational

- [ ] QA-003-T02 Add `ImageDiffTolerance` (fields per data-model: `channelThreshold` "0-255 (clamped)", `allowedFraction` "≥ 0", `maxExceedingPixels` optional, `neighborhoodRadius` "≥ 0 (clamped 0-8)", `maxClusterPixels` optional, `minimumSSIM` optional), presets `exact`, `qa002`, `golden`, `allowedPixels(total:)`, `ImageDiffBoundingBox`, `ImageDiffRule` and `ImageDiffReport` with `summary` (contract I2) in `Sources/GoldenImages/ImageDiff.swift`
- [ ] QA-003-T03 Implement `ImageDiff.compare(expected:actual:tolerance:)`: size check, per-pixel colour rule, bidirectional neighbourhood forgiveness, 8-connected clusters of unmatched pixels (iterative, no recursion), bounding box, rule evaluation (contract I1) in `Sources/GoldenImages/ImageDiff.swift`
- [ ] QA-003-T04 [P] Implement luma SSIM (8 × 8 windows, stride 4, nil below 8 × 8; research D4) in `Sources/GoldenImages/ImageDiffSSIM.swift`

## Phase 3: User Story 1 — Noise passes, geometry regressions fail (P1) 🎯 MVP

**Goal**: the acceptance. **Independent test**: `ImageDiffAcceptanceTests` alone.

- [ ] QA-003-T05 [P] [US1] Add seeded fixtures (SplitMix64 generator, gradient + rectangle + circle at any size, salt-and-pepper noise spaced ≥ 2 apart, ±2 channel noise, move, scale, remove, whole-image shift) in `Tests/RenderGoldensTests/ImageDiffFixtures.swift`
- [ ] QA-003-T06 [US1] Acceptance tests: noise passes at 128 × 96 and 256 × 192 with `.golden`; rectangle moved 12 px, circle scaled 1.5×, rectangle removed each fail with `.cluster` among the failures; a one-pixel whole-image shift passes with radius 1 and fails with `.qa002` in `Tests/RenderGoldensTests/ImageDiffAcceptanceTests.swift`

## Phase 4: User Story 2 — Configurable thresholds (P1)

**Independent test**: `ImageDiffBoundaryTests`.

- [ ] QA-003-T07 [US2] Boundary tests: difference exactly at the colour tolerance passes, one above exceeds; exactly the allowed count passes, one more fails; `maxExceedingPixels` caps the fraction; cluster limit at and above; `minimumSSIM` gate; all-different image fails every applicable rule with a whole-image box; size mismatch fails with `[.size]`; determinism (same inputs twice → equal reports); `.exact` fails on any change in `Tests/RenderGoldensTests/ImageDiffBoundaryTests.swift`

## Phase 5: User Story 3 — Readable failures (P2)

- [ ] QA-003-T08 [US3] Diff image: forgiven pixels orange, unmatched red, bounding-box outline cyan over unchanged pixels; tolerance parameter default `.golden` (contract I3) in `Sources/GoldenImages/GoldenDiffImage.swift`
- [ ] QA-003-T09 [US3] Report and diff-image tests (summary names rules, box, cluster, SSIM; diff colours) in `Tests/RenderGoldensTests/ImageDiffBoundaryTests.swift`
- [ ] QA-003-T10 [US3] Artifacts use the comparison's tolerance and write the report summary in `Tests/RenderGoldensTests/GoldenArtifacts.swift`

## Phase 6: User Story 4 — QA-002 goldens on the comparator (P2)

- [ ] QA-003-T11 [US4] `GoldenTolerance` becomes `typealias GoldenTolerance = ImageDiffTolerance`; `GoldenComparison.compare` delegates to `ImageDiff` (default `.golden`) and `GoldenComparisonResult` carries `report` with a compatible initializer in `Sources/GoldenImages/GoldenComparison.swift`
- [ ] QA-003-T12 [US4] Pin QA-002's comparison tests to `.qa002` where they test that rule, and pass `.golden` explicitly in `Tests/RenderGoldensTests/GoldenRenderSuiteTests.swift` and `Tests/RenderGoldensTests/OscilloscopeGoldenTests.swift` (hash-equal still `identical`)
- [ ] QA-003-T13 [US4] Run every golden on the host and on the QA3 iOS 27.2 simulator; all pass (QA-003-S4)

## Phase 7: Polish

- [ ] QA-003-T14 [P] README: rule, presets, diff colours, how to configure in `README.md`; update ADR-0030 cross-reference if needed in `docs/adr/`
- [ ] QA-003-T15 Linux shape and type-check budget: `swift test` with the `-D*_NO_*` flags; `-warn-long-function-bodies=300 -warn-long-expression-type-checking=150` shows no warnings in the new files
- [ ] QA-003-T16 Repo checks (`check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`, `test_scripts`)
- [ ] QA-003-T17 {device} FINAL stage: run the comparator-backed goldens on a physical device once device goldens exist (QA-011); the device run reports "pending" today

## Dependencies

T01 → T02 → T03 → (T04 ∥ T05) → T06 → T07 → T08 → T09 → T10 → T11 → T12 → T13 → T14-T16. T17 is the
FINAL stage.

## Parallel examples

- T04 (SSIM) and T05 (fixtures) touch different files.
- T14 (README) can run while T13 runs.

## Implementation strategy

MVP = Phases 1-3 (comparator + acceptance). Then boundaries, report, adoption, polish.
