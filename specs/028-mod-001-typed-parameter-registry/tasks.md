# Tasks: MOD-001 Typed Parameter Registry

**Input**: Design documents in `specs/028-mod-001-typed-parameter-registry/` (spec.md, plan.md,
research.md, data-model.md, contracts/parameter-registry.md, quickstart.md); ADR-0012.

**Tests**: test-first. Each test task comes before the code it covers; the red run (compile failure
or failing assertions) is recorded before the production change. Budgets (owner rule 7): a unit
test about 1-2 s (≤ 10 s) on the host, a package suite under 1 minute; representative cases only.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. `[P]` = can run in parallel
(different files). Tags: `{device}` = needs a physical device (none in this row); `{sim}` = needs
this row's own iOS 27.2 simulator "MOD iPhone 17". Inside descriptions "T07" is short for
`MOD-001-T07`. A task is ticked only when its acceptance evidence was produced, with
" — Verified <date>: <how>" appended. Logs go to `.build/scratch/`.

## Phase 1: Setup

- [X] MOD-001-T01 Record the baseline: `swift test --package-path Packages/VisualGenerators` on the host; `python3 scripts/check_compliance.py`, `scripts/validate_docs.py`, `scripts/test_scripts.py`. Evidence: counts recorded here. — Verified 2026-11-13: at ff76f50, VisualGenerators 95 tests on the host, 0 failures (14.9 s; .build/scratch/mod001-T01-vg.log); check_compliance OK; validate_docs OK; test_scripts.py 99 tests OK (1 skipped).
- [X] MOD-001-T02 Create `Packages/ParameterGraph/Package.swift` (tools 6.0; platforms iOS 26, macOS 15; one library product and target `ParameterGraph`, test target `ParameterGraphTests`; no dependencies) with a header comment naming MOD-001 and ADR-0012; add `ParameterGraph` to the five package loops in `.github/workflows/ios-ci.yml` (Linux tests, macOS host tests, generic-iOS compile, iOS 26 and iOS 27 simulator tests). Evidence: `swift build --package-path Packages/ParameterGraph` succeeds; `grep -c ParameterGraph .github/workflows/ios-ci.yml` = 5. — Verified 2026-11-13: `swift build --package-path Packages/ParameterGraph` succeeds (after T04 added sources); `grep -c` finds ParameterGraph in all 5 package loops of ios-ci.yml.

## Phase 2: Foundational (model types; blocks every story)

- [X] MOD-001-T03 [P] Write `Packages/ParameterGraph/Tests/ParameterGraphTests/ParameterIDTests.swift`: well-formed IDs (`visual.circularSpectrum.gap`, `effect.bloom.radius`, `a.b1`); ill-formed: empty, one segment, empty segment (`a..b`, `.a.b`, `a.b.`), uppercase or digit first character, non-ASCII, `-`/`_`/space, 129 characters; `domain`, `segments`; `Codable` as a bare JSON string and as a dictionary key (`CodingKeyRepresentable`); `ParameterValue` JSON round trip for all five kinds with explicit kind tags (integer 1 and continuous 1.0 stay distinct); enum case ID syntax "`[a-z0-9][A-Za-z0-9]*`". — Verified 2026-11-13: written before the sources; ParameterIDTests 5 tests.
- [X] MOD-001-T04 Record the T03 red run in `.build/scratch/mod001-red-T03.log`; implement `ParameterID.swift`, `ParameterKind.swift` (unit, curve, kind, `ParameterEnumCase`, `ParameterColor`), `ParameterValue.swift`, `ModulationPolicy.swift`, `ParameterDescriptor.swift` (with `ParameterRegistrationSite` captured by `#fileID`/`#line` default arguments) in `Packages/ParameterGraph/Sources/ParameterGraph/` per data-model.md. Evidence: T03 passes on the host. — Verified 2026-11-13: red run: `target 'ParameterGraph' referenced in product 'ParameterGraph' is empty` (.build/scratch/mod001-red-T03.log); after the change ParameterIDTests 5 tests pass on the host, each < 0.001 s; no warnings (.build/scratch/mod001-T04.log).

