# Tasks: PRE-009 Preset Comparison

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/preset-comparison.md](contracts/preset-comparison.md), [quickstart.md](quickstart.md)

**Tests**: requested by the spec (S1-S4). Budgets (owner rule 7): unit tests about 1-2 s, UI tests under 30 s.

## Phase 1: Setup

- [ ] PRE-009-T01 Create the private simulator "PRE9 iPhone 17" (iOS 27.2), run `xcodegen generate` in the worktree, and confirm `Build` and `Vendor/presets/*` are present (quickstart step 1)

## Phase 2: Foundational (shared lockstep types)

- [ ] PRE-009-T02 Add `PresetComparisonTick`, `PresetComparisonTimeline` ("`frameTime = index / rate`; `firstSample` = sum of earlier ticks' frame counts"), `PresetComparisonBatch`, `PresetComparisonMailbox` (thread-safe, "cap 6", drops the oldest, `take` joins all waiting ticks), `PresetComparisonDelivery` (FNV-1a checksum), `PresetComparisonRecorder`, `PresetComparisonConfiguration`, `PresetComparisonEvent`/`Frame` and the `PresetComparing` protocol, plus `VisualizerRenderer.presetComparison` and `sharedPCMReader` (default nil) in `Packages/Rendering/Sources/Rendering/PresetComparison.swift` and `VisualizerRenderer.swift`
- [ ] PRE-009-T03 [P] Unit tests for the timeline (contiguous indexes, sample ranges, frame times) and the mailbox (joins in order, last frame time, cap drops the oldest and counts them, empty take is nil) in `Packages/Rendering/Tests/RenderingTests/PresetComparisonTimelineTests.swift`

## Phase 3: User Story 2 - identical sample timestamps (P1, acceptance)

**Independent test**: `PresetComparisonRunnerTests` with real engines off screen.

- [ ] PRE-009-T04 [US2] Implement `PresetComparisonRunner` (one worker thread, two unshared EGL contexts and engines, per-side flash limiter into a 320 × 180 BGRA target, batch → record → feed in `maxSamplesPerFrame` chunks → `setFrameTime` → draw → read back, A then B; load failures per side; stop and suspension; test hook `slowSide`) in `Packages/ANGLERendering/Sources/ANGLERendering/PresetComparisonRunner.swift`
- [ ] PRE-009-T05 [US2] Expose the runner and the attached reader from `ANGLERenderer`, stop the runner on PERF-011 suspension, memory pressure and deinit in `Packages/ANGLERendering/Sources/ANGLERendering/ANGLERenderer.swift`
- [ ] PRE-009-T06 [US2] Acceptance tests (S1-S3): identical delivery records for A and B over at least 30 ticks; with B slowed, at least one merged batch and still identical records covering every kept sample once; the same preset as A and B gives identical pixels, in `Packages/ANGLERendering/Tests/ANGLERenderingTests/PresetComparisonRunnerTests.swift`

## Phase 4: User Story 1 - compare two presets live (P1, MVP UI)

**Independent test**: `PresetCompareUITests` opens Compare and chooses B.

- [ ] PRE-009-T07 [US1] `PresetComparisonModel` (pending pick, session, tick driver at 30/15 fps reading `sharedPCMReader` on the main actor with the PRE-001 test signal when silent, panes with loading/showing/failed and the 20 s limit, main visual pause/resume hooks, announcements) in `Apps/projectM-iOS/Coordinators/PresetComparisonModel.swift`
- [ ] PRE-009-T08 [US1] Wiring in `Apps/projectM-iOS/Coordinators/AppCoordinator+Comparison.swift` (preset contents as PRE-001, renderer, safety clamp, pause and `resumeActiveVisual`) and one line in `AppCoordinator.swift`; `PresetCoordinator.comparison`
- [ ] PRE-009-T09 [US1] UI: row menu "Compare…"/"Compare with <A>" and VoiceOver action, the pick bar and the Compare sheet (side by side when wide, stacked when tall; Play A/B; Close; test-signal note) in `Apps/projectM-iOS/Views/PresetCompareView.swift` and small edits in `Apps/projectM-iOS/Views/PresetBrowserView.swift`
- [ ] PRE-009-T10 [P] [US1] Model unit tests (pick rules, same preset refused, cancel, choose calls back with the pick's scope, tick stamping with a fake runner, silence uses the test signal, pause/resume) in `Apps/projectM-iOS/Tests/PresetComparisonModelTests.swift`
- [ ] PRE-009-T11 [US1] UI test (S4): Compare… on one preset, Compare with … on another, sheet shows both names, Play B makes B current, in `Apps/projectM-iOS/UITests/PresetCompareUITests.swift`

## Phase 5: User Story 3 - limits (P2)

- [ ] PRE-009-T12 [US3] Compare offered only where PRE-010's `canPreview` holds (flagged under Reduce flashing, locked, excluded and the current preset are not offered); the flash clamp reaches both previews; covered by T10 and T06
- [ ] PRE-009-T13 {device} [US3] S5 on D1: 60 s comparison with music, previews near their rate, thermal state not above fair, main visual resumes on Close; record in `docs/test-reports/performance.md`

## Phase 6: Polish

- [ ] PRE-009-T14 Repo checks (`check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`, `test_scripts`), privacy manifest and network symbol checks on the Debug app, Xcode 26 type-check budget flags; spec status; delete the simulator and derived data

## Dependencies

T01 → T02 → (T03, T04) → T05 → T06; T02 + T05 → T07 → T08 → T09 → (T10, T11); T12 after T09; T13 after all; T14 last.
MVP: Phases 1-4 (acceptance and the Compare sheet).
