# Tasks: VIS-003 Waveform Oscilloscope

**Input**: Design documents in `specs/083-vis-003-waveform-oscilloscope/` (spec.md, plan.md,
research.md, data-model.md, contracts/waveform-oscilloscope.md, quickstart.md); ADR-0009, ADR-0010,
ADR-0011, ADR-0030.

**Tests**: test-first. Each test task comes before the code it covers; the red run (compile failure
or failing assertions) is recorded before the production change. Budgets (owner rule 7): a unit
test about 1-2 s (≤ 10 s) on the host, each package suite under 1 minute, a UI test under 30 s;
representative cases only.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. `[P]` = can run in parallel
(different files). Tags: `{device}` = needs a physical device, done only in the roadmap's final
device phase; `{sim}` = needs the feature's own iOS 27.2 simulator "VIS3 iPhone 17" (created for
this row, deleted afterwards). Inside descriptions "T07" is short for `VIS-003-T07`. A task is
ticked only when its acceptance evidence was produced, with " — Verified <date>: <how>" appended.
Logs go to `.build/scratch/`.

## Phase 1: Setup

- [X] VIS-003-T01 Record the baseline: `swift test --package-path Packages/VisualGenerators` on the host and in the Linux shape (`-Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`), `swift test --package-path Packages/RenderGoldens` on the host; `check_compliance.py`, `validate_docs.py`, `test_scripts.py`; PosterBoard report count. Evidence: counts recorded here. — Verified 2026-11-13: at 01c0388, VisualGenerators 103 tests on the host (25.4 s) and 81 in the Linux shape (8.7 s), RenderGoldens 35 tests on the host (1.9 s), 0 failures; check_compliance OK; validate_docs OK; test_scripts.py 147 tests OK; PosterBoard reports 32 (.build/scratch/vis003-T01-*.log).

## Phase 2: User Story 2 - stable sine cycles without allocation spikes (P1, the roadmap acceptance)

**Goal**: the stabilizer, the sample path and the generator. **Independent test**:
`WaveformTriggerTests`, `WaveformFrameBufferTests`, `WaveformTapTests`, `OscilloscopeLayoutTests`,
`OscilloscopeRenderTests`, `OscilloscopeGoldenTests`.

