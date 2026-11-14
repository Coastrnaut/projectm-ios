# Tasks: SHOW-006 Cue Rehearsal Mode

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/cue-rehearsal.md](contracts/cue-rehearsal.md), [quickstart.md](quickstart.md)

**Tests**: requested by the spec (S1-S4, owner rule 7 budgets: unit ≤ 10 s, UI < 30 s).

## Phase 1: Setup

- [X] SHOW-006-T01 Create simulator "SHOW6 iPhone 17" (iOS 27.2), run `xcodegen generate`, record PosterBoard report count before runs — Verified 2026-11-14: simulator CABBD4EF (iOS 27.2) created, `xcodegen generate`; PosterBoard reports 26 before and after

## Phase 2: Foundational (target model)

- [X] SHOW-006-T02 Add `ShowCueList.nextCue` (the cue Next would reach; nil at end, empty or all skipped) in Packages/ShowControl/Sources/ShowControl/ShowCueList.swift — Verified 2026-11-14: `swift test --package-path Packages/ShowControl` (123 tests, 1.6 s)
- [X] SHOW-006-T03 Add `ShowRehearsalTarget` (`.followNext`, `.picked(UUID)`; `resolve(in:)` falls back to `nextCue` when a picked cue is gone; `stepped(by:in:)` picks the cue `delta` places from the resolved one, clamped, skipped cues included; never changes the list) in Packages/ShowControl/Sources/ShowControl/ShowRehearsalTarget.swift — Verified 2026-11-14: `ShowRehearsalTargetTests` (3 tests)
- [X] SHOW-006-T04 [P] Package tests (next, skipped, end, picked, removed pick, stepping, empty) in Packages/ShowControl/Tests/ShowControlTests/ShowRehearsalTargetTests.swift — Verified 2026-11-14: `swift test --package-path Packages/ShowControl`: 123 tests pass, 1.6 s

## Phase 3: User Story 1 - See the next cue before it goes live (P1) — MVP

**Independent test**: rehearsal on with three cues: the panel names cue 2 with its picture; live state unchanged.

