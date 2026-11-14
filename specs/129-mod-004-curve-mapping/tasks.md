# Tasks: MOD-004 Curve Mapping

**Input**: Design documents in `specs/129-mod-004-curve-mapping/` (spec.md, plan.md, research.md,
data-model.md, contracts/mapping-curve.md, quickstart.md).

**Tests**: test-first; the red run (compile failure) is recorded before the production change.
Budgets (owner rule 7): each unit test about 1-2 s or less, each package suite under 1 minute.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. Inside descriptions "T03" is short
for `MOD-004-T03`. A task is ticked only when its evidence was produced, with " — Verified <date>:
<how>" appended. Logs go to `.build/scratch/mod-004/`.

## Phase 1: Setup

- [X] MOD-004-T01 Record the baseline: `swift test --package-path Packages/ParameterGraph` and `swift test --package-path Packages/SceneFormat` on the host (counts, failures); count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips`. — Verified 2026-11-14: at 3c373722, ParameterGraph 118 tests on the host (77 + 41, 1 skipped), 0 failures; SceneFormat 117 tests, 0 failures (2.7 s); PosterBoard reports 25 (.build/scratch/mod-004/T01-*.log).

## Phase 2: Foundational

None: the curve type is User Story 2's and User Story 1's shared deliverable and is built first in Phase 3.

## Phase 3: User Story 2 - every curve stays bounded, monotonic and deterministic (P1) MVP

**Independent test**: `MappingCurveTests.testMonotonicCurveFixturesRemainBoundedAndDeterministic`.

- [X] MOD-004-T02 [US2] Write `Packages/ParameterGraph/Tests/ParameterGraphTests/MappingCurveTests.swift`: (a) the roadmap acceptance over ≥ 20 fixtures (linear; easeIn/easeOut/easeInOut with p ∈ {1.5, 2, 3, 8}; logarithmic/exponential with k ∈ {0.01, 1, 9, 1000}; piecewise empty, one point, eight points, flat segments): 1,001 grid inputs plus 200 adjacent representable inputs after 0, around 0.5 and before 1, outputs in 0…1, non-decreasing, `apply(0) == 0`, `apply(1) == 1`, two runs bit-identical (contract K2, K3); (b) edge inputs −1, −0, 2, NaN, −∞, +∞ (K1: non-finite → 0); (c) shape values: easeIn 2 at 0.5 = 0.25, easeOut 2 = 0.75, easeInOut 2 at 0.25 = 0.125, logarithmic 9 at 0.5 = log(5.5)/log(10), exponential is the inverse of logarithmic within 1e-12, piecewise (0.5, 0.8) at 0.25/0.5/0.75 = 0.4/0.8/0.9 (K4). — Verified 2026-11-14: written before the type in MappingCurveTests.swift (with T04's tests, same file): 26 valid fixtures, grid 1,001 + 600 adjacent inputs, edge inputs, shape values.
- [X] MOD-004-T03 [US2] Record T02's red run; implement `Packages/ParameterGraph/Sources/ParameterGraph/MappingCurve.swift` (`MappingCurve`, `CurvePoint`) per research MOD-004-D1 and contract K1-K4, maths in typed steps, no allocation in `apply`, `Sendable` and `Hashable` (MOD-004-R4: usable from any thread). Evidence: T02 passes on the host. — Verified 2026-11-14: red run `cannot find type 'MappingCurve' in scope` (.build/scratch/mod-004/red-T02.log); after MappingCurve.swift the 8 MappingCurveTests pass on the host in 0.029 s (acceptance test 0.014 s; .build/scratch/mod-004/T03.log).

## Phase 4: User Story 3 - invalid custom curves never reach a parameter (P1)

**Independent test**: `MappingCurveTests.testInvalidPiecewiseCurvesAreReportedAndStillSafe`, `CurvedBindingTests.testInvalidCurveIsRefused`.

- [X] MOD-004-T04 [US3] Add to `MappingCurveTests.swift`: validation (K5) of valid curves (nil problem) and of ≥ 7 invalid piecewise fixtures (unsorted x, repeated x, x = 0, x = 1, x < 0, y > 1, y decreasing, NaN coordinate, 9 points) and invalid parameters ("exponent 1 < p ≤ 8": p = 1, 0.5, 9, NaN; "strength 0 < k ≤ 1000": 0, −1, 1001, ∞); each invalid curve still passes the K2/K3 sweep. Add the text form (K6): every fixture round-trips through `textForm` / `init?(textForm:)`; malformed texts (`bezier:1`, `easeIn:`, `easeIn:x`, `piecewise:0.5`, `log:1:2`, empty) read as nil; no form contains `;` or `=`. — Verified 2026-11-14: written with T02 before the type (same red run): 21 invalid fixtures (11 piecewise faults, 5 exponent, 5 strength), each refused and still bounded/monotonic/exact; text-form round trip and 15 malformed texts.
- [X] MOD-004-T05 [US3] Implement validation and the text form in `MappingCurve.swift`; make T04 pass. — Verified 2026-11-14: testInvalidPiecewiseCurvesAreReportedAndStillSafe, testTextFormRoundTrips, testMalformedTextReadsAsNothing pass (.build/scratch/mod-004/T03.log).

## Phase 5: User Story 1 - a binding can follow a curve (P1)

**Independent test**: `CurvedBindingTests` (ParameterGraph), `CurveMappingAppTests` (app, simulator).

- [X] MOD-004-T06 [US1] Write `Packages/ParameterGraph/Tests/ParameterGraphTests/CurvedBindingTests.swift`: a band bound with `easeIn(exponent: 2)` resolves 0.25 at band 0.5 (replace), with an inverted output range and with an envelope (the curve shapes the smoothed signal); an invalid curve is refused with `.invalidCurve` and the previous binding stays; an `ExpressionMapping` with a curve maps through it (K7). — Verified 2026-11-14: written before the change (CurvedBindingTests.swift; the ExpressionMapping case in Tests/ParameterExpressionTests/ExpressionCurveTests.swift because ParameterGraphTests does not depend on ParameterExpression); red run `extra argument 'curve' in call`, `value of type 'ExpressionMapping' has no member 'curve'` (.build/scratch/mod-004/red-T06.log).
- [X] MOD-004-T07 [US1] Add `curve` to `AudioFeatureBinding` and `invalidCurve` to `AudioFeatureBindingError` (`Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureBinding.swift`); validate it in `AudioFeatureModulator.validate` after the envelope and resolve `mapping.interpolate(curve.apply(signal))` in `effective` (`AudioFeatureModulator.swift`); add `curve` to `ExpressionMapping` (`Packages/ParameterGraph/Sources/ParameterExpression/ExpressionMapping.swift`). Evidence: T06 passes; whole ParameterGraph suite passes. — Verified 2026-11-14: after the change the 5 T06 tests and ExpressionCurveTests pass; whole ParameterGraph package 133 tests (91 + 42, 1 skipped as before), 0 failures, 0.25 s of tests (.build/scratch/mod-004/T07.log).
- [ ] MOD-004-T08 [US1] Write `Apps/projectM-iOS/Tests/CurveMappingAppTests.swift`: band 0 bound to the glow intensity with `easeIn(exponent: 2)` drives `effectiveGlow.intensity` to 0.25 at band 0.5 (as `testKickBindsAndDrivesTheGlow`); with ACC-012's Reduced clamp applied and the band at 1 the intensity is capped at 0.5 (MOD-004-R11). Run on a private iOS 27.2 simulator, then the whole `projectM-iOSTests` bundle.

## Phase 6: User Story 4 - existing bindings and scenes behave exactly as before (P1)

**Independent test**: `CurvedBindingTests.testLinearCurveIsBitIdentical`, `SceneCurveTests`, QA-004 meta-test.

- [X] MOD-004-T09 [US4] Add to `CurvedBindingTests.swift`: over 10,001 signals plus −0, the edge values and several output ranges (opposite-sign, same-sign, inverted, constant), `interpolate(MappingCurve.linear.apply(s))` is bit-identical to `interpolate(s)`, and a default binding resolves bit-identically to one with an explicit `.linear` (MOD-004-R7, research D4). — Verified 2026-11-14: testLinearCurveIsBitIdentical (7 ranges × 10,009 signals incl. −0, NaN, ±∞; 0.015 s) and testDefaultBindingResolvesLikeAnExplicitLinearOne (1,001 band levels, bit-identical to MOD-003's interpolation) pass; written with T06 (same red run).
- [X] MOD-004-T10 [US4] Write `Packages/SceneFormat/Tests/SceneFormatTests/SceneCurveTests.swift`: every curve kind survives encode → decode and restore (applied with the same curve); a linear binding writes no `curve` key; an unknown kind (`bezier`), a non-object curve and a missing parameter are rejected with `unsupportedCurve`, kept verbatim and re-encoded unchanged; an invalid piecewise curve is rejected with `invalidBinding`; unknown keys inside a readable curve give `droppedField`. — Verified 2026-11-14: SceneCurveTests.swift (7 tests) written before the change; red run `value of type 'SceneBinding' has no member 'curve'`, `type 'SceneIssue.Code' has no member 'unsupportedCurve'` (.build/scratch/mod-004/red-T10.log). Six unreadable shapes covered (unknown kind, number, missing exponent, string strength, point without y, no kind). Decision while implementing: an empty piecewise curve is written (only `.linear` is omitted) so it reads back identical.
- [X] MOD-004-T11 [US4] Implement scene storage: `SceneBinding.curve` (`SceneDocument.swift`, incl. `audioFeatureBinding` and `init(_ binding:)`), encoding (`SceneEncoding.swift`), decoding into `curve` or verbatim into `extra` (`SceneDecoding.swift`), the `unsupportedCurve` warning (`SceneIssue.swift`, `SceneRepair.swift` mapping group) and the rejection in `SceneModulationRestore.swift`; update contract C5 (new `unsupportedCurve` row, severity warning, as every per-edge code since the MOD-013 amendment) and the binding fields in `specs/059-scn-001-versioned-scene-format/contracts/scene-document.md`. Evidence: T10 and the whole SceneFormat suite (QA-004 meta-test included) pass. — Verified 2026-11-14: after the change SceneCurveTests' 7 tests pass and the whole SceneFormat package passes, 124 tests, 0 failures, 2.2 s (QA-004's SceneMigrationMatrixMetaTests 4/4 pass; no SceneDecodeError case added) (.build/scratch/mod-004/T11.log). One existing expectation updated on purpose: SceneForwardCompatibilityTests' hypothetical future binding stores `{"kind":"easeIn","power":2.0}`, which MOD-004 cannot read; it still round-trips byte for byte and now also reports `unsupportedCurve`. Contract scene-document.md: binding field and C5 row added.

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

## Analysis (speckit-analyze, 2026-11-14)

Coverage: MOD-004-R1-R11 and S1-S6 each map to at least one task (R1-R5 → T02-T05; R6-R8 → T06-T07; R7 → T09; R9 → T10-T11; R10 → T04-T05; R11 → T08; S6 → every test task and T12). No constitution conflict. Fixes applied: R4's thread-safety (`Sendable`) named in T03; T11 states the new code's severity. Noted, not changed: contract C5 lists the per-edge binding codes as errors although `SceneIssue` made them warnings in the MOD-013 amendment (pre-existing; outside this row).
