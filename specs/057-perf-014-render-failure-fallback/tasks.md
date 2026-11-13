# Tasks: PERF-014 Render Failure Fallback

**Input**: design documents in `specs/057-perf-014-render-failure-fallback/` (spec, plan, research,
data-model, contracts/render-health.md, quickstart).

**Tests**: requested by the spec (PERF-014-S1 to S6) and the brief; budgets follow owner rule 7
(unit test about 1-2 s, ≤ 10 s; suite < 1 min; UI test < 30 s).

Format: `- [ ] PERF-014-Tnn [P?] [US?] description (file)`. `{device}` = needs the owner's hands and
physical devices; left open.

## Phase 1: Foundational (blocks every story)

- [X] PERF-014-T01 [P] Fault model in plain Swift per data-model.md: `RenderFaultReason` (11 cases, String raw values), `RenderRecoveryPolicy` (firstDelayTicks 30 "> 0", maxRetries 4 "≥ 0", `delay(afterRetries:)` = 30 << n), `RenderRetryState` (transition table of data-model.md; `fault` returns whether counted; `isHolding`, `isRetryDue`, `beginRetry`, `succeeded(encodedAt:)` returns whether a recovery, `reset(atTick:)`), `RenderHealthState` and `RenderHealth` (state derivation `state(layers:visual:)`, `recordFault`, `recordRecovery`, `setState`, `revision`, `summary(visual:)`, `debugValue`), `RenderFaultInjection` (fields and `parse(_:)`), in `Packages/Compositor/Sources/Compositor/RenderHealth.swift` — Verified 2026-11-13: `swift test --package-path Packages/Compositor --filter RenderHealthTests` 7/7 (0.003 s) on the macOS host; also in the Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`) 7/7
- [X] PERF-014-T02 [P] Fault model tests (host and Linux shape, no Metal): retry ticks 30/90/210/450 then given up and no retry in the next 1,000 ticks (S3); coalescing while waiting/given up; recovery only for work encoded after the retry began; reset retries at once with a fresh budget; state derivation table; summary and debug text carry identifiers and counts only; injection parsing (known items, unknown ignored), in `Packages/Compositor/Tests/CompositorTests/RenderHealthTests.swift` — Verified 2026-11-13: RenderHealthTests 7/7 on the macOS host and in the Linux shape (no Metal, no clock)
- [X] PERF-014-T03 [P] Diagnostics event `DiagnosticsLog.renderFault(_ summary:)` (one Points of Interest event "Render fault" plus one private app log line) and its test, in `Packages/Diagnostics/Sources/Diagnostics/Logging.swift`, `Packages/Diagnostics/Tests/DiagnosticsTests/RenderFaultLogTests.swift` — Verified 2026-11-13: `swift test --package-path Packages/Diagnostics` 12 tests, 0 failures (RenderFaultLogTests 1)

## Phase 2: User Story 1 - A broken part of the picture never freezes the app (P1)

**Goal**: layer faults and preset load failures are recorded, bounded and recovered; the frame loop keeps ticking.
**Independent test**: inject each layer fault into a running compositor: ticks advance, other layers draw, retries at back-off ticks only, recovery when cleared.

- [ ] PERF-014-T04 [US1] Compositor layer recovery: `frameTicks`, `health`, `recoveryPolicy`, per-layer `RenderRetryState`; prepare failure → `layerPrepareFailed`, picture creation failure → `missingTexture`, serious render error (`resourceUnavailable`, `engineFailure`, `unsupportedPicture`) → `layerRenderFailed` with the layer held (no render call) until due; routine `notReady`/`frameSkipped` unchanged (D4); due → re-prepare (pictures again if missing); `resetRenderHealth()` (and `retryUnavailableLayers()` = reset); size change resets layer parts; DEBUG `faultInjection` (prepare, picture, render by layer name), in `Packages/Compositor/Sources/Compositor/Compositor.swift`
- [ ] PERF-014-T05 [US1] Layer fault tests on the Mac's Metal device (64 × 64): per kind (prepare, picture, render) the reason is recorded at the fault's tick with count 1 (S1); ticks advance every frame and the other layer keeps drawing (S2); prepare/render calls happen only at ticks 30, 90, 210, 450 and not in the next 1,000 frames (S3); clearing the injection before a retry recovers it there (S4; state healthy, recoveries 1); `.notReady` every frame is not a fault; reset after giving up retries at once; while a layer is held at a steady size `pictureAllocations` and `layerPreparations` change only at retry ticks (R12); existing FallbackRenderTests unchanged, in `Packages/Compositor/Tests/CompositorTests/RenderFaultRecoveryTests.swift`
- [ ] PERF-014-T06 [US1] projectM preset load failures: `ANGLERenderer.health`, `displayTicks`, `onRenderHealthChange`; `setPreset` records `presetLoadFailed` (state unchanged) and rethrows; DEBUG `faultInjection.failPresetLoads` throws a `PMEngineErrorDomain` preset-load error before the engine sees the preset; `ANGLERendering` target depends on the `Compositor` product, in `Packages/ANGLERendering/Package.swift`, `Packages/ANGLERendering/Sources/ANGLERendering/ANGLERenderer.swift`
- [ ] PERF-014-T07 [US1] Compositor hosts: `compositor.resetRenderHealth()` where the frame loop starts (beside `resetFlashHistory()`), report `compositor.health` through `onRenderHealthChange` when its revision changes (checked every tick before the encode guard), `renderTicks`, in `Apps/projectM-iOS/Visuals/CameraVisualHost.swift`, `PhotoVisualHost.swift`, `VideoVisualHost.swift`, `TextVisualHost.swift`
- [ ] PERF-014-T08 [US1] App routing: `AppCoordinator` keeps `renderHealthRevision` (observable), `activeRenderHealth` (shown visual), `visualCreationHealth` (records `visualUnavailable` in `markNativeVisualUnavailable`, VIS-001-R16 unchanged), wires host and renderer callbacks, logs `DiagnosticsLog.renderFault(summary)` when a record's fault or recovery count changes; DEBUG: arms every new compositor visual and the renderer from `-uitestRenderFaults <list>`, `clearRenderFaults()`, `activeRenderTicks`, in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`
- [ ] PERF-014-T09 [P] [US1] projectM fault tests on the simulator: an injected preset load failure is recorded (`presetLoadFailed`, count 1, state healthy) and rethrown; a real unloadable preset (garbage bytes) records the same reason, in `Packages/ANGLERendering/Tests/ANGLERenderingTests/ANGLERenderFaultTests.swift`
- [ ] PERF-014-T10 [US1] App test: Photo host made with an injected photo prepare failure renders offscreen: reason `layerPrepareFailed`, `renderTicks` advance, the spectrum still renders (`framesComposited` advances), the coordinator-style callback fires once per revision; clearing the injection recovers the photo at its retry (`framesShown` advances); a VIS-001-R16 failure is recorded as `visualUnavailable`, in `Apps/projectM-iOS/Tests/RenderFaultAppTests.swift`

