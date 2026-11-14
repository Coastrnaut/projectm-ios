# Tasks: OSC-003 OSC Parameter Routes

**Input**: `specs/191-osc-003-parameter-routes/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: no wall-clock assertions (fake monotonic clock in package tests); unit tests about 1-2 s, package
suite < 1 min, UI test < 30 s (owner rule 7). Tasks are ticked only when verified, with
" — Verified 2026-11-14: <how>".

## Phase 1: Setup

- [X] OSC-003-T01 Audit OSC-001/002/009, MOD-001, MOD-003, MIDI-003 and ACC-012 code paths; record the baseline table in spec.md. — Verified 2026-11-14: spec.md "Baseline" (fixed `/projectm/test` route only; OSC-009 targets are parameter IDs; MIDI live values feed `NativeSpectrumHost.externalValues`).
- [X] OSC-003-T02 Network policy unchanged: no edit under `OSCTransport/`. — Verified 2026-11-14: `git diff 0cad6578 -- Packages/PerformanceControl/Sources/PerformanceControl/OSCTransport` is empty; `check_compliance` OK; `check_network_symbols` OK on the Debug simulator build (only the existing OSC and StoreKit allowances).

## Phase 2: Foundational (package, tests first)

- [X] OSC-003-T03 [US1] `OSCParameterRoutes` (routable set, table, active routes, normalized mapping) in `Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCParameterRoutes.swift`; `OSCRoute.scale`. — Verified 2026-11-14: OSCParameterRoutesTests.testTableListsOnlyRoutableParametersWithOneStandardRuleAndTheAlias passes.
- [X] OSC-003-T04 [US1] `OSCDispatcher`: mutable allowlist (`setRoutes`), `.normalized` mapping before the limiter, `liveValues`/`clearLiveValues`, `unknownAddresses` counter. — Verified 2026-11-14: all 230 PerformanceControl tests pass, including the unchanged OSC-001/002/009 dispatcher, receiver and flood tests.
- [X] OSC-003-T05 [US1] Acceptance fixture (S1): `OSCParameterRoutesTests.testKnownRouteChangesTheIntendedTargetAndUnknownRouteIsIgnored` (glow alias 0.25 → intensity 0.25, all other values bit-identical; `/projectm/unknown 1.0` → byte-identical store, `unknownAddresses` 1; `"text"` and `T` ignored) and `testADisabledRouteIsIgnoredAndOtherRoutesToTheSameParameterStillWork`. — Verified 2026-11-14: both pass (`swift test --package-path Packages/PerformanceControl`).
- [X] OSC-003-T06 [US1] Range mapping and clamp of normalized values (0, 1, 0.5, 7, -2, NaN, two arguments); rate limiter still applies with the mapped value held and flushed (S2). — Verified 2026-11-14: testNormalizedValuesMapOverTheRegistryRangeAndClamp and testTheTargetRateLimitStillAppliesAndTheHeldValueIsTheMappedOne pass.
- [X] OSC-003-T07 [US2] Alias rules and storage lines (S3). — Verified 2026-11-14: testAliasValidation (13 invalid formats, reserved prefix, duplicate, unroutable target, 16 maximum) and testUserAliasesRouteAndRoundTripTheirStorageLines pass.
- [X] OSC-003-T08 [US1] `ExternalLiveValues` (MIDI/OSC merge, newest change wins, fallback). — Verified 2026-11-14: ExternalLiveValuesTests passes (first run failed on empty-map bookkeeping, fixed).

## Phase 3: App

- [X] OSC-003-T09 [US1] App wiring: receiver store = test value + routable glow parameters, initial routes from settings; `OSCReceiverCoordinator.liveValues`/`applyLiveValues` on the gated refresh; `AppCoordinator.pushLiveValues` merges MIDI and OSC into the host. — Verified 2026-11-14: OSCRoutesCoordinatorTests.testARouteDrivesTheLiveValueAndADisabledRouteIsIgnoredAndRemembered and testTurningOSCOffForgetsLiveValues pass on the iOS 27.2 simulator.
- [X] OSC-003-T10 [US1] ACC-012 clamp applies to OSC values (S2). — Verified 2026-11-14: testTheOSCValueGoesThroughTheMIDIPathAndIsCappedByStrict passes (Strict caps 1.0 to the intensity limit; manual glow unchanged); MIDIMappingCoordinatorTests (14) still pass.
- [X] OSC-003-T11 [US2] `OSCRoutesCoordinator` persistence and aliases; keys in `LibrarySettingsPolicy.includedKeys`, `ALLOWED_KEYS` and the `-uitestResetNotice` reset. — Verified 2026-11-14: testAliasesAreValidatedStoredAndDeleted, testTheReceiverStoreAndTableCoverTheGlow pass; LibraryBackup 74 tests pass; `test_scripts.py` 159 OK.
- [X] OSC-003-T12 [US2] OSC Routes screen (`OSCRoutesView`) linked from Settings › OSC; UI test `OSCRoutesUITests` (S4). — Verified 2026-11-14: OSCRoutesUITests.testOSCRoutesListsTheGlowRoutesAndARouteToggles passes in 13.2 s; OSCReceiverUITests still passes (22.4 s).
- [X] OSC-003-T13 Type-check budget: build with `-warn-long-function-bodies=300 -warn-long-expression-type-checking=150`. — Verified 2026-11-14: build-for-testing succeeded with no long-type-check warning in the changed files.

## Phase 4: Polish

- [X] OSC-003-T14 Repo checks: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events, test_scripts, check_privacy_manifest, check_network_symbols. — Verified 2026-11-14: all OK.
- [ ] OSC-003-T15 {device} Send `/projectm/param/glow.intensity` from a controller on Wi-Fi to D1 and see the glow follow (quickstart). Not run: needs a device and a person.
