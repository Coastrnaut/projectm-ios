# Tasks: PRE-018 Preset integrity scanner

**Input**: `specs/194-pre-018-integrity-scanner/` (spec, plan, research, data-model, contracts, quickstart)
**Tests**: requested by the roadmap brief (acceptance fixture, clean library, bounds, UI test).
Budgets (owner rule 7): unit ≤ 10 s, package suite < 1 min, UI test < 30 s.

## Phase 1: Setup

- [ ] PRE-018-T01 Create simulator "PRE18 iPhone 17" (iOS 27.2), `xcodegen generate`, count PosterBoard reports (baseline)

## Phase 2: Foundational (PresetLibrary package)

- [ ] PRE-018-T02 [P] Model: `PresetIntegrityIssue` (kind missingTexture | danglingReference | missingFile | unparsable; stable `id` "<kind>|<store>|<collectionID>|<presetID>|<detail>"), `PresetReferenceStore`, `PresetIntegrityAction` (`isSafe` only for removeReference), `PresetIntegrityReport`, `PresetIntegrityLimits` (maxRecords 1,200; maxTextBytes 128 MiB; maxReferences 60,000; maxIssues 500; maxTexturesPerPreset 8), contract words in `Packages/PresetLibrary/Sources/PresetLibrary/Integrity/PresetIntegrityModel.swift`
- [ ] PRE-018-T03 [P] `PresetReferenceSnapshot` in `Packages/PresetLibrary/Sources/PresetLibrary/Integrity/PresetReferenceSnapshot.swift`
- [ ] PRE-018-T04 Pure `PresetIntegrityScanner.scan` (R3-R5, R14; research D5, D7) in `Packages/PresetLibrary/Sources/PresetLibrary/Integrity/PresetIntegrityScanner.swift`
- [ ] PRE-018-T05 `movedByUser` quarantine reason in `Packages/PresetLibrary/Sources/PresetLibrary/UserPresets/UserPresetModel.swift`; `UserPresetStore.restoreContents` in `UserPresetStore.swift`; `RecentPresetHistory.removing` in `RecentPresetHistory.swift`
- [ ] PRE-018-T06 `UserPresetLibrary` integrity: `integrityInventory(limits:)` (size + SHA-256 + validator re-check with the context's texture names; read-only), `relink(_:with:)` (checksum match only), `quarantineByUser(_:detail:)` in `Packages/PresetLibrary/Sources/PresetLibrary/Integrity/UserPresetLibrary+Integrity.swift`
- [ ] PRE-018-T07 Package tests: broken fixture → each kind once with the right suggestion; clean library → 0; bounds (records, bytes, references, issues, textures → incomplete); relink restores byte for byte, mismatch writes nothing; quarantineByUser; inventory changes no byte, in `Packages/PresetLibrary/Tests/PresetLibraryTests/PresetIntegrityTests.swift`

## Phase 3: User Story 1 — Find what is broken (P1) 🎯 MVP

**Independent test**: broken fixture library → 8 issues, each once, right kind and suggestion.

- [ ] PRE-018-T08 [US1] Make `UserPresetsCoordinator.library` and `PresetCoordinator`'s favorites and collections stores module-internal; `PresetCoordinator+Integrity.swift` (reference snapshot, `isKnownPreset`, reference removal per store) in `Apps/projectM-iOS/Coordinators/`
- [ ] PRE-018-T09 [US1] `LibraryIntegrityCoordinator` (scan off main, no overlap, report, result text, library-lane announcements, fixes, rescan after each fix) in `Apps/projectM-iOS/Coordinators/LibraryIntegrityCoordinator.swift`; construction and lane wiring in `AppCoordinator.swift`
- [ ] PRE-018-T10 [US1] `LibraryCheckView` (Check Library, "Not checked yet.", issues by kind, fix buttons + accessibility actions, confirmations, Re-import… picker) in `Apps/projectM-iOS/Views/LibraryCheckView.swift`; row in `UserPresetsView.swift`; route in `PresetBrowserView.swift`
- [ ] PRE-018-T11 [US1] DEBUG `-uitestBrokenLibrary` seed in `Apps/projectM-iOS/Debug/UITestBrokenLibraryFixture.swift`
- [ ] PRE-018-T12 [US1] Acceptance test (broken fixture through real stores: 8 issues once each; clean → 0) in `Apps/projectM-iOS/Tests/LibraryIntegrityAcceptanceTests.swift`

## Phase 4: User Story 2 — Fix the safe problems (P1)

- [ ] PRE-018-T13 [US2] Fix All Safe + single reference removal (recents via `RecentPresetsStore.remove`/`RecentPresetsCoordinator.removeIDs`); acceptance: rescan 0 dangling, 3 remain, presets untouched, in `LibraryIntegrityAcceptanceTests.swift`
- [ ] PRE-018-T14 [US2] UI test < 30 s: broken seed → My Presets → Check Library → issues listed → Fix All Safe → dangling gone, in `Apps/projectM-iOS/UITests/LibraryCheckUITests.swift`

## Phase 5: User Story 3 — Relink a lost file (P2)

- [ ] PRE-018-T15 [US3] Re-import… and Restore from Library in the coordinator (picked file read bounded, security-scoped); acceptance: restore by checksum removes the issue, mismatch refused, in `LibraryIntegrityAcceptanceTests.swift`

## Phase 6: Polish

- [ ] PRE-018-T16 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app, type-check budget, PosterBoard count, delete simulator and derived data; status and test counts in `spec.md`

## Dependencies

T01 → T02-T03 [P] → T04 → T05 → T06 → T07; T08 → T09 → T10/T11 → T12 → T13 → T14; T15 after T09; T16 last.

## Implementation strategy

MVP = Phase 2 + US1 (report). US2 adds the safe fixes; US3 the checksum relink.
