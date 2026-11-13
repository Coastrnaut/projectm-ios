# Tasks: AUD-016 Reference tone suite

**Input**: Design documents in `specs/011-aud-016-reference-tone-suite/` (spec.md, plan.md,
research.md, data-model.md, contracts/, quickstart.md)

**Tests**: test-first. Each test task comes before the code it covers; the red run (compile failure
or failing assertions) is recorded in the task that writes the tests, before any production change.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. `[P]` = can run in parallel
(different files). Tags: `{device}` = needs a physical device, done only in the roadmap's final
device phase; `{sim}` = needs the iOS 27.2 simulator (udid
`77E17861-E687-4274-8A84-14224F32BE3E`, "iPhone Air").

A task is ticked only when its acceptance evidence was produced, with " — Verified <date>: <how>"
appended. Inside descriptions, "T07" is short for `AUD-016-T07`. Phase (Constitution, Workflow): all
tasks belong to the roadmap's AUD area. Every task needs macOS with Xcode except T29 (any OS); only
`{device}` tasks need a physical device. The app builds in the feature worktree with the 28 included
presets; `PresetTests.testBundledIncludedScopeMatchesRelease1_0` needs the full preset library, is
known to fail there and is not evidence for or against this feature.

**Order**: the stories are listed by priority (US1, US2 P1; US3 P2; US4 P3), but US1 plays its
signal through US3's playback path, so the phases run Foundational → US2 → US3 → US1 → US4.

## Phase 1: Setup

- [ ] AUD-016-T01 Confirm the baseline before any change: `swift test` for `Packages/AudioCore` (also with `-Xswiftc -DAUDIOCORE_NO_AVFAUDIO`), `Packages/CaptureKit`, `Packages/CaptureUI`, `Packages/Diagnostics`; `python3 scripts/test_scripts.py`, `scripts/check_compliance.py`, `scripts/validate_docs.py`; record the counts here. Evidence: all pass at `97d7949`.

## Phase 2: Foundational (the generator; blocks every story)

- [ ] AUD-016-T02 [P] Write `Packages/AudioCore/Tests/AudioCoreTests/ToneMathTests.swift`: `ToneMath.sin2pi(c)` within 2e-15 of `sin(2πc)` for 100,003 evenly spaced `c ∈ [0,1)` and exactly 0, 1, 0, −1 at c = 0, ¼, ½, ¾; `ToneMath.exp(x)` within 4 ulp of Foundation `exp` for x ∈ [−20, 20]; `ToneMath.log(x)` within 4 ulp of `log` for x ∈ [1e-6, 1e6]; `exp(0) == 1`, `log(1) == 0` exactly (research AUD-016-D1).
- [ ] AUD-016-T03 [P] Write `Packages/AudioCore/Tests/AudioCoreTests/ToneGeneratorTests.swift`: every `ToneError` case from data-model.md ("8,000…192,000"; "1 or 2" channels; "1 Hz ≤ f < rate/2"; amplitude "finite, 0…1"; seconds "0.01…600"; BPM "1…600"; width "≥ 1 frame and < the shortest beat period"; "1…32 accents, each 0…1"; mono needs `left == right`; at least one frequency); purity: `render(startFrame: s, frames: n)` equals the same range of a longer run and equals `sample(frame:channel:)`; interleaved and planar renders agree; sine periodicity (frame n and n + rate equal bit for bit); silence all +0.0; a nil channel is silent; pulse onsets and widths at 48 kHz; mono output equals the stereo variant's left channel (AUD-016-R1 to R8). Record the red run (missing symbols).
- [ ] AUD-016-T04 [P] Write `Packages/AudioCore/Tests/AudioCoreTests/TestSHA256.swift` (FIPS 180-4, test target only) and its known-answer tests ("", "abc", the 448-bit message, one million "a") (research AUD-016-D8).
- [ ] AUD-016-T05 Implement `Packages/AudioCore/Sources/AudioCore/ReferenceTones/ToneMath.swift` (sin2π, exp, log; basic arithmetic only, no Foundation transcendental call). Evidence: T02 passes on the host.
- [ ] AUD-016-T06 Implement `Packages/AudioCore/Sources/AudioCore/ReferenceTones/ToneSignal.swift` (`ToneFormat`, `ToneSignal`, `SineTone`, `SweepTone`, `PulseTrain`, `ToneError`, validation) and `ToneGenerator.swift` (`sample`, interleaved and planar `render` without allocation, `interleaved`). Evidence: T03 and T04 pass on the host.

## Phase 3: User Story 2 - identical fixtures on every run (P1)

**Goal**: a versioned catalog whose samples hash to stored values on every host, with expected
analysis values checked by an independent oracle.
**Independent test**: `ReferenceToneCatalogTests` and `ReferenceToneOracleTests`.