## Phase 3: User Story 2 - A visual that cannot draw at all shows a calm placeholder (P1)

**Goal**: GPU errors and projectM presentation failures back off and end on a placeholder that never flashes.
**Independent test**: persistent injected GPU fault → black during back-off, placeholder after the retries, flash analysis ≤ 1 transition per switch, recovery after a reset.

- [ ] PERF-014-T11 [US2] Compositor visual part: fixed ring of the last three command buffers with their tick (D2), status polled at the start of each call (`.completed` → success, `.error` → reason from `MTLCommandBufferError.Code`), missing composite texture → `missingTexture` with back-off (no allocation attempt while holding), black frame (no layer renders) while holding, `health.state` derived each tick; DEBUG `faultInjection.gpuFault` makes finished buffers read as errors, in `Packages/Compositor/Sources/Compositor/Compositor.swift`
- [ ] PERF-014-T12 [US2] GPU fault tests: an injected GPU timeout (and page fault, not permitted) is recorded with its reason once although three in-flight buffers report it (coalesced); output is black during the back-off (pixel read) while ticks advance; after the last retry the state is placeholder; clearing then `resetRenderHealth()` recovers (state healthy, layers drawn); a success from a buffer encoded before the retry does not count; the composite flash check: a white layer switching to its transparent fallback produces at most one transition per window in `FlashAnalysis` of the read-back luminance (S5), in `Packages/Compositor/Tests/CompositorTests/RenderFaultRecoveryTests.swift`
- [ ] PERF-014-T13 [US2] projectM presentation faults: swap result checked (DEBUG `failPresentation` reads it as failed) → `presentationFailed` with tick back-off (no render while holding), the window surface recreated at each retry, placeholder after the last retry, reset in `resume()` and `resumeForPresentation()`; the display-link tick path is `presentationTick()` (internal, testable), in `Packages/ANGLERendering/Sources/ANGLERendering/ANGLERenderer.swift`
- [ ] PERF-014-T14 [P] [US2] projectM presentation tests on the simulator (renderer view in a window): injected swap failure → reason, renders only at retry ticks, placeholder after the last retry, ticks advance; cleared + `resume()` → healthy and frames presented again, in `Packages/ANGLERendering/Tests/ANGLERenderingTests/ANGLERenderFaultTests.swift`
- [ ] PERF-014-T15 [US2] Placeholder: `RenderPlaceholder` (fadeSeconds 0.5, `opacity(elapsed:)` linear and clamped, note "Visual unavailable") and `RenderPlaceholderView` (black, small grey note, accessibility label and identifier `renderPlaceholder`); `VisualizerView` shows it over the visual while `showsRenderPlaceholder`, with a linear 0.5 s opacity animation, in `Apps/projectM-iOS/Visuals/RenderPlaceholder.swift`, `Apps/projectM-iOS/Views/VisualizerView.swift`
- [ ] PERF-014-T16 [US2] Placeholder flash test: `L × (1 − opacity)` at 60 fps for a white picture through fade-in, hold and fade-out: one transition per switch, at most one per 1 s window (S5); `showsRenderPlaceholder` only for the placeholder state of the shown visual, in `Apps/projectM-iOS/Tests/RenderFaultAppTests.swift`

