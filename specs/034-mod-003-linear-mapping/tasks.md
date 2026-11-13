# Tasks: MOD-003 Linear Mapping

**Input**: Design documents in `specs/034-mod-003-linear-mapping/` (spec.md, plan.md, research.md,
data-model.md, contracts/linear-mapping.md, quickstart.md).

**Tests**: test-first. Each test task comes before the code it covers; the red run (compile failure
or failing assertions) is recorded before the production change. Budgets (owner rule 7): each unit
test well under 1 s on the host, the package suite under 1 minute; representative cases only.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. `[P]` = can run in parallel
(different files). No `{device}` or `{sim}` task: the row changes no app code. Inside descriptions
"T03" is short for `MOD-003-T03`. A task is ticked only when its acceptance evidence was produced,
with " — Verified <date>: <how>" appended. Logs go to `.build/scratch/`.

## Phase 1: Setup

- [X] MOD-003-T01 Record the baseline: `swift test --package-path Packages/ParameterGraph` on the host (test count, failures). Evidence: counts recorded here. — Verified 2026-11-13: at f7c905e, ParameterGraph 42 tests on the host, 0 failures (0.008 s of tests, 6.6 s wall; .build/scratch/mod003-T01.log).

## Phase 2: Foundational

None: the mapping type is the first story's deliverable.

## Phase 3: User Story 1 - zero and one land exactly on the configured ends (P1) MVP

**Independent test**: `LinearMappingTests.testZeroAndOneMapToConfiguredEndpointsExactly`,
`testInputIsClampedToTheEnds`.

