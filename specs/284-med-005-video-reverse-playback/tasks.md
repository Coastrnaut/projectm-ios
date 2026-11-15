# Tasks: MED-005 Video Reverse Playback

**Input**: Design documents from `specs/284-med-005-video-reverse-playback/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/video-reverse.md, quickstart.md

Tests are part of the acceptance criterion ("Short fixture reverses frame order and unsupported
clips show clear error"), so each story carries its tests. Budgets (owner rule 7): unit tests
about 1-2 s, a UI test under 30 s, no wall-clock assertions (injected presentation times).

## Phase 1: Setup

- [ ] MED-005-T01 Add the `ImageLayer` dependency to the `VideoLayer` target in Packages/Compositor/Package.swift (for `AnimatedFrameBudget`)

## Phase 2: Foundational (plain Swift rules)

- [ ] MED-005-T02 Implement `VideoReverseLimits` (30 s, longest side ≤ 1920, shortest side ≤ 1080, 30 pictures/s), `VideoReverseUnsupported` with the contract C3 messages, `VideoReversePlan` ("(maxPictures + 2) × accounted ≤ budget", never larger than the clip), `VideoReverseTimeline` (research D4), `VideoReverseFrameStore` (no eviction, peak) and `VideoReverseCacheBuilder` with the `VideoReverseDecoding` seam in Packages/Compositor/Sources/VideoLayer/VideoReversePlayback.swift
- [ ] MED-005-T03 [P] Pure tests with a fake decoder (plan limits and messages, budget for the largest shape on each device class, selection order, wrap, region, start offset, decimation of 60/s, peak ≤ budget, cancel, zero pictures = undecodable) in Packages/Compositor/Tests/CompositorTests/VideoReverseTests.swift

## Phase 3: User Story 1 - Play a short clip backwards (P1)

**Goal**: reverse a supported stored clip through the real compositor.
**Independent test**: a generated 12-picture clip reads back 11…0 then wraps to 11.

- [ ] MED-005-T04 [US1] Implement `AVReverseFrameDecoder` (container check, probe, 32BGRA reader, nearest downsample into a shared `.bgra8Unorm_srgb` texture) in Packages/Compositor/Sources/VideoLayer/AVReverseFrameDecoder.swift
- [ ] MED-005-T05 [US1] Implement `VideoReverseDriver` (background build, try-lock state, main-actor notifications, cancel) in Packages/Compositor/Sources/VideoLayer/VideoReverseDriver.swift
- [ ] MED-005-T06 [US1] Add `reverse`, `reverseLimits`, `reverseBudgetBytes`, `reverseState`, `onReverseStateChange`, `reverseShownIndex`, `reversePeakBytes` to `VideoLayerSource`; stop/restart the forward decoder; shared draw; suspend/resume and new content in Packages/Compositor/Sources/VideoLayer/VideoLayerSource.swift
- [ ] MED-005-T07 [US1] Layer acceptance: 12-picture fixture in descending order at the expected times, wrap, region, off resumes forward at the shown picture, in Packages/Compositor/Tests/CompositorTests/VideoReverseLayerTests.swift
- [ ] MED-005-T08 [P] [US1] `VideoStore` reverse key `settings.video.reverse` = `{id}` (read only for its id, cleared by a new video and Remove Video) in Apps/projectM-iOS/Coordinators/VideoStore.swift; `AppSettings.videoReverseKey` in `allKeys` in Apps/projectM-iOS/Coordinators/AppSettings.swift
- [ ] MED-005-T09 [P] [US1] Backup exclusion and media erase of `settings.video.reverse` in Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift and LibraryErasePolicy.swift; `ALLOWED_KEYS` in scripts/run_device_tests.py; written-keys list in Apps/projectM-iOS/Tests/SettingsTests.swift
- [ ] MED-005-T10 [US1] `VideoCoordinator` reverse (`reverse`, `setReverse`, `onReverseChange`, `reverseState`, `reverseCaption`, `reverseStateChanged`) in Apps/projectM-iOS/Coordinators/VideoCoordinator.swift
- [ ] MED-005-T11 [US1] `VideoReverseControls` toggle and caption (Apps/projectM-iOS/Views/VideoReverseControls.swift), placed under Speed in Apps/projectM-iOS/Views/SettingsView.swift
- [ ] MED-005-T12 [US1] Wire `VideoVisualHost.reverse` / `onReverseStateChange` / `reverseProbe()` (Apps/projectM-iOS/Visuals/VideoVisualHost.swift), `AppCoordinator` (Apps/projectM-iOS/Coordinators/AppCoordinator.swift) and the `videoReverse` probe (Apps/projectM-iOS/Views/VisualizerView.swift)
- [ ] MED-005-T13 [US1] App tests (persistence across a relaunch, cleared by a new video and Remove Video, foreign values removed, coordinator applies at once, keys listed for reset/backup/erase) in Apps/projectM-iOS/Tests/VideoReverseAppTests.swift
- [ ] MED-005-T14 [US1] UI test: seeded counter clip, Reverse on in Settings → Video, probe `playing` with a decreasing index, in Apps/projectM-iOS/UITests/VideoReverseUITests.swift

## Phase 4: User Story 2 - Unsupported clips say so (P1)

**Independent test**: an over-limit clip and a corrupt clip give their message; forward continues.

- [ ] MED-005-T15 [US2] Layer tests: a 2 s clip with a 1 s duration limit reports `.tooLong` and the forward picture keeps advancing; a corrupt copy reports `.undecodable` without a crash, in Packages/Compositor/Tests/CompositorTests/VideoReverseLayerTests.swift
- [ ] MED-005-T16 [US2] App test: an unsupported state sets the caption to the message, announces it once, and Reverse off or a new video clears it, in Apps/projectM-iOS/Tests/VideoReverseAppTests.swift

## Phase 5: User Story 3 - Memory stays bounded (P2)

- [ ] MED-005-T17 [US3] Real-file peak: a small budget build records `reversePeakBytes` ≤ budget; suspend releases and resume rebuilds, in Packages/Compositor/Tests/CompositorTests/VideoReverseLayerTests.swift

## Phase 6: Polish

- [ ] MED-005-T18 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), type-check budget, privacy manifest and network symbols on the Debug app
- [ ] MED-005-T19 Report docs/test-reports/video-reverse-playback.md and spec status
- [ ] MED-005-T20 {device} On D1 and D3: a 30 s 1080p clip reverses after preparation within the device class budget (Xcode memory gauge), and a 2-minute clip shows the 30-second message while playing forward

## Dependencies

T01 → T02 → T03; T02 → T04 → T05 → T06 → T07, T15, T17. T08, T09 independent of the package
work; T10 → T11, T12 → T13, T14, T16. T18, T19 last; T20 needs a person and a device.

## Parallel examples

- T03 with T04 (different files); T08 with T09 (store and backup policy).

## Implementation strategy

MVP is US1 (package T01-T07, then the app T08-T14); US2 and US3 add tests on the same code.
