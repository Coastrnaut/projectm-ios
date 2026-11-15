# Tasks: OSC-010 OSC Schema Export

**Input**: `specs/282-osc-010-osc-schema-export/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the brief (pure tests with an injected instant, a leak test, an app test, a short UI test,
device last). Unit tests about 1-2 s, package suite < 1 min, UI test < 30 s (owner rule 7). Tasks are ticked only
when verified, with " — Verified 2026-11-14: <how>".

## Phase 1: Setup

- [X] OSC-010-T01 Audit OSC-003/004/008 routes, aliases and peers, the REC-012/PERF-012 share path and the SHD-003/MOD-001 descriptors; record the baseline in `specs/282-osc-010-osc-schema-export/spec.md`. — Verified 2026-11-14: spec.md "Baseline" table (route table, descriptors, REC-012/PERF-012 share path, network keys to exclude).

## Phase 2: Foundational (package)

- [X] OSC-010-T02 `OSCSchemaRow`, `OSCSchemaExport.rows`, `document`, `fileName`, `utcStamp` (Foundation-free; header `| Address | Parameter ID | Name | Arguments | Input | Value range | Unit | Origin | Enabled |`; `|` escaped as `\|`) in `Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCSchemaExport.swift` (R2-R4; contract C1). — Verified 2026-11-14: built with `swift test --package-path Packages/PerformanceControl`; no Foundation import in the file.

## Phase 3: User Story 1 - Document the routes (P2)

**Independent test**: build the document from a seeded table and compare it with the table.

- [X] OSC-010-T03 [US1] Tests in `Packages/PerformanceControl/Tests/PerformanceControlTests/OSCSchemaExportTests.swift`: each table address appears exactly once and the (address, ID) set equals the table's including a user alias; ranges and units equal the descriptors; a disabled route says `off`; same instant and version → identical bytes; the UTC stamp of known instants; escaping (S1, S2). — Verified 2026-11-14: OSCSchemaExportTests (6) pass on the macOS host in 0.002 s: each of the 5 table addresses once, (address, ID) set equals the table's including `/fader/1=effect.bloom.radius`, ranges/units equal the descriptors, byte-identical builds, UTC stamps incl. 2000-02-29 and before 1970.

## Phase 4: User Story 2 - Nothing private (P2)

- [X] OSC-010-T04 [US2] `OSCSchemaExportCoordinator` in `Apps/projectM-iOS/Coordinators/OSCSchemaExportCoordinator.swift` (inputs from `OSCRoutesCoordinator` only; app version; injected clock; REC-012 share copy; finish deletes it) and the `.oscSchema` kind in `Apps/projectM-iOS/Coordinators/CaptureShareCoordinator.swift` (R1, R5, R7; contract C2). — Verified 2026-11-14: built for the iOS 27.2 simulator (TEST BUILD SUCCEEDED); exercised by OSCSchemaExportCoordinatorTests.
- [X] OSC-010-T05 [US2] App tests in `Apps/projectM-iOS/Tests/OSCSchemaExportCoordinatorTests.swift`: a seeded settings store with approved peers, `settings.osc.send.host`/`port`, `settings.osc.port` and a device name — the file contains none of those strings and no IPv4/IPv6 pattern; the file and request exist after export, a second export is refused while offered, finish deletes the copy; a store that cannot write shows the failure notice and no request (S3, S4; edge cases). — Verified 2026-11-14: OSCSchemaExportCoordinatorTests (3) pass on "OSC10 iPhone 17" (iOS 27.2, 0.017 s): file `projectM-osc-routes-20261114-093005Z.md` with each table route once (incl. `/fader/1`, glow.knee off), refused second export, finish deletes the copy; seeded peers, `settings.osc.send.host`/`hostName`/`port`, `settings.osc.port` and a device name absent, no IPv4/IPv6/host:port/port-sized numbers; failed write shows the notice.

## Phase 5: User Story 3 - Share it (P2)

- [X] OSC-010-T06 [US3] `OSCSchemaExportSection` in `Apps/projectM-iOS/Views/OSCSchemaExportSection.swift` (button `oscSchemaExport`, presenter, DEBUG probe and stand-in) and the hook in `Apps/projectM-iOS/Views/OSCRoutesView.swift` (R1, R6). — Verified 2026-11-14: built; driven by OSCSchemaExportUITests. Existing OSCRoutesUITests reordered to reveal the standard route before the alias (it failed once after the list grew; passes 17.8 s).
- [X] OSC-010-T07 [US3] UI test `Apps/projectM-iOS/UITests/OSCSchemaExportUITests.swift`: OSC Routes › Export routes… shows the share stand-in; the probe text lists `/projectm/param/glow.intensity` and `effect.bloom.intensity`; completed shows "Shared." (S5). — Verified 2026-11-14: OSCSchemaExportUITests passes in 17.6 s on "OSC10 iPhone 17": stand-in shown, probe text holds the glow alias and test rows, "Shared." after completed.

## Phase 6: Polish

- [X] OSC-010-T08 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), the PerformanceControl suite, `LibraryBackupAppTests` and `SettingsTests` (no new keys), privacy manifest and network symbols on the Debug app, type-check budget, PosterBoard counts. — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 179 OK; check_privacy_manifest and check_network_symbols OK on the Debug app; PerformanceControl 320 tests pass (15.6 s); LibraryBackupAppTests 5, SettingsTests 9, OSCRoutesCoordinatorTests 5 pass (no new keys); no type-check warning in any OSC-010 file (300/150 ms flags); PosterBoard reports 32 before, 32 after.
- [ ] OSC-010-T09 {device} D1: Settings › OSC › OSC Routes › Export routes… › Save to Files; the file lists every route on the screen, opens in Files, and holds no address or port (quickstart step 4).

## Analysis (speckit-analyze, 2026-11-14)

Every requirement maps to a task: R1 → T04, T06, T07; R2-R4 → T02, T03; R5 → T05; R6 → T07 (OSC off); R7 → T04,
T05; R8 → T08. Fixed: the write-failure edge case had no test (added to T05). No constitution conflict; no
ambiguity or duplication found.

## Dependencies

T01 → T02 → T03; T02 → T04 → T05; T04 → T06 → T07; all → T08. T09 needs a device and a person.
Parallel: T03 and T04 after T02.

## Implementation strategy

MVP is T02-T03 (the builder). Then the app path and its leak test, then the button and UI test.
