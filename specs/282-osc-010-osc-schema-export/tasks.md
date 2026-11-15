# Tasks: OSC-010 OSC Schema Export

**Input**: `specs/282-osc-010-osc-schema-export/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the brief (pure tests with an injected instant, a leak test, an app test, a short UI test,
device last). Unit tests about 1-2 s, package suite < 1 min, UI test < 30 s (owner rule 7). Tasks are ticked only
when verified, with " — Verified 2026-11-14: <how>".

## Phase 1: Setup

- [ ] OSC-010-T01 Audit OSC-003/004/008 routes, aliases and peers, the REC-012/PERF-012 share path and the SHD-003/MOD-001 descriptors; record the baseline in `specs/282-osc-010-osc-schema-export/spec.md`.

## Phase 2: Foundational (package)

- [ ] OSC-010-T02 `OSCSchemaRow`, `OSCSchemaExport.rows`, `document`, `fileName`, `utcStamp` (Foundation-free; header `| Address | Parameter ID | Name | Arguments | Input | Value range | Unit | Origin | Enabled |`; `|` escaped as `\|`) in `Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCSchemaExport.swift` (R2-R4; contract C1).

## Phase 3: User Story 1 - Document the routes (P2)

**Independent test**: build the document from a seeded table and compare it with the table.

- [ ] OSC-010-T03 [US1] Tests in `Packages/PerformanceControl/Tests/PerformanceControlTests/OSCSchemaExportTests.swift`: each table address appears exactly once and the (address, ID) set equals the table's including a user alias; ranges and units equal the descriptors; a disabled route says `off`; same instant and version → identical bytes; the UTC stamp of known instants; escaping (S1, S2).

## Phase 4: User Story 2 - Nothing private (P2)

- [ ] OSC-010-T04 [US2] `OSCSchemaExportCoordinator` in `Apps/projectM-iOS/Coordinators/OSCSchemaExportCoordinator.swift` (inputs from `OSCRoutesCoordinator` only; app version; injected clock; REC-012 share copy; finish deletes it) and the `.oscSchema` kind in `Apps/projectM-iOS/Coordinators/CaptureShareCoordinator.swift` (R1, R5, R7; contract C2).
- [ ] OSC-010-T05 [US2] App tests in `Apps/projectM-iOS/Tests/OSCSchemaExportCoordinatorTests.swift`: a seeded settings store with approved peers, `settings.osc.send.host`/`port`, `settings.osc.port` and a device name — the file contains none of those strings and no IPv4/IPv6 pattern; the file and request exist after export, a second export is refused while offered, finish deletes the copy (S3, S4).

## Phase 5: User Story 3 - Share it (P2)

- [ ] OSC-010-T06 [US3] `OSCSchemaExportSection` in `Apps/projectM-iOS/Views/OSCSchemaExportSection.swift` (button `oscSchemaExport`, presenter, DEBUG probe and stand-in) and the hook in `Apps/projectM-iOS/Views/OSCRoutesView.swift` (R1, R6).
- [ ] OSC-010-T07 [US3] UI test `Apps/projectM-iOS/UITests/OSCSchemaExportUITests.swift`: OSC Routes › Export routes… shows the share stand-in; the probe text lists `/projectm/param/glow.intensity` and `effect.bloom.intensity`; completed shows "Shared." (S5).

## Phase 6: Polish

- [ ] OSC-010-T08 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), the PerformanceControl suite, `LibraryBackupAppTests` and `SettingsTests` (no new keys), privacy manifest and network symbols on the Debug app, type-check budget, PosterBoard counts.
- [ ] OSC-010-T09 {device} D1: Settings › OSC › OSC Routes › Export routes… › Save to Files; the file lists every route on the screen, opens in Files, and holds no address or port (quickstart step 4).

## Dependencies

T01 → T02 → T03; T02 → T04 → T05; T04 → T06 → T07; all → T08. T09 needs a device and a person.
Parallel: T03 and T04 after T02.

## Implementation strategy

MVP is T02-T03 (the builder). Then the app path and its leak test, then the button and UI test.