- [X] MOD-003-T02 [US1] Write `Packages/ParameterGraph/Tests/ParameterGraphTests/LinearMappingTests.swift` (a) the roadmap acceptance: for output ranges 0…1, 0.2…0.9, 0.9…0.1, −3…7, 7…−3, −5…−1, 1e−9…2e−9, −1e300…1e300, 1e300…1.5e300 and 0.1…0.1, `interpolate(0) == start`, `interpolate(1) == end`, and the same via the static `interpolate(from:to:at:)` (contract L2); (b) input 0.25…0.75 → 0.9…0.1: `map` of 0.25, 0, −1, −∞, +∞, NaN gives exactly 0.9 (non-finite → the start, MOD-002 semantics); of 0.75, 1, 2 exactly 0.1; Float-exact band levels (`Double(Float(0.25))`) are exact too (contract L1, L4); (c) `isValid` (false for 1…1, 1…0, NaN bounds, infinite ends), `isInverted`, `isConstant`, `.identity`; an invalid mapping's `position` and `map` return without trapping and positions stay in 0…1 (MOD-003-R8). — Verified 2026-11-13: written before the type (with T04 and T05 in the same new file); LinearMappingTests 3 US1 tests: testZeroAndOneMapToConfiguredEndpointsExactly, testInputIsClampedToTheEnds, testValidityAndInvalidMappingsDoNotTrap.
- [X] MOD-003-T03 [US1] Record the T02 red run; implement `Packages/ParameterGraph/Sources/ParameterGraph/LinearMapping.swift` per contract L1-L4 and research MOD-003-D1 ("finite, minimum below maximum" for validity; default input range 0…1; stored scalars and arithmetic only, so allocation-free by construction, MOD-003-R6). Evidence: T02 passes on the host. — Verified 2026-11-13: red run `cannot find 'LinearMapping' in scope` (.build/scratch/mod003-red-T02.log); after the change the US1 tests pass on the host (each 0.000 s; .build/scratch/mod003-T06.log). Semantics aligned with MOD-002 while implementing: a non-finite position (NaN or ±∞) reads 0, so +∞ input maps to the start (spec scenario, contract L1 and this task's text updated).

## Phase 4: User Story 2 - values in between stay in range and move one way (P1)

**Independent test**: `LinearMappingTests.testInterpolationIsBoundedAndMonotonic`.

- [X] MOD-003-T04 [US2] Add to `LinearMappingTests.swift`: over the T02 ranges, 1,001 evenly spaced positions plus 200 adjacent representable positions (`nextUp`) starting at 0.1, 0.3, 0.5, 0.7, 0.9 (1,000 steps): every result within `min…max` of the ends and ordered (non-decreasing for increasing ends, non-increasing for inverted); the constant range returns 0.1 exactly everywhere; positions −1, 2, NaN, ±∞ are clamped (contract L3). Each range's check well under 1 s. Evidence: passes on the host against T03's code (guard test; the formula was chosen for this property, so no red run is expected; record a red run by temporarily evaluating MOD-002's formula for the constant range in a scratch check if needed). — Verified 2026-11-13: testInterpolationIsBoundedAndMonotonic passes on the host in 0.011 s (10 ranges × 2,001 positions, zero violations). Guard test, no red run in Swift: the failure of MOD-002's formula on the constant range (4,725 of 100,001 positions outside, 4,579 reversals) is the audit evidence in research MOD-003-D1.

## Phase 5: User Story 3 - existing bindings behave the same (P1)

**Independent test**: `LinearMappingTests.testMatchesModulationTwoFormula`, MOD-002's suites unchanged.

- [X] MOD-003-T05 [US3] Add to `LinearMappingTests.swift` the regression sweep (contract L5): over 1,001 positions, ranges 0…1, −0.2…0.2, 0…10, 0.9…0, −3…7, −1e300…1e300 are bit-identical to `(1 − p)·start + p·end`; ranges 0.2…0.9, 0.9…0.1, 0.5…1, −5…−1, 1e300…1.5e300 differ by at most 2 units in the last place (`ulp` of the larger end magnitude); `AudioFeatureBinding.mapping` round-trips the four fields (get and set). — Verified 2026-11-13: testMatchesModulationTwoFormula and testBindingExposesItsMapping written before the binding change.
- [X] MOD-003-T06 [US3] Record the T05 red run (no `mapping` on the binding); add `mapping` to `Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureBinding.swift` and use `mapping.position(of:)` and `mapping.interpolate(_:)` in `Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureModulator.swift` (no other change). Evidence: the full ParameterGraph suite passes on the host with MOD-002's test files unmodified (`git diff --stat` shows no change under `AudioFeature*Tests.swift`). — Verified 2026-11-13: red run `value of type 'AudioFeatureBinding' has no member 'mapping'` (.build/scratch/mod003-red-T05.log); after the change ParameterGraph 48 tests pass on the host, 0 failures, 0.033 s of tests, 1.9 s wall (.build/scratch/mod003-T06.log); `git diff` shows no change to AudioFeature*Tests.swift (MOD-002's 16 modulator, validation and source tests pass unmodified); regression sweep bit-identical for opposite-sign/zero ranges and within 2 ulp otherwise.

## Phase 6: Polish & cross-cutting

- [X] MOD-003-T07 [P] Run `swift test --package-path Packages/VisualGenerators` and the Linux shape `swift test --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --scratch-path .build/linuxshape` (the app catalog's binding tests, Linux-safe code). Evidence: pass counts and durations recorded here. — Verified 2026-11-13: VisualGenerators on the host 103 XCTest tests, 0 failures (17.7 s of tests, 29.7 s wall; .build/scratch/mod003-T07-host.log); Linux shape (VISUAL_NO_METAL, ANALYSIS_NO_ACCELERATE) 81 tests, 0 failures (8.2 s, 15.4 s wall; .build/scratch/mod003-T07-linux.log). Pre-existing render tests take 2.1-5.3 s each (unchanged by this row).
- [X] MOD-003-T08 [P] Run `python3 scripts/check_compliance.py` and `python3 scripts/validate_docs.py`. The roadmap table is not edited (MOD-002 precedent: row status is tracked by the autonomous run's status files, not the roadmap). Evidence: both exit 0. — Verified 2026-11-13: check_compliance OK (exit 0); validate_docs OK (327 files); roadmap not edited.

## Dependencies

T01 → T02 → T03 → T04; T03 → T05 → T06 → T07, T08. US2 and US3 depend on US1's type; T07 and T08
run in parallel.

## Parallel execution

Within this small row, only T07 and T08 are parallel (different tools, no shared files).

## Implementation strategy

MVP = US1 (T01-T03): the named mapping with exact ends. US2 adds the bounded/monotonic proof,
US3 wires it into the modulator with the regression proof. One commit per story.