## Phase 3: User Story 2 - malformed catalogs fail validation (P1)

**Goal**: the roadmap acceptance ("Duplicate IDs fail validation and defaults remain in range").
**Independent test**: `RegistryValidationTests`.

- [X] MOD-001-T05 [US2] Write `Packages/ParameterGraph/Tests/ParameterGraphTests/RegistryValidationTests.swift`: a duplicate ID throws and the message names the ID, both display names and both `file:line` sites; one representative fixture per `Problem` case of data-model.md (`malformedID`, `retiredID`, `emptyDisplayName`, `malformedGroup`, `conflictingGroupName`, `nonFiniteNumber`, `emptyRange` for min = max and min > max, `invalidStep`, `defaultOutOfRange` for continuous and integer, `invalidCurve` (log with min ≤ 0), `noEnumCases`, `malformedEnumCase`, `duplicateEnumCase`, `unknownEnumDefault`, `colorOutOfRange`, `invalidModulationPolicy` for "not modulatable lists no mix modes" and "add/multiply only for continuous and integer"), each naming the parameter; several defects in one catalog are all reported in registration order; a valid catalog builds. — Verified 2026-11-13: written before the validator; RegistryValidationTests 6 tests (one fixture per Problem case, 17 kinds).
- [X] MOD-001-T06 [US2] Record the T05 red run; implement `ParameterValidation.swift` (issues, `ParameterRegistryError` with one message per line) and `ParameterRegistry.swift` (`init(descriptors:retiredIDs:) throws(ParameterRegistryError)`, `validate`, lookup, `descriptors(inGroup:)`, `ids`, `groups`). Evidence: T05 passes on the host. — Verified 2026-11-13: red run `cannot find type 'ParameterValidationIssue' in scope` (.build/scratch/mod001-red-T05.log); one test-helper fix (an empty ID cannot be 'mentioned'); then RegistryValidationTests 6 tests pass on the host, each < 0.001 s; ParameterGraph 11 tests (.build/scratch/mod001-T06.log).

## Phase 4: User Story 1 - every editable visual parameter has a stable identity (P1)

**Goal**: the observable behavior. **Independent test**: `RegistryEnumerationTests`,
`VisualParameterCatalogTests`, `ParameterCatalogAppTests`.

- [ ] MOD-001-T07 [P] [US1] Write `Packages/ParameterGraph/Tests/ParameterGraphTests/RegistryEnumerationTests.swift`: enumeration and group queries return registration order; two enumerations and two builds give identical ID sequences; `groups` in first-appearance order; lookup of an unknown ID is nil. Evidence: passes with T06's code (no new production code expected; if it fails, fix the registry).
- [ ] MOD-001-T08 [P] [US1] Write `Packages/VisualGenerators/Tests/VisualGeneratorsTests/VisualParameterCatalogTests.swift`: the catalog validates; exactly the 14 IDs of data-model.md in that order; every default finite and in range; drift: each range, default and enum case list equals `CircularSpectrumConfiguration`, `LinearSpectrumConfiguration`, `SpectrumBarCount.allCases`, `LinearSpectrumOrientation.allCases` and `BloomParameters` values (Float via `Double(Float)`); policies: continuous parameters modulatable with replace/add/multiply, enums and boolean manual only, all externally controllable; no ID mentions `reduceFlashing`.
- [ ] MOD-001-T09 [US1] Record the T08 red run; add target `VisualParameters` (dependencies `VisualGenerators`, `VisualEffects`, `ParameterGraph`) to `Packages/VisualGenerators/Package.swift`, add it to the library product and the test target, and implement `Packages/VisualGenerators/Sources/VisualParameters/VisualParameterCatalog.swift` (`VisualParameterIDs`, `VisualParameterCatalog.descriptors`, `retiredIDs`, `makeRegistry()`), reading every number from the types (no literal ranges or defaults). Evidence: T08 passes on the host; the whole VisualGenerators suite passes with the T01 count plus T08's tests.
- [ ] MOD-001-T10 [US1] {sim} Write `Apps/projectM-iOS/Tests/ParameterCatalogAppTests.swift`: `AppSettings`' default bars and every bar choice are cases of `visual.circularSpectrum.barCount` and `visual.linearSpectrum.barCount`; every spacing choice and the default spacing lie in `visual.linearSpectrum.spacing`'s range; the default orientation and every `LinearSpectrumOrientation` raw value are its cases; the glow defaults equal the bloom descriptors' defaults. Record the run (`xcodegen generate`; `-only-testing:projectM-iOSTests/ParameterCatalogAppTests` and `SettingsTests` on "MOD iPhone 17"). Evidence: both classes pass; `SettingsTests` unchanged.