## Phase 4: User Story 3 - The reason is recorded where a developer can see it (P2)

**Goal**: the overlay, the log and a DEBUG readout show the health.
**Independent test**: after an injected fault the readout names the reason; the overlay shows a render line.

- [ ] PERF-014-T17 [US3] FR-048 overlay: a `render: <debugValue>` line (identifier `overlayRender`) when the shown visual's record has a fault or is not healthy, in `Apps/projectM-iOS/Views/PerformanceOverlay.swift`, `Apps/projectM-iOS/Views/VisualizerView.swift`
- [ ] PERF-014-T18 [US3] DEBUG probe under `-uitestRenderFaults <list>`: readouts `renderHealth` (active record's debug value), `renderFaults` (count), `renderTicks`, `visualFrames`, button `faults:clear`; Release builds exclude it (`#if DEBUG`), in `Apps/projectM-iOS/Debug/UITestRenderFaultPanel.swift`, `Apps/projectM-iOS/Views/VisualizerView.swift`
- [ ] PERF-014-T19 [US3] UI test (S6): launch with `-uitestRenderFaults prepare:photo,preset:1` and a seeded photo; projectM: frames advance, `renderHealth` names `presetLoadFailed`; choose Photo through Settings (opens and closes promptly); `renderHealth` names `layerPrepareFailed`, `renderTicks` advance; open and close Settings again; `faults:clear` → the photo recovers (`visualFrames` advances); `sourceStarts` stays "1"; < 30 s, in `Apps/projectM-iOS/UITests/RenderFaultUITests.swift`

## Phase 5: Polish and cross-cutting

- [ ] PERF-014-T20 Regression runs: Compositor (`swift test` host, Linux shape, `xcodebuild test -scheme Compositor` once), Diagnostics, ANGLERendering (fault and existing suites) on the simulator, app `-only-testing:projectM-iOSTests` + RenderFaultUITests, NativeVisualUITests, CameraUITests, GlowUITests; `check_compliance.py`, `validate_docs.py`; PosterBoard reports counted before and after
- [ ] PERF-014-T21 Docs: spec status and an Evidence section in this file (what is real vs injected, counts, durations)
- [ ] PERF-014-T22 {device} D1 (iOS 27) and D3 (iPadOS 26.5), Debug build with `-uitestRenderFaults prepare:photo,preset:1,gpu:gpuTimeout`: no hang, controls respond, overlay shows the reason, "Render fault" events in Console, the placeholder fades in after the GPU retries and goes after pause/resume with the fault cleared (quickstart E)

## Analysis (speckit-analyze, 2026-11-13)

No CRITICAL or HIGH finding; constitution aligned (I, VI, VII, X, privacy). Applied: R12 (no work outside retry ticks) made testable in T05 (allocation and prepare counters); R2's "frame clock" made precise as the visual's frame ticks (research D1) in the spec. Coverage: R1 T01/T02; R2 T01/T04/T06; R3-R5 T04/T05; R6 T04/T05/T12/T13/T14; R7 T11/T12; R8 T06/T09; R9 T13/T14; R10 T15/T16; R11 T08/T10; R12 T05/T12/T19; R13 T03/T08; R14 T17/T18; R15 T04/T06/T11/T13/T18; R16 T12. S1-S6 each have a task; S7 is T22 `{device}`. Low: the native spectrum's runtime GPU errors are out of scope by decision (Clarifications Q4), recorded, not a gap.

## Dependencies

T01 → T02, T04, T06, T11, T13; T03 before T08; T04 → T05, T07; T07, T06 → T08 → T10, T15-T19;
T11 → T12; T13 → T14; T15 → T16; T20-T21 last; T22 needs the owner and devices.

## Parallel opportunities

T01/T03 (different packages); T09 and T14 (one ANGLE test file, after T06/T13) alongside the app tasks;
T05/T12 share a file (one writer, sequential).

## Implementation strategy

MVP = Phase 1 + US1 (layer faults, preset failures, recorded reason). US2 adds the GPU watch and the
placeholder; US3 the visible readouts and the end-to-end UI test.
