# Tasks: SCN-002 Scene Autosave

**Input**: `specs/067-scn-002-scene-autosave/` (spec, plan, research, data-model, contracts/scene-autosave.md,
quickstart). Tests are required by the spec (SCN-002-S1…S6). Budgets (owner rule 7): unit tests about
1-2 s, the UI test under 30 s. `{device}` = needs a person and a device.

## Phase 1: Setup

- [ ] SCN-002-T01 Add public `SceneJSON.parse(_:)` (bounded: 1 MiB, depth 32, the existing reader) in Packages/SceneFormat/Sources/SceneFormat/SceneJSON.swift with a test in Packages/SceneFormat/Tests/SceneFormatTests/SceneJSONTests.swift (host and Linux shape)

## Phase 2: Foundational

- [ ] SCN-002-T02 [P] Debouncer (quiet 1 s, maximum latency 5 s, injected clock; `deadline = min(lastEdit + quiet, firstPending + maximumLatency)`) in Apps/projectM-iOS/Coordinators/SceneAutosaveDebouncer.swift
- [ ] SCN-002-T03 [P] Store: files `current.scene`, `current.scene.bak`, `current.scene.tmp` in Application Support/Scenes; save sequence A2 with a per-step fault hook and `mainIsGood`; load A3 (leftover temporary removed, bounded read, decode + `liveState`, main → backup → none, newer-version file set aside as `current.scene.newer`, events) in Apps/projectM-iOS/Coordinators/SceneAutosaveStore.swift
- [ ] SCN-002-T04 [P] Capture: `SceneInputs`, `SceneAutosaveCarry`, inputs → document (layers per research D1, seven parameters, assets `photo`/`video`/`text`, bindings), merge D6 (unknown layers at their index, renumbering, 8-layer cap, matched known layers, carried assets, parameters, modulation, ID, name, extra), document → restored values in Apps/projectM-iOS/Coordinators/SceneAutosaveCapture.swift

## Phase 3: User Story 1 — the last committed look survives a kill (P1) 🎯 MVP

**Independent test**: kill after a committed edit and an uncommitted one; relaunch shows the committed one.

- [ ] SCN-002-T05 [US1] Store tests: save → load round trip; injected failure at each step before `replaceMain` keeps the old main file readable; a leftover partial temporary file is removed and never read; at least one complete scene exists after a failure at any step in Apps/projectM-iOS/Tests/SceneAutosaveStoreTests.swift
- [ ] SCN-002-T06 [US1] Coordinator (main actor): restore at launch, Observation tracking of `SceneInputs`, revisions, commits on the serial queue, triggers A4 (visual change at once, Settings closing, background task, synchronous terminate), DEBUG probe value and launch arguments in Apps/projectM-iOS/Coordinators/SceneAutosaveCoordinator.swift
- [ ] SCN-002-T07 [US1] Wire into Apps/projectM-iOS/Coordinators/AppCoordinator.swift (create and restore before UI-test seeds, `-uitestResetNotice` removes the folder, commit when Settings closes, apply restored bindings to the native spectrum), Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift (`bindings`), Apps/projectM-iOS/Views/VisualizerView.swift (probe `sceneAutosave`)
- [ ] SCN-002-T08 [US1] Restore round trip test: capture → save → load → live state and restored values equal; restore is not an edit in Apps/projectM-iOS/Tests/SceneAutosaveCaptureTests.swift
- [ ] SCN-002-T09 [US1] Acceptance UI test: Circular Spectrum, 16 bars, close Settings, wait for `pending=0`; reopen, 32 bars, `terminate()` before the commit (long quiet via launch argument); relaunch → `restored=main`, 16 bars selected, in Apps/projectM-iOS/UITests/SceneAutosaveUITests.swift
- [ ] SCN-002-T10 [US1] {device} On D1 (Debug build): Circular Spectrum, 16 bars, close Settings; reopen, 32 bars, force-quit from the app switcher at once; relaunch: a committed value (32 expected, the switcher passes through the background), never 64, visual draws (quickstart D)

## Phase 4: User Story 2 — saving never gets in the way (P1)

**Independent test**: with a fake clock a burst gives one write; continuous edits commit within 5 s.

- [ ] SCN-002-T11 [US2] Debouncer and coordinator tests with a fake clock: ten edits 0.1 s apart → one commit 1 s after the last; edits every 0.5 s → a commit at 5 s; a commit-now trigger commits a pending edit at once; nothing pending → no write in Apps/projectM-iOS/Tests/SceneAutosaveDebouncerTests.swift and Apps/projectM-iOS/Tests/SceneAutosaveCoordinatorTests.swift

## Phase 5: User Story 3 — a damaged file never stops the app (P2)

**Independent test**: truncated main → backup; both damaged → nothing restored and an event.

- [ ] SCN-002-T12 [US3] Store tests: truncated, non-JSON, newer-version and error-bearing main files fall back to the backup with `mainUnreadable` + `restoredFromBackup`; both damaged → `nothingRestored`; a newer-version main file is moved to `current.scene.newer` and never overwritten; a save after a fallback never replaces the good backup with the damaged main file in Apps/projectM-iOS/Tests/SceneAutosaveStoreTests.swift

## Phase 6: User Story 4 — content this version does not understand is kept (P3)

**Independent test**: unknown layer, document field and orphaned binding survive the next save.

- [ ] SCN-002-T13 [US4] Capture tests: unknown layer kept at its index (renumbered on collision, dropped beyond 8 with an event), unknown document field, unknown asset type, orphaned binding, modulation section, ID and name survive a capture; Camera records the visual before it; no photo stored → no photo layer in Apps/projectM-iOS/Tests/SceneAutosaveCaptureTests.swift

## Phase 7: Polish

- [ ] SCN-002-T14 [P] ADR-0028 amendment (SCN-002: files, save sequence, which wins at launch, carry) in docs/adr/0028-scene-document-format.md
- [ ] SCN-002-T15 [P] Privacy policy stored-data list (scene files) in docs/privacy-policy.md; `check_privacy_manifest.py` on the Debug app
- [ ] SCN-002-T16 Regression: `projectM-iOSTests`, `SceneAutosaveUITests`, `TextOverlayUITests`, `GlowUITests`, `PhotoLayerUITests` on the dedicated simulator; `check_compliance.py`, `validate_docs.py`; PosterBoard count before and after

## Dependencies

T01 → T04 (text asset). T02, T03, T04 in parallel → T06 → T07 → T09. T05, T08, T11, T12, T13 after
their component. T14, T15 any time. T16 last. T10 after T07 (owner, device).

## Parallel example

T02, T03 and T04 touch different new files and can be written together; T14 and T15 are docs.

## Implementation strategy

MVP = Phases 1-3 (atomic store, capture, coordinator, kill-and-relaunch). Then US2 timing tests, US3
fallback tests, US4 merge tests, polish.