## Phase 5: User Story 3 - typed, clamped, observable current values (P2)

**Independent test**: `ParameterStoreTests`, `ParameterSnapshotTests`.

- [ ] MOD-001-T11 [P] [US3] Write `Packages/ParameterGraph/Tests/ParameterGraphTests/ParameterStoreTests.swift`: initial values are defaults; continuous 1.5 in 0…1 → 1 with one notification (old, new, change count 1); −0.5 → 0; no snapping of continuous values with a step; integer snap-then-clamp (range 0…10 step 2: nearest step from the minimum, ties toward the maximum, so 3 → 4 and 5 → 6; 11 → 10); color components clamp; NaN, ±∞, wrong kind, unknown ID, unknown enum case each throw a readable error with no state, counter or notification change; equal value → no notification; typed accessors for all five kinds round-trip and return nil for another kind; `reset`/`resetAll`; two observers are called in the order they were registered; a cancelled observation receives nothing; an observer may read the store re-entrantly (no deadlock: the lock is released before observers run); concurrent sets from 4 tasks × 250 sets end with `changeCount` equal to the number of effective changes (no timing assertion).
- [ ] MOD-001-T12 [US3] Record the T11 red run; implement `Packages/ParameterGraph/Sources/ParameterGraph/ParameterStore.swift` (`Mutex` state, `ParameterStoreError`, `ParameterChange`, `ParameterObservation`). Evidence: T11 passes on the host.
- [ ] MOD-001-T13 [P] [US3] Write `Packages/ParameterGraph/Tests/ParameterGraphTests/ParameterSnapshotTests.swift`: snapshot → JSON (sorted keys, stable string) → decode → restore into a fresh store reproduces every value of all five kinds; an unknown ID is reported orphaned and not applied; a wrong-kind entry is rejected with its reason; an out-of-range entry is clamped; a newer `schemaVersion` is rejected whole; rollback: snapshot, change values, restore → values and a further snapshot equal the first.
- [ ] MOD-001-T14 [US3] Record the T13 red run; implement `Packages/ParameterGraph/Sources/ParameterGraph/ParameterSnapshot.swift` and `ParameterStore.snapshot()`/`restore(_:)`. Evidence: T13 passes on the host.

## Phase 6: Polish and cross-cutting

- [ ] MOD-001-T15 Run every touched package: `swift test --package-path Packages/ParameterGraph` and `Packages/VisualGenerators` on the host (record counts and durations; each new test ≤ 2 s, suites < 1 min); compile both for generic iOS (`xcodebuild -scheme <pkg> -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`); `swift build --build-tests` shows no warnings in the new files. Linux: pending CI (no Linux host here).
- [ ] MOD-001-T16 `python3 scripts/check_compliance.py`, `scripts/validate_docs.py`, `scripts/test_scripts.py` pass; count new `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` files since the start of the row; shut down "MOD iPhone 17".

## Dependencies

- T01 → T02 → T03/T04 → (US2: T05 → T06) → (US1: T07; T08 → T09 → T10) and (US3: T11 → T12 → T13 → T14) → T15 → T16.
- US1 depends on US2 (the catalog is built through validation). US3 depends only on the foundational types and the registry.

## Parallel opportunities

- T03 and T05's fixtures can be drafted together; T07, T08, T11 and T13 are separate test files.
- US1 (T08-T10) and US3 (T11-T14) are independent once T06 is done.

## Implementation strategy

MVP = Phases 1-4 (US2 + US1): the roadmap's acceptance and observable behavior. US3 completes the
"current manual value" of the roadmap's parameter boundary. No device step exists in this row.
