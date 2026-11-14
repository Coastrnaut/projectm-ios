# Tasks: MOD-004 Curve Mapping

**Input**: Design documents in `specs/129-mod-004-curve-mapping/` (spec.md, plan.md, research.md,
data-model.md, contracts/mapping-curve.md, quickstart.md).

**Tests**: test-first; the red run (compile failure) is recorded before the production change.
Budgets (owner rule 7): each unit test about 1-2 s or less, each package suite under 1 minute.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. Inside descriptions "T03" is short
for `MOD-004-T03`. A task is ticked only when its evidence was produced, with " — Verified <date>:
<how>" appended. Logs go to `.build/scratch/mod-004/`.

## Phase 1: Setup

- [ ] MOD-004-T01 Record the baseline: `swift test --package-path Packages/ParameterGraph` and `swift test --package-path Packages/SceneFormat` on the host (counts, failures); count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips`.

## Phase 2: Foundational

None: the curve type is User Story 2's and User Story 1's shared deliverable and is built first in Phase 3.

## Phase 3: User Story 2 - every curve stays bounded, monotonic and deterministic (P1) MVP

**Independent test**: `MappingCurveTests.testMonotonicCurveFixturesRemainBoundedAndDeterministic`.

- [ ] MOD-004-T02 [US2] Write `Packages/ParameterGraph/Tests/ParameterGraphTests/MappingCurveTests.swift`: (a) the roadmap acceptance over ≥ 20 fixtures (linear; easeIn/easeOut/easeInOut with p ∈ {1.5, 2, 3, 8}; logarithmic/exponential with k ∈ {0.01, 1, 9, 1000}; piecewise empty, one point, eight points, flat segments): 1,001 grid inputs plus 200 adjacent representable inputs after 0, around 0.5 and before 1, outputs in 0…1, non-decreasing, `apply(0) == 0`, `apply(1) == 1`, two runs bit-identical (contract K2, K3); (b) edge inputs −1, −0, 2, NaN, −∞, +∞ (K1: non-finite → 0); (c) shape values: easeIn 2 at 0.5 = 0.25, easeOut 2 = 0.75, easeInOut 2 at 0.25 = 0.125, logarithmic 9 at 0.5 = log(5.5)/log(10), exponential is the inverse of logarithmic within 1e-12, piecewise (0.5, 0.8) at 0.25/0.5/0.75 = 0.4/0.8/0.9 (K4).
- [ ] MOD-004-T03 [US2] Record T02's red run; implement `Packages/ParameterGraph/Sources/ParameterGraph/MappingCurve.swift` (`MappingCurve`, `CurvePoint`) per research MOD-004-D1 and contract K1-K4, maths in typed steps, no allocation in `apply`. Evidence: T02 passes on the host.

## Phase 4: User Story 3 - invalid custom curves never reach a parameter (P1)

**Independent test**: `MappingCurveTests.testInvalidPiecewiseCurvesAreReportedAndStillSafe`, `CurvedBindingTests.testInvalidCurveIsRefused`.

- [ ] MOD-004-T04 [US3] Add to `MappingCurveTests.swift`: validation (K5) of valid curves (nil problem) and of ≥ 7 invalid piecewise fixtures (unsorted x, repeated x, x = 0, x = 1, x < 0, y > 1, y decreasing, NaN coordinate, 9 points) and invalid parameters ("exponent 1 < p ≤ 8": p = 1, 0.5, 9, NaN; "strength 0 < k ≤ 1000": 0, −1, 1001, ∞); each invalid curve still passes the K2/K3 sweep. Add the text form (K6): every fixture round-trips through `textForm` / `init?(textForm:)`; malformed texts (`bezier:1`, `easeIn:`, `easeIn:x`, `piecewise:0.5`, `log:1:2`, empty) read as nil; no form contains `;` or `=`.
- [ ] MOD-004-T05 [US3] Implement validation and the text form in `MappingCurve.swift`; make T04 pass.

## Phase 5: User Story 1 - a binding can follow a curve (P1)

**Independent test**: `CurvedBindingTests` (ParameterGraph), `CurveMappingAppTests` (app, simulator).

- [ ] MOD-004-T06 [US1] Write `Packages/ParameterGraph/Tests/ParameterGraphTests/CurvedBindingTests.swift`: a band bound with `easeIn(exponent: 2)` resolves 0.25 at band 0.5 (replace), with an inverted output range and with an envelope (the curve shapes the smoothed signal); an invalid curve is refused with `.invalidCurve` and the previous binding stays; an `ExpressionMapping` with a curve maps through it (K7).
- [ ] MOD-004-T07 [US1] Add `curve` to `AudioFeatureBinding` and `invalidCurve` to `AudioFeatureBindingError` (`Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureBinding.swift`); validate it in `AudioFeatureModulator.validate` after the envelope and resolve `mapping.interpolate(curve.apply(signal))` in `effective` (`AudioFeatureModulator.swift`); add `curve` to `ExpressionMapping` (`Packages/ParameterGraph/Sources/ParameterExpression/ExpressionMapping.swift`). Evidence: T06 passes; whole ParameterGraph suite passes.
- [ ] MOD-004-T08 [US1] Write `Apps/projectM-iOS/Tests/CurveMappingAppTests.swift`: band 0 bound to the glow intensity with `easeIn(exponent: 2)` drives `effectiveGlow.intensity` to 0.25 at band 0.5 (as `testKickBindsAndDrivesTheGlow`); with ACC-012's Reduced clamp applied and the band at 1 the intensity is capped at 0.5 (MOD-004-R11). Run on a private iOS 27.2 simulator, then the whole `projectM-iOSTests` bundle.

## Phase 6: User Story 4 - existing bindings and scenes behave exactly as before (P1)

**Independent test**: `CurvedBindingTests.testLinearCurveIsBitIdentical`, `SceneCurveTests`, QA-004 meta-test.

- [ ] MOD-004-T09 [US4] Add to `CurvedBindingTests.swift`: over 10,001 signals plus −0, the edge values and several output ranges (opposite-sign, same-sign, inverted, constant), `interpolate(MappingCurve.linear.apply(s))` is bit-identical to `interpolate(s)`, and a default binding resolves bit-identically to one with an explicit `.linear` (MOD-004-R7, research D4).
- [ ] MOD-004-T10 [US4] Write `Packages/SceneFormat/Tests/SceneFormatTests/SceneCurveTests.swift`: every curve kind survives encode → decode and restore (applied with the same curve); a linear binding writes no `curve` key; an unknown kind (`bezier`), a non-object curve and a missing parameter are rejected with `unsupportedCurve`, kept verbatim and re-encoded unchanged; an invalid piecewise curve is rejected with `invalidBinding`; unknown keys inside a readable curve give `droppedField`.
- [ ] MOD-004-T11 [US4] Implement scene storage: `SceneBinding.curve` (`SceneDocument.swift`, incl. `audioFeatureBinding` and `init(_ binding:)`), encoding (`SceneEncoding.swift`), decoding into `curve` or verbatim into `extra` (`SceneDecoding.swift`), the `unsupportedCurve` warning (`SceneIssue.swift`, `SceneRepair.swift` mapping group) and the rejection in `SceneModulationRestore.swift`; update contract C5 and the binding fields in `specs/059-scn-001-versioned-scene-format/contracts/scene-document.md`. Evidence: T10 and the whole SceneFormat suite (QA-004 meta-test included) pass.

## Phase 7: Polish

- [ ] MOD-004-T12 Linux shape: build and test ParameterGraph and SceneFormat as CI's Linux job does (or record that only the host ran); the six repository checks (`check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `check_status_events.py`, `test_scripts.py`); PosterBoard count after the simulator run; delete the private simulator.
- [ ] MOD-004-T13 Write `docs/test-reports/curve-mapping.md` (commands, counts, durations, decisions, what was not verified) and set the spec's status.

## Dependencies

T01 → T02 → T03 → T04 → T05 → T06 → T07 → T08; T09 after T07; T10 → T11 after T03 (needs the type);
T12, T13 last. US2 is the MVP (the curve type and acceptance).

## Parallel examples

- T08 (app test, simulator) and T10/T11 (SceneFormat) touch different packages and can run side by side once T07 is in.

## Implementation strategy

Curve type and acceptance first (US2), then validation (US3), the binding pipeline (US1), then
persistence and regression (US4). Commit after each phase.