- [X] VIS-003-T02 [P] [US2] Write `Packages/VisualGenerators/Tests/VisualGeneratorsTests/WaveformFixtures.swift` (a continuous signal generator: sine, square, saw, DC offset, seeded white noise, silence; a rolling 4,096 history advanced by a deterministic varying count 700…770 per frame; the absolute index of each history sample) and `WaveformTriggerTests.swift`: sines 110 Hz, 440 Hz, 1 kHz at 44.1 kHz and 440 Hz at 48 kHz, square and saw at 220 Hz, sine + 0.3 DC, a 147 Hz wave with three rising crossings per period: over 60 frames the start phase (absolute time × f, mod 1, circular spread) varies < 0.01 cycle and the mode is `.triggered`; silence and noise → `.freeRun` with start = H − W every frame; the window always fits (start + W ≤ H); the period estimate of the 440 Hz sine is within 1 % of 100.2 samples; 1,000 frames leave capacities and buffer addresses unchanged (VIS-003-S1 to S3). — Verified 2026-11-13: written before the trigger; WaveformTriggerTests 6 tests; red run `cannot find type 'WaveformTriggerResult' in scope` (.build/scratch/vis003-red-T02.log).
- [X] VIS-003-T03 [US2] Record the T02 red run; implement `Packages/VisualGenerators/Sources/VisualGenerators/WaveformTrigger.swift` (contract C1; research VIS-003-D2). Evidence: T02 passes on the host and in the Linux shape. — Verified 2026-11-13: WaveformTriggerTests 6 pass on the host (1.30 s in all; the 8-fixture stability test 0.45 s, 1,000-frame storage test 0.77 s) and in the Linux shape (1.68 s). Worst start-phase spread over 60 frames: sines 1.9e-8 to 1.3e-5 cycle, square 9.1e-4 (edge between samples), saw 1.1e-10, DC offset 8.2e-7, 3-crossing wave 2.8e-14; silence and noise free-run on the newest window every frame. Two design fixes found by the tests, recorded in the spec: level = range midpoint (not the mean) and periodic spread ≤ 10 % (25 % let white noise pass at grouping 4) (.build/scratch/vis003-T03-*.log).
- [X] VIS-003-T04 [P] [US2] Write `WaveformFrameBufferTests.swift` (newest frame wins, nil when nothing new, `totalWritten` round-trips, a concurrent writer never yields a torn frame: every slot read is constant-valued) and `WaveformTapTests.swift` (bytes returned are exactly the wrapped reader's; the history holds the mid mix, newest last, with zeros before the first 4,096 samples; a session generation is forwarded, 0 without one; reads larger than the history keep only the newest 4,096). Record the red run. — Verified 2026-11-13: written before the code; red run `cannot find 'WaveformFrameBuffer' in scope` (.build/scratch/vis003-red-T04.log); WaveformFrameBufferTests 3 + WaveformTapTests 4, including the bands through `SpectrumBandFeed` bit-identical with and without the tap.
- [X] VIS-003-T05 [US2] Implement `WaveformFrameBuffer.swift` (VisualGenerators) and `Sources/VisualBandFeed/WaveformTap.swift` (contracts C2, C3). Evidence: T04 passes on the host and in the Linux shape. — Verified 2026-11-13: 7 tests pass on the host (0.82 s; 2,000-frame concurrent torn-frame check 0.71 s) and in the Linux shape (0.78 s) (.build/scratch/vis003-T05-*.log).
- [X] VIS-003-T06 [P] [US2] Write `OscilloscopeLayoutTests.swift`: configuration defaults and clamping (window 5…40 ms, thickness 0.001…0.05, amplitude 0.1…1, non-finite → default); P = min(W, 1,024) points spanning x 0…width; y of a sample s = H/2 − s·a·H/2 with NaN/∞ → 0 and |s| > 1 clamped; segment count P − 1, each a rectangle of the line thickness (≥ 1 px) with butt ends, a bevel triangle on the outer side of each turn (none on a straight run), every sample point inside the output; colors by palette index; tessellation 6 vertices per segment in NDC with the gain applied; zero size draws nothing; the 17 area levels equal a direct per-quad integration within 1e-6 and the whole frame equals Σ area·Y/A over the in-frame area. Record the red run. — Verified 2026-11-13: written before the code; red run: OscilloscopeLayoutTests fails to compile (`OscilloscopeConfiguration`, `OscilloscopeLayout` missing; .build/scratch/vis003-red-T06.log); 6 tests. The area check is independent of the model: each region supersampled 4 × 4 per pixel against the tiles (within 3 %).
- [X] VIS-003-T07 [US2] Implement `OscilloscopeConfiguration.swift` and `OscilloscopeLayout.swift` (`FlashRegionLayout`, `FlashAreaLevelSource`). Evidence: T06 passes on the host and in the Linux shape. — Verified 2026-11-13: OscilloscopeLayoutTests 6 pass on the host (1.48 s; 300-frame storage test 1.43 s) and in the Linux shape (1.51 s) (.build/scratch/vis003-T07-*.log). The storage test was cut from 1,000 to 300 frames (about 4 ms per frame in Debug with the area model; spec S3 updated).
- [ ] VIS-003-T08 [P] [US2] Write `OscilloscopeRenderTests.swift` (Metal; skips without a device): a 440 Hz sine rendered at 128 × 96: lit pixels lie within the predicted segment quads grown by 1 px, the centre column's line pixel is lit with the palette color within 2/255, the picture is identical for two histories that differ only by a whole number of periods of advance (stable cycles in pixels). Record the red run.
- [ ] VIS-003-T09 [US2] Implement `OscilloscopeGenerator.swift` (contract C4); one-sentence doc notes on `TextureGenerator` and `SpectrumTextureGenerator` that the input vector is the visual's input. Evidence: T08 passes on the host; the full VisualGenerators suite passes on the host and in the Linux shape with the T01 tests unchanged.
- [ ] VIS-003-T10 [US2] Write `Packages/RenderGoldens/Tests/RenderGoldensTests/OscilloscopeGoldenTests.swift` (research VIS-003-D4: the sine fixture at both QA-002 resolutions compared with `GeneratorGoldens/<class>/` under QA-002's rule and record policy; an integrity test over `GeneratorGoldens` with the one-entry generator catalog, runnable on Linux); record the goldens on the macOS host and the iOS 27.2 simulator with the record switch; review the PNGs. Evidence: the comparison passes without the switch on both classes; integrity passes.

## Phase 3: User Story 3 - flash safety and glow (P2)

- [ ] VIS-003-T11 [P] [US3] Write `OscilloscopeFlashTests.swift`: (CPU) a 60 Hz alternation of a full-scale 220 Hz sine and silence for 2 s through `FlashSafetyLimiter` with the oscilloscope layout (Thick line, white palette, the strongest glow's luminance model as the downstream transfer) yields ≤ 4 transitions per 1 s window in every area and signal with Reduce flashing on and ≤ 6 off (FlashAnalysis); portrait and landscape layouts keep every sample point inside the output. Evidence: passes on the host and in the Linux shape (fix the model if needed).

## Phase 4: User Story 1 - choose it in the app (P1)

- [ ] VIS-003-T12 [P] [US1] Write app unit tests: `Apps/projectM-iOS/Tests/SettingsTests.swift` (line/window defaults medium/20, persistence, unknown → defaults, `allKeys` contains both keys, `VisualChoice.oscilloscope` stored as `oscilloscope`, `isNative`) and `Apps/projectM-iOS/Tests/NativeVisualTests.swift` (an oscilloscope host names itself "Oscilloscope visualization", identifier `oscilloscope`, value "20 ms, Glow off"; switches to circular and back; the unavailable notice names "Oscilloscope"; a scene captured while the oscilloscope is shown has no native layer, VIS-003-R12). Record the red run.
- [ ] VIS-003-T13 [US1] Implement: `AppSettings.swift`, `NativeSpectrumHost.swift` (style, `WaveformTap`, sample scratch), `AppCoordinator.swift` (style), `SettingsView.swift` (Line, Window; Bars hidden), `VisualizerView.swift` (onChange), `ShowSceneSnapshot.swift` and `SceneAutosaveCapture.swift` (no layer), `scripts/run_device_tests.py` (two allowed keys). Evidence: `xcodegen generate`, app build, T12 and the app unit tests pass `{sim}`; `test_scripts.py` passes.
- [ ] VIS-003-T14 [US1] Write `Apps/projectM-iOS/UITests/OscilloscopeUITests.swift`: choose Oscilloscope, Thick and 40 ms, check the visual (`oscilloscope`, value starting "40 ms"), Bars absent, relaunch and check all persisted, source started once; under 30 s `{sim}`. Then run it with `NativeVisualUITests` and `GlowUITests`. Evidence: all pass; durations recorded.
- [ ] VIS-003-T15 [US1] One simulator screenshot with the reference track into `.build/scratch/vis003-oscilloscope.png` `{sim}`; count new PosterBoard reports.

## Phase 5: Polish

- [ ] VIS-003-T16 Run `xcodebuild test -scheme VisualGenerators` on the simulator `{sim}`; `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `test_scripts.py`, `check_privacy_manifest.py <Debug .app>`; amend ADR-0009 (third native visual, the sample path); delete the feature's simulator. Evidence: logs.
- [ ] VIS-003-T17 `{device}` On D1 under Instruments (Allocations, Metal System Trace): 60 s of the oscilloscope with the reference track, no allocation growth in the frame loop and frame time within the VIS-001 budget; D2 and D3 render it. Final device phase only.

## Analysis (speckit-analyze, 2026-11-13)

Coverage: every requirement maps to a task (R1-R2, R15 → T04-T05, T09; R3-R6 → T02-T03; R7-R8 → T06-T08; R9 → T11; R10-R11, R13 → T12-T14; R12 → T12-T13; R14 → T10). One gap fixed: R12 had no test (added to T12). Terminology checked across spec, research, data model and contract (window samples 441/882/1,764; thickness 0.001…0.05; amplitude 0.9; tolerance 1.05 × best + 1e-4). Constitution: no conflict (plan, Constitution Check). No CRITICAL or HIGH findings.

## Dependencies

T01 → (T02-T03) → (T04-T05) → (T06-T07) → (T08-T09) → T10 → T11 → (T12-T15 US1) → T16; T17 last, on
devices. US1 needs the generator and the tap (US2). Within a phase, `[P]` test tasks can be written
in parallel; production tasks follow their tests.