- [ ] AUD-016-T07 [P] [US2] Write `Packages/AudioCore/Tests/AudioCoreTests/ReferenceToneCatalogTests.swift`: version 1; ten fixtures with the IDs, names, parameters and layouts of `contracts/fixture-catalog.md`; unique IDs; names begin with "Test"; peak ≤ 0.5 in every variant; each loop repeats seamlessly (frame `loop + i` equals frame `i` for the first 4,096 frames; sweeps restart at phase 0); expected values equal the contract's tables (bins for 512…8192 at 44.1 and 48 kHz, onset frames, tempo, inter-onset frames, accents, sweep frequencies at 0, 1.25, 2.5, 5, 7.5 s); `ReferenceToneCatalog.playbackFormat == ToneFormat.canonical` (AUD-016-R9, R11, R23).
- [ ] AUD-016-T08 [P] [US2] Write `Packages/AudioCore/Tests/AudioCoreTests/ReferenceToneOracleTests.swift`, test target only (AUD-016-R12): a direct Hann-windowed DFT (cos/sin table, magnitude of every bin 0…N/2) over the first N frames of each sine fixture channel for N = 512…8192 at both rates, asserting the peak at `nearestBin` and, for `sine-1500` at 48 kHz, a magnitude of N/16 within 1e-6 relative; an onset scan (first non-zero sample after a zero, or frame 0) finding exactly `onsetFrames` with the documented accents for every pulse fixture at both rates; zero-crossing frequency measurement of the sweeps at 1.25, 2.5, 5 and 7.5 s within 1% (AUD-016-S2 to S4).
- [ ] AUD-016-T09 [US2] Write `Packages/AudioCore/Tests/AudioCoreTests/ReferenceToneGoldens.swift` and the golden test in ReferenceToneCatalogTests: for every fixture × {44,100, 48,000} × layouts, generate twice, assert the two outputs are equal and that SHA-256 of the little-endian Float32 interleaved loop equals the stored value; copy the values into the contract's golden table (AUD-016-R10, S1).
- [ ] AUD-016-T10 [US2] Implement `Packages/AudioCore/Sources/AudioCore/ReferenceTones/ReferenceToneCatalog.swift` (`ReferenceToneFixture`, the ten fixtures, expected-value functions). Evidence: T07, T08, T09 pass on the host.
- [ ] AUD-016-T11 [P] [US2] Write `Packages/AudioCore/Tests/AudioCoreTests/ToneAnalyzerDeterminismTests.swift`: each fixture's 48 kHz stereo loop fed in 1,024-frame blocks through `LevelMeter.measure` and `AudioStateClassifier.dataArrived` with `t = frames / 48,000`, twice; the level sequences and state sequences are identical; sines, sweeps and pulses end `active`, silence ends `silent`; sine peak −12.04 dBFS ± 0.01 (AUD-016-R21, S6).
- [ ] AUD-016-T12 [US2] Run the AudioCore suite with `-Xswiftc -DAUDIOCORE_NO_AVFAUDIO` on the host: the same golden values pass (AUD-016-R3).
- [ ] AUD-016-T13 [US2] {sim} Run the AudioCore suite with `xcodebuild test -scheme AudioCore` on the iOS 27.2 simulator: the same golden values pass (AUD-016-R3, S1).

## Phase 4: User Story 3 - the tone reaches the analysis unchanged (P2)

**Goal**: a fixture plays through the production graph and arrives unchanged.
**Independent test**: `ToneTrackTests`.

- [ ] AUD-016-T14 [US3] Write `Packages/CaptureKit/Tests/CaptureKitTests/ToneTrackTests.swift` (production backend and graph, offline rendering): `InAppPlaybackGraph.load(.tone(f))` is 48 kHz stereo, 480,000 frames, equal to the generator; at a 48 kHz offline output the frames reaching the sink equal the generator's from frame 0 for 2 s (for `sine-split`, `pulse-132`, `sweep-log`, `silence`), and two runs deliver identical audio; `PlaybackItem.tone(f)` has id `tone.<id>`, the fixture's name and 10 s (AUD-016-R15, R20, R23, S5). Record the red run.
- [ ] AUD-016-T15 [US3] Implement the tone track: `InAppPlaybackTrack.tone` in `InAppPlaybackSource.swift`, `Packages/CaptureKit/Sources/CaptureKit/InAppPlayback/ToneContent.swift` (generation into an `AVAudioPCMBuffer` on the main actor), buffer storage and buffer scheduling (whole buffer from 0, a tail copy from another frame) in `InAppPlaybackGraph.swift`, `PlaybackItem.tone` in `PlayOrder.swift` (AUD-016-R17 to R19). Evidence: T14 passes; SeekableGraphTests, TransportPipelineTests, InterruptionPipelineTests unchanged and passing.
- [ ] AUD-016-T16 [US3] Measure and assert the conversion tolerance at a 44.1 kHz offline output in ToneTrackTests (sine frequency by zero crossings, RMS level, pulse inter-onset intervals; two runs identical); record the tolerance in `contracts/fixture-catalog.md` (AUD-016-R20).

## Phase 5: User Story 1 - check the visualizer with a known signal (P1)

**Goal**: a Diagnostics section in the chooser starts a labeled test signal; nothing is stored.
**Independent test**: `TestSignalsUITests`.