- [X] SHOW-006-T05 [US1] `ShowCoordinator.rehearsalScene(of:)` (reads and decodes a cue's stored scene, validates it with SCN-001 `liveState`; never applies, never writes; unreadable → nil) in Apps/projectM-iOS/Coordinators/ShowCoordinator.swift — Verified 2026-11-14: `CueRehearsalTests` (5 tests, 0.05 s) on SHOW6 iPhone 17
- [X] SHOW-006-T06 [P] [US1] `CueRehearsalRendering` protocol and the REC-002 adapter (`SnapshotStillRenderer.renderPixels` at 320 × 180 → `CGImage`, detached) in Apps/projectM-iOS/Visuals/CueRehearsalRenderer.swift — Verified 2026-11-14: `CueRehearsalAcceptanceTests` renders through it on the simulator GPU (renderCount ≥ 4)
- [X] SHOW-006-T07 [US1] `CueRehearsalCoordinator` (isOn, target, load, draft from live values overlaid with the scene's values, picture rendered / stored / message, coalesced renders: one in flight, newest wins, ≥ 100 ms between starts via injected sleep; announcements on the cue lane) in Apps/projectM-iOS/Coordinators/CueRehearsalCoordinator.swift — Verified 2026-11-14: `CueRehearsalTests` (coalescing: load + 3 edits → 1 render, newest wins; no render while off)
- [X] SHOW-006-T08 [US1] Wire `cueRehearsal` in Apps/projectM-iOS/Coordinators/AppCoordinator.swift (one lazy line) and `makeCueRehearsal()` in Apps/projectM-iOS/Coordinators/AppCoordinator+Show.swift — Verified 2026-11-14: Debug build-for-testing exit 0; `CueRehearsalUITests` drives it in the app
- [X] SHOW-006-T09 [US1] Panel view (title, picture with VoiceOver label, previous/next target, close; `.task(id:)` reload on the resolved cue) in Apps/projectM-iOS/Views/CueRehearsalPanel.swift; Rehearse toggle `showRehearse` in Apps/projectM-iOS/Views/ShowControls.swift; one line in `topStatus` of Apps/projectM-iOS/Views/VisualizerView.swift — Verified 2026-11-14: `CueRehearsalUITests` (7.5 s): panel names "Cue 2, Build", show stays on cue 1
- [X] SHOW-006-T10 [US1] Unit tests (target follows a step, skipped next, end of show, stored picture for projectM, unreadable scene, render coalescing with a fake renderer, no render while off, cue-lane announcements) in Apps/projectM-iOS/Tests/CueRehearsalTests.swift — Verified 2026-11-14: `CueRehearsalTests` 5/5 pass (0.05 s)

## Phase 4: User Story 2 - Tweak the cue in a sandbox (P1)

**Independent test**: draft edits re-render only; Save to Cue writes only the scene file; locked refuses.

- [X] SHOW-006-T11 [US2] `ShowCoordinator.saveRehearsal(cueID:parameters:)` (an edit: refused while locked; overlays the seven values on the stored document, `store.saveScene`, `sceneFilesChanged`; never `applyScene`) in Apps/projectM-iOS/Coordinators/ShowCoordinator.swift — Verified 2026-11-14: `testSaveWritesTheSceneFileOnlyAndTheCueAppliesItLater`
- [X] SHOW-006-T12 [US2] Draft editing (`setDraft`, `revert`, `saveDraft`, close drops the draft) in CueRehearsalCoordinator and the Edit section (glow switch, intensity, radius, threshold, bar count, linear spacing; `.accessibleParameter` sliders; Save to Cue, Revert) in Apps/projectM-iOS/Views/CueRehearsalPanel.swift — Verified 2026-11-14: `CueRehearsalTests` (revert, close, lock) and `CueRehearsalAcceptanceTests` (edits through `editDraft`)
- [X] SHOW-006-T13 [US2] Unit tests (save writes the file and does not apply; stepping to the cue applies the saved values; revert; close drops; lock refuses) in Apps/projectM-iOS/Tests/CueRehearsalTests.swift — Verified 2026-11-14: `CueRehearsalTests` 5/5 pass
- [X] SHOW-006-T14 [US2] Acceptance (S1, S2): real panel + coordinator + offscreen renderer in the device window; external window snapshot byte-identical off / on / after three edits; Photo visual's captured frame and every recorded frame identical; live settings, position, applied scene, autosave revision and scene history unchanged, in Apps/projectM-iOS/Tests/CueRehearsalAcceptanceTests.swift — Verified 2026-11-14: `CueRehearsalAcceptanceTests` 2/2 pass (1.8 s): external snapshot byte-identical off/on/after 3 edits; still and 4/4 recorded frames identical (0 differing); settings, position, applied scene, autosave revision, history unchanged

## Phase 5: Polish

- [X] SHOW-006-T15 UI test (< 30 s): Rehearse shows the panel naming the next cue, the cue status is unchanged, the panel stays when the controls hide (R10), Close hides it, in Apps/projectM-iOS/UITests/CueRehearsalUITests.swift — Verified 2026-11-14: `CueRehearsalUITests` 1/1 pass (7.5 s)
- [X] SHOW-006-T16 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app, type-check budget, `LibraryBackupAppTests` (no new keys) — Verified 2026-11-14: compliance, validate_docs, motion policy, permission catalog, status events OK; test_scripts 177 OK; privacy manifest OK; network symbols OK; `LibraryBackupAppTests` pass (no new keys); `CueHoldSkipUITests` pass; new files under the type-check budget
- [ ] SHOW-006-T17 {device} On D1 with an external display: the projector and a recording do not change while rehearsing and editing; Save to Cue then stepping shows the new values

## Dependencies

T01 → T02 → T03 → T04; T05-T07 need T03; T08-T09 need T07; T10 after T09; T11-T12 after T07; T13-T14 after T12;
T15 after T09; T16 last; T17 needs a person and a device.

## Parallel opportunities

T04 with T05/T06; T06 with T05; T10 and T13 share a file (sequential).

## Implementation strategy

MVP = Phase 3 (preview only); Phase 4 adds the sandbox and the roadmap acceptance test.
