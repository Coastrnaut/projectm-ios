# Tasks: MOD-005 Attack/Release Envelope

**Input**: Design documents in `specs/141-mod-005-attack-release/` (spec.md, plan.md, research.md,
data-model.md, contracts/envelope.md, quickstart.md).

**Tests**: test-first; the red run (compile failure) is recorded before the production change.
Budgets (owner rule 7): each unit test about 1-2 s or less, each package suite under 1 minute.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. Inside descriptions "T03" is short
for `MOD-005-T03`. A task is ticked only when its evidence was produced, with " — Verified <date>:
<how>" appended. Logs go to `.build/scratch/mod-005/`.

## Phase 1: Setup

- [X] MOD-005-T01 Record the baseline: `swift test --package-path Packages/ParameterGraph` and `swift test --package-path Packages/SceneFormat` on the host (counts, failures); count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips`. — Verified 2026-11-14: at 08c5551a, ParameterGraph 136 tests on the host (93 + 43, 1 skipped), 0 failures (10.8 s wall incl. build); SceneFormat 124 tests, 0 failures (2.4 s of tests); PosterBoard reports 25 (.build/scratch/mod-005/T01-*.log).

## Phase 2: Foundational

None: the pure step (contract E2) is User Story 1's and User Story 2's shared deliverable and is built first in Phase 3.

## Phase 3: User Story 1 - a step follows the chosen rise and fall times (P1) MVP

**Independent test**: `EnvelopeStepResponseTests.testStepInputFollowsSelectedTimeConstantsWithinTolerance`.

- [X] MOD-005-T02 [US1] Write `Packages/ParameterGraph/Tests/ParameterGraphTests/EnvelopeStepResponseTests.swift`: (a) the roadmap acceptance through `AudioFeatureModulator`: attack/release pairs (0.05, 0.5), (0.25, 0.1), (1, 2) × frame patterns 60 fps, 120 fps and seeded jitter (SplitMix64, 4–40 ms): a 0→1 step held 5τa then a 1→0 step held 5τr; every frame within 0.01 absolute of the analytic curve (E1), and within 1e-9 (E3); the first frame at or above 63.2 % (rise) and at or below 36.8 % of the start (fall) lies within one frame duration of τ; (b) rise uses only attack and fall only release (swap one time and the other phase is unchanged); (c) the 10–90 % helpers: `riseTime10To90(timeConstant: 1) == log(9)` and the inverse round-trips; (d) direct `step` cases of contract E2, called without a registry or modulator (MOD-005-R11). — Verified 2026-11-14: written before the production change (EnvelopeStepResponseTests.swift, 6 tests including T04's and T05's); red run `value of type 'AudioFeatureEnvelope' has no member 'step'`, `no member 'setEnvelope'` (.build/scratch/mod-005/red-T02.log).
- [X] MOD-005-T03 [US1] Record T02's red run; implement in `Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureBinding.swift` the documented definition (E1), `step(from:toward:elapsedSeconds:)` (E2: "A non-finite `target` reads 0"; "τ ≤ 0 (or not finite) returns the target"; "`elapsedSeconds` ≤ 0 or not finite returns `current` clamped to 0…1"; result clamped to 0…1), `tenToNinetyFactor`, `riseTime10To90(timeConstant:)`, `timeConstant(riseTime10To90:)`; call `step` from `AudioFeatureModulator.advance` in `AudioFeatureModulator.swift`, keeping the existing clock rules (E4). Evidence: T02 passes; the existing `AudioFeatureModulatorTests` (including the bit-identical determinism test) and `CurvedBindingTests` pass unchanged. — Verified 2026-11-14: acceptance test passes in 0.005 s (9 runs: 3 settings × 60 fps, 120 fps, seeded jitter; every frame within 0.01 and 1e-9 of the analytic curve, 63.2 %/36.8 % crossings within one frame); existing AudioFeatureModulatorTests (12, incl. the bit-identical determinism test) and CurvedBindingTests (6) pass unchanged; ParameterGraph 142 tests (99 + 43, 1 skipped), 0 failures (.build/scratch/mod-005/T03.log).

## Phase 4: User Story 2 - safe and predictable at the edges (P1)

**Independent test**: `EnvelopeStepResponseTests.testEdgeInputsStayFiniteBoundedAndDeterministic`.

- [X] MOD-005-T04 [US2] Add to `EnvelopeStepResponseTests.swift`: τ = 0 in either direction is instant (also with Δt = 0); repeated and backwards frame times leave a smoothed signal unchanged; a gap of 9 s counts as 0.25 s; NaN, +∞ and −∞ feature values move toward 0 and stay finite in 0…1; `step` with a NaN current, a NaN or infinite elapsed time, a target of 2 or −1 stays in 0…1; times 60 accepted and 60.000001, −0.001, NaN, ∞ refused by `bind` with `invalidEnvelope`; two runs of the jitter simulation are bit-identical. Evidence: passes after T03. — Verified 2026-11-14: testEdgeInputsStayFiniteBoundedAndDeterministic passes (.build/scratch/mod-005/T03.log).

## Phase 5: User Story 3 - live change and scenes (P2)

**Independent test**: `EnvelopeStepResponseTests.testSetEnvelopeContinuesFromTheCurrentSignal`, `SceneEnvelopeTests`, `EnvelopeBindingAppTests`.

- [X] MOD-005-T05 [US3] Add to `EnvelopeStepResponseTests.swift`: `setEnvelope` mid-rise continues from the current signal with the new τ (next frame matches the analytic step from that value); unbound target throws `unknownTarget`; invalid times throw `invalidEnvelope` and leave the binding and signal unchanged (E6). Record the red run, then implement `setEnvelope(_:for:)` in `Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureModulator.swift` (in place, no allocation). — Verified 2026-11-14: red run in red-T02.log (`no member 'setEnvelope'`); after AudioFeatureModulator.setEnvelope(_:for:) testSetEnvelopeContinuesFromTheCurrentSignal passes (.build/scratch/mod-005/T03.log).
- [X] MOD-005-T06 [P] [US3] Write `Packages/SceneFormat/Tests/SceneFormatTests/SceneEnvelopeTests.swift`: a scene with envelope (0.08, 1.5) encodes, decodes and restores with equal times and a bit-identical step response to the original binding; a scene with only `attack` reads release 0 and with no `envelope` reads `.none` (legacy shape); an attack of −1 or 61 rejects that binding (outcome rejected, preserved for re-save) with issue `invalidBinding` at `$.bindings[0].envelope`. Record the red run of the path assertion. — Verified 2026-11-14: SceneEnvelopeTests.swift (3 tests); red run: the invalid-time test failed with path `$.bindings[0]` instead of `$.bindings[0].envelope`, the round-trip and legacy-shape tests already passed (.build/scratch/mod-005/red-T06.log).
- [X] MOD-005-T07 [US3] In `Packages/SceneFormat/Sources/SceneFormat/SceneModulationRestore.swift`, report `invalidEnvelope` at `path + ".envelope"` (other errors unchanged). Evidence: T06 passes; whole SceneFormat suite (including QA-004's meta-test and the legacy fixtures) passes. — Verified 2026-11-14: SceneEnvelopeTests 3/3 pass; whole SceneFormat suite 127 tests, 0 failures, 2.5 s of tests, including SceneMigrationMatrixMetaTests (QA-004) and the legacy fixtures (.build/scratch/mod-005/T07.log).
- [X] MOD-005-T08 [US3] Write `Apps/projectM-iOS/Tests/EnvelopeBindingAppTests.swift`: a band bound to `VisualParameterIDs.bloomIntensity` with attack 0.5 s and release 0.05 s through `NativeSpectrumHost.bind`; drive 60 fps frames: after 0.5 s of band 1 the effective glow is 1 − e⁻¹ within 0.01 (slow rise), then after 0.05 s of band 0 it is that value × e⁻¹ within 0.01 and below 0.01 after 0.25 s (fast fall); skips without Metal. Run it on the private simulator "MOD5 iPhone 17" (build-for-testing, then test-without-building -only-testing). — Verified 2026-11-14: on the private simulator "MOD5 iPhone 17" (iOS 27.2), after merging autonomous/integration (its ParameterInspectorModel fix for `.midTransient` was needed to build): build-for-testing 11 s (incremental, type-check flags on, no warning in MOD-005 files), test-without-building EnvelopeBindingAppTests 1/1 passed (0.02 s) together with AudioFeatureBindingAppTests 6/6 and CurveMappingAppTests 3/3, 10 tests in 28 s wall (.build/scratch/mod-005/T08-*.log).

## Phase 6: Polish & Cross-Cutting

- [X] MOD-005-T09 Run the whole ParameterGraph and SceneFormat suites on the host (durations under 1 minute) and the repository checks (`check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `check_status_events.py`, `test_scripts.py`); Linux shape (MOD-005-S5; Linux itself runs only in CI, not on this Mac): no Apple-only API added to ParameterGraph or SceneFormat (grep for `import Darwin`, `os.`, `stdout`). — Verified 2026-11-14 (after merging autonomous/integration): ParameterGraph 142 tests (99 + 43, 1 skipped), 0 failures, 1 s wall; SceneFormat 127 tests, 0 failures, 9 s wall; check_compliance, validate_docs (1219 files), check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 153 tests OK (1 skipped); no Darwin/stdio use in the changed files. Linux itself not run here (CI).
- [X] MOD-005-T10 Update the binding docs: `AudioFeatureBinding.swift` header and `specs/059-scn-001-versioned-scene-format/contracts/scene-document.md` envelope row (meaning τ, 0…60 s, issue path) if it describes the envelope; set spec Status to Implemented; count PosterBoard reports again. — Verified 2026-11-14: header and scene-document contract envelope paragraph updated, validate_docs OK; spec Status Implemented; PosterBoard reports 25 before and after (no new report).

## Dependencies

T01 → T02 → T03 → T04 → T05; T06 can be written in parallel with T02-T05; T07 after T06; T08 after T03 (and T05 not required); T09, T10 last.

## Parallel examples

- T06 (SceneFormat tests) alongside T02 (ParameterGraph tests): different packages.

## Implementation strategy

MVP is User Story 1 (T01-T03): the acceptance proof on the existing envelope. Then the edge cases
(T04), live change and scenes (T05-T07), the app check on the simulator (T08), polish (T09, T10).