- [ ] AUD-016-T17 [P] [US1] Write `Packages/CaptureUI/Tests/CaptureUITests/TestSignalStringsTests.swift`: the strings of `contracts/ui-strings.md` verbatim; `UIStrings.sourceStatus(mode:state:signal:)` gives "In-App Playback · Test tone 1 kHz · Active audio" with a signal and the feature 001 text without one; extend `ViewRenderTests.swift` to render `TestSignalsSection` and `TestSignalListView` (AUD-016-R13, R16). Record the red run.
- [ ] AUD-016-T18 [US1] Implement `Packages/CaptureUI/Sources/CaptureUI/TestSignalsSection.swift` (section, navigation row, list with name, summary, hint, footer, accessibility identifiers) and the strings in `UIStrings.swift`. Evidence: T17 passes on the host.
- [ ] AUD-016-T19 [P] [US1] Write `Apps/projectM-iOS/Tests/TestSignalCoordinatorTests.swift`: `playTestSignal` prepares the transport with `PlaybackItem.tone`, an order of one (Next and Previous return the same item), switches to the visualizer, and writes nothing to its `UserDefaults` suite; `SourceStatusIndicator.text` names the signal only for a tone item (AUD-016-R14, R16).
- [ ] AUD-016-T20 [US1] Implement `AppCoordinator.playTestSignal(_:)`, the section in `Apps/projectM-iOS/ProjectMApp.swift`, and the signal name in `Apps/projectM-iOS/Views/SourceStatusIndicator.swift`. Evidence: T19 passes {sim}.
- [ ] AUD-016-T21 [US1] {sim} Write and run `Apps/projectM-iOS/UITests/TestSignalsUITests.swift`: the chooser shows the Diagnostics section and plays nothing; Test Signals → "Test tone 1 kHz" shows "In-App Playback · Test tone 1 kHz" in the indicator and the name in the transport; "Test silence" reaches "Audio received — silent"; relaunch shows the chooser with nothing playing (AUD-016-S7, US1 scenarios 1 to 4).

## Phase 6: User Story 4 - transport and interruptions for an endless tone (P3)

**Goal**: seek, loop, Previous/Next, Stop playback and AUD-014 behave as specified.
**Independent test**: the US4 cases in `ToneTrackTests`.

- [ ] AUD-016-T22 [US4] Add to ToneTrackTests: seek to 4.0 s delivers the fixture's frame 192,000 first; rendering past 10 s wraps to frame 0 without a gap and no end is reported; `PlaybackTransport` with an order of one: `next()` and `previous()` restart at 0:00 with the same item, `stop()` holds 0:00 and `play()` continues (AUD-016-R17, US4 scenarios 1 to 4).
- [ ] AUD-016-T23 [US4] Add to ToneTrackTests: a synthetic interruption (engine stopped, `.interruptionBegan`, then resume) continues from the held frame with the fixture's content; a media-services reset rebuilds the tone and continues at the held frame (AUD-016-R15, US4 scenario 5).

## Phase 7: Polish and cross-cutting

- [ ] AUD-016-T24 {sim} Run the dependent packages: CaptureKit, CaptureUI, Diagnostics on the host and the simulator; Rendering (`Rendering-Package`) and ANGLERendering on the simulator (engine submodule from the local copy).
- [ ] AUD-016-T25 {sim} Run all app unit tests and the UI tests `ImportedAudioUITests`, `TransportUITests`, `InterruptionUITests`, `StatusUITests`, `SettingsUITests`, `TestSignalsUITests`.
- [ ] AUD-016-T26 Record generation time of a 10 s 48 kHz stereo loop on the host (Debug test build) in this file; the D1 Release figure belongs to T30.
- [ ] AUD-016-T27 Update the Baseline-independent docs: `docs/FEATURE_ROADMAP_AUTONOMOUS.md` is frozen and not edited; add the feature to nothing else shared. Confirm `docs/privacy-policy.md` needs no change (no stored data, nothing leaves the device).
- [ ] AUD-016-T28 Run every suite touched twice at the end (host and simulator) and record the counts.
- [ ] AUD-016-T29 `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`, `python3 scripts/test_scripts.py` pass.
- [ ] AUD-016-T30 {device} On D1, D2 and D3 in the final device phase: each signal kind audible on the speaker and on headphones; status "Active audio" (silence "Audio received — silent"); an interruption and a route change behave as for an imported track; Release generation time on D1 (AUD-016-S8).

## Dependencies

- T01 → T02–T04 (tests, red) → T05, T06 → US2 (T07–T13) → US3 (T14–T16) → US1 (T17–T21) → US4 (T22, T23) → T24–T29. T30 waits for the roadmap's final device phase.
- US1 needs US3's track; US4 needs US3. US2 needs only the foundation.

## Parallel opportunities

- T02, T03, T04 (separate test files). T07, T08, T11 (separate test files). T17 and T19.
- Builds and simulator runs share one Mac: at most one `xcodebuild` lane at a time.

## Implementation strategy

MVP = Foundational + US2 (deterministic fixtures with goldens and expected values): it is what the
ANL rows need first. Then US3 (playback path), US1 (the user-facing Diagnostics list), US4.
