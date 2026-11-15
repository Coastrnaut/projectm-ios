# Tasks: SHOW-008 Keyframe Tracks

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/show-keyframe-tracks.md](contracts/show-keyframe-tracks.md), [quickstart.md](quickstart.md)

Tests are required (roadmap acceptance, owner rule 7 budgets). `{device}` tasks need a person and stay open.

## Phase 1: Setup

- [X] SHOW-008-T01 Create simulator "SHOW8 iPhone 17" (iOS 27.2), run `xcodegen generate`, record the PosterBoard report count before runs — Verified 2026-11-14: simulator 5C0C014E ("SHOW8 iPhone 17", iOS 27.2) created, `xcodegen generate`, preset submodules initialised; PosterBoard reports 27 before runs

## Phase 2: Foundational (pure model, ShowControl)

- [X] SHOW-008-T02 Add `ShowKeyframeColor`, `ShowKeyframeValue`, `ShowKeyframeInterpolation`, `ShowKeyframe`, `ShowKeyframeTrack` (`value(at:)` exact at keys, segment-relative between, edits) and `ShowKeyframeTracks` (limits, `values(at:)`, edits) in Packages/ShowControl/Sources/ShowControl/ShowKeyframes.swift — Verified 2026-11-14: `swift test --package-path Packages/ShowControl` (135 tests, 1.2 s; 7 new in ShowKeyframeTrackTests)
- [X] SHOW-008-T03 `ShowCueList.tracks`; `show.json` `tracks` written only when non-empty, lenient read with `droppedKeyframeTracks`/`droppedKeyframes` warnings in Packages/ShowControl/Sources/ShowControl/ShowKeyframesDocument.swift, ShowCueList.swift and ShowDocument.swift — Verified 2026-11-14: `ShowKeyframeTrackTests.testTracksRoundTripAndOldShowsKeepTheirBytes`, `testDamagedTracksAndKeyframesAreDroppedWithCountedWarnings`; all 128 earlier ShowControl tests still pass
- [X] SHOW-008-T04 [P] Package tests (K1 exact at every key, numbers and colours; K2 hold/linear/ease midpoints, linear-light colour midpoint, before/after; K3 pure; K4 round trip byte-identical, lenient drops, limits; edits replace at same time, kind mismatch refused) in Packages/ShowControl/Tests/ShowControlTests/ShowKeyframeTrackTests.swift — Verified 2026-11-14: `ShowKeyframeTrackTests` 7/7 (exact at every key bit for bit, numbers and colours; midpoints; linear-light colour; purity; edits; round trip; lenient read)

## Phase 3: User Story 1 — Glow rises along the show (P1, MVP)

**Independent test**: seek to a keyframe time → that exact value applied once; play across keys → same sequence twice.

- [X] SHOW-008-T05 [US1] `ShowCoordinator.setKeyframeTracks(_:)` (an edit: refused while locked, saves at once) in Apps/projectM-iOS/Coordinators/ShowCoordinator.swift — Verified 2026-11-14: `ShowKeyframeAcceptanceTests.testEditsAddAtPlayheadClampAndAreRefusedWhileLocked` (lock refuses; saved); `ShowCoordinatorTests` pass
- [X] SHOW-008-T06 [US1] `ShowKeyframeCoordinator` (targets from the MOD-001 registry plus Visual Colour, `sample()`, apply-on-change, sampling loop, `addKeyframeAtPlayhead`, edits) in Apps/projectM-iOS/Coordinators/ShowKeyframeCoordinator.swift; `positionJumped` hook in ShowTransportCoordinator.swift — Verified 2026-11-14: `ShowKeyframeAcceptanceTests` 6/6 (0.08 s); `ShowTransportAcceptanceTests` 7/7 still pass with the `positionJumped` hook
- [X] SHOW-008-T07 [US1] Output wiring: one lazy var, `showTrackOutput`, `hostExternalValues` (tracks under MIDI/OSC) in AppCoordinator.swift and AppCoordinator+Show.swift — Verified 2026-11-14: app build-for-testing; `testStandbyReleasesTheParametersAndLiveValuesWin` (track numbers under MIDI/OSC values); LibraryBackupAppTests, LibraryEraseAppTests pass
- [X] SHOW-008-T08 [US1] Acceptance tests (S3: seek to a key applies its exact value once, repeat none; play across three keys with a manual clock twice → identical sequences; Standby → empty output; MIDI/OSC wins; lock refuses edits; add at playhead replaces at same time) in Apps/projectM-iOS/Tests/ShowKeyframeAcceptanceTests.swift — Verified 2026-11-14: `ShowKeyframeAcceptanceTests`: seek to each keyframe time → one apply, bit-exact value; repeat → none; play across keys twice with `ShowManualClock` → identical sequences, exact at keys

