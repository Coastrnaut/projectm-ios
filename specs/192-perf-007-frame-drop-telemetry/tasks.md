# Tasks: PERF-007 Frame drop telemetry

**Input**: Design documents from `specs/192-perf-007-frame-drop-telemetry/`
**Tests**: requested by the brief (acceptance, session reset, per-output separation, unavailable, Linux shape, app test with an injected clock, export round trip).

## Phase 1: Setup

- [ ] PERF-007-T01 Confirm the baseline: `swift test --package-path Packages/Compositor --filter FrameTimingTests` passes before changes; `Build` symlink present; simulator "PERF7 iPhone 17" (iOS 27.2) created

## Phase 2: Foundational (the counter)

- [ ] PERF-007-T02 `FrameDropOutput`, `FrameDropSession`, `FrameDropTicket`, `FrameDropCounts` (with `recording(written:droppedSlots:)` and `line(for:)`) and the lock-free `FrameDropCounter` (contract C1) in Packages/Compositor/Sources/FrameTiming/FrameDropCounter.swift

## Phase 3: User Story 2 - Reset per session, never double-count (P1)

- [ ] PERF-007-T03 [US2] Acceptance tests in Packages/Compositor/Tests/FrameTimingTests/FrameDropCounterTests.swift: injected sequence → exact counts; duplicated presented reports and repeated timestamps counted once; out-of-order within the window counted once; session reset zeroes; late reports of the previous session excluded (stale); concurrent duplicate reports from several threads counted once
- [ ] PERF-007-T04 [P] [US2] Separation and unavailable tests: two counters (device, external) never affect each other; a session without presentation reports nil presented/late/discarded and the line reads "unavailable"; recording counts from written and dropped slots

## Phase 4: User Story 1 - Counts per output in the overlay (P1)

- [ ] PERF-007-T05 [US1] `FrameDropCounted` protocol and `track(_:link:)` drawable helper in Apps/projectM-iOS/Visuals/FrameDropCounting.swift; a `frameDrops` property and one call before `present` in the native spectrum, Camera, Photo, Video and Text hosts; `ANGLERenderer.frameDrops` (submit only) in Packages/ANGLERendering
- [ ] PERF-007-T06 [US1] `FrameDropAttachment` (device and external counters, session on attach, visual change, output change, overlay on) and `frameDropLines()` in Apps/projectM-iOS/Coordinators/AppCoordinator+FrameDrops.swift; lines appended in `frameStageLines()`, stop with `stopFrameStageTiming()`; recording line from `VideoRecordingCoordinator.currentStatistics`
- [ ] PERF-007-T07 [US1] Overlay: lines starting with "frames " in their own text (`overlayFrameDrops`) in Apps/projectM-iOS/Views/PerformanceOverlay.swift
- [ ] PERF-007-T08 [US1] App tests in Apps/projectM-iOS/Tests/FrameDropAppTests.swift: device counter driven with an injected clock (submit/presented events) gives exact counts; the attachment starts a new session on visual or output change and attaches the external counter when the visual is external; overlay split keeps "frames" lines apart

## Phase 5: User Story 3 - Export (P2)

- [ ] PERF-007-T09 [P] [US3] `DiagnosticsSnapshot.FrameDrops` (optional top-level `frameDrops`) in Packages/Diagnostics/Sources/Diagnostics/DiagnosticsSnapshot.swift; schema in specs/001-ios-projectm-visualizer/contracts/diagnostics-export.schema.json and the test resource copy
- [ ] PERF-007-T10 [US3] Round-trip and schema tests in Packages/Diagnostics/Tests/DiagnosticsTests/FrameDropsExportTests.swift; `AppCoordinator.exportFrameDrops`; automation perf001 adds `frameDrops`

## Phase 6: Polish

- [ ] PERF-007-T11 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), Linux shape (`swift build` of FrameTiming with no Apple-only API), type-check budget, privacy manifest and network symbols on the Debug app; PosterBoard counts
- [ ] PERF-007-T12 {device} On D1 with an external display: overlay shows `frames external` counting after the connection settles, the device counter stops; a recording line matches the recording's dropped slots

## Dependencies

T02 → T03, T04 → T05 → T06 → T07, T08. T09 → T10. T11 last.

## Implementation strategy

Counter and its tests first (the acceptance), then the app wiring, then the export.