## Phase 4: User Story 2 — Colour along the show (P1)

- [X] SHOW-008-T09 [US2] Visual Colour: `effectiveSpectrumPalette` returns a one-colour palette from the track colour unless the colour-blind-safe palette is on (AppCoordinator.swift); acceptance test (colour at key exact, colour-blind-safe wins) — Verified 2026-11-14: `testColourTrackIsExactAtKeysAndColourBlindSafeWins` (exact colour at key, linear-light midpoint, `trackPalette` nil when colour-blind-safe); PaletteAppTests pass

## Phase 5: User Story 3 — Edit tracks (P1)

- [X] SHOW-008-T10 [US3] `ShowKeyframeTracksView` and `ShowKeyframeEditView` (playhead, Add Track menu, keyframe rows with VoiceOver labels, Add Keyframe at Playhead, ACC-005 slider / colour picker, interpolation picker, deletes; hidden while locked) in Apps/projectM-iOS/Views/ShowKeyframeTracksView.swift; link from Apps/projectM-iOS/Views/ShowEditorView.swift — Verified 2026-11-14: `ShowKeyframeUITests` (link, Add Track… dialog, Add Keyframe at Playhead, row label); type-check flags: no warning in the new views
- [X] SHOW-008-T11 [US3] UI test (add Glow Intensity, add keyframe at playhead, row listed; < 30 s) in Apps/projectM-iOS/UITests/ShowKeyframeUITests.swift — Verified 2026-11-14: `ShowKeyframeUITests` passes in 19.2 s on "SHOW8 iPhone 17" (iOS 27.2)

## Phase 6: Polish

- [X] SHOW-008-T12 Regression: ShowControl package on host; ShowTransportAcceptanceTests, ShowCoordinatorTests, LibraryBackupAppTests; Linux shape (Foundation and ParameterGraph only, no stdio globals) — Verified 2026-11-14: 57 app unit tests (10 suites) and 2 UI tests (ShowTimelineUITests, ShowKeyframeUITests) pass in 58 s; ShowControl 135 tests on the host; new ShowControl files use Foundation, ParameterGraph and Darwin/Glibc/Musl only, no stdio globals
- [X] SHOW-008-T13 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), type-check budget, privacy manifest and network symbols on the Debug app — Verified 2026-11-14: compliance, docs, motion, permission catalog, status events OK; 179 script tests OK; `check_privacy_manifest` OK and `check_network_symbols` OK on the Debug app; type-check flags: no warning in new or changed code (AppCoordinator's init exceeds 300 ms on this loaded Mac with and without this change: 469 ms on the baseline)
- [ ] SHOW-008-T14 {device} D1: a glow ramp and a colour track across two cues on the projector; scrub to a keyframe time and see its value

## Dependencies

T01 → T02 → T03 → T04; T03 → T05-T08 (US1) → T09 (US2) → T10-T11 (US3) → T12-T13. T14 after all.
Parallel: T04 with T05.

## Implementation strategy

MVP = US1 (exact values at keyframes through the live path, the roadmap acceptance). US2 adds colour, US3 the editor.
