# Test Report: FX-010 Echo Feedback

Spec: `specs/297-fx-010-echo-feedback` (ADR-0108). Run 2026-11-15 on the Mac Studio (Xcode 27.2) and the feature's own
iOS 27.2 simulator ("FX10 iPhone 17", deleted afterwards). Simulator results are never device evidence.

## Roadmap acceptance: "Echo count is capped and memory use remains bounded"

| Proof | Test | What it asserts |
|-------|------|-----------------|
| Count capped (model) | `EchoFeedbackModelTests.testCountIsCappedAtFourEverywhere` | Requests of 5, 8, 1000 and `Int.max` echoes (and a stored 7.6 or +Inf) give exactly 4; the weights list has 4 entries |
| Count capped (GPU, shader) | `EchoCompositeTests.testMovingDotShowsExactlyFourCappedEchoesMatchingTheReference` | The shader declares `cmp_echo_cap = 4` and loops `k < min(e.count, cmp_echo_cap)`; with 8 echoes requested a moving dot shows exactly 4 copies and nothing where a 5th would be |
| Count capped (scenes, app) | `SceneEffectChainTests.testEchoEntryRoundTripsAndTheCountIsCapped`, `EchoSettingTests.testOffByDefaultPersistedAndCapped`, `EchoUITests` | A scene entry with 12 echoes reads as 4 (reported as clamped); a stored 1000 and a set 9 read as 4; the slider ends at "4" |
| Memory bounded | `EchoCompositeTests.testMemoryStaysBoundedOverSixHundredFramesWithChangesAndResizes` | 600 frames with count (1…8), delay and fade changes every 50 frames, resizes 32×32 → 34×30 (same history class) → 64×48 → 32×32 and an off/on: while on the ring always holds exactly 4 pictures at the history size; their identities never change except at a history-size change or turning on; total `allocatedSize` ≤ 4 × the device's allocation size of one picture; echo allocations happen only on frames 0, 200 (output picture only), 300, 450 and 510; off holds nothing |
| Bound per device class | `EchoFeedbackModelTests.testHistorySizePerDeviceClassStaysUnderTheBound` | History sizes D1 960×432 (13,271,040 B), D2 960×720, D3 960×656, 4K 960×544; every size up to 16,384² stays ≤ 29,491,200 B; a small resize keeps the size class |

## Echo maths, safety and identity

| Proof | Test | What it asserts |
|-------|------|-----------------|
| Delays and weights | `EchoCompositeTests.testMovingDotShowsExactlyFourCappedEchoesMatchingTheReference`; `EchoFeedbackModelTests` schedule tests | A 2×2 dot moving 6 px per 62.5 ms frame, one store per frame: the GPU frame matches the CPU reference (downsample + bilinear + weighted max) within 2/1024; echo k sits where the dot was k frames ago and each copy is 0.6 × the one before; the schedule stores every frame at a one-frame delay and every 125 ms at a 125 ms delay, at most once per frame |
| Weight sum ≤ cap | `EchoFeedbackModelTests.testWeightsDecayAndNeverSumAboveTheCap`, `testSafetyProfileLimitsTheWeightSum` | For fades 0.1-0.9, counts 1-4 and caps 1, 0.5, 0.25 the Float weights sum to at most the cap with ratio = fade; Reduce flashing caps the sum at 0.5, an intensity limit of 0 turns Echo off |
| Never brighter | `EchoCompositeTests.testNeverBrighterThanTheFramesItIsMadeOf` | Alternating white and grey frames at fade 0.9 (raw sum 3.1, scaled to 1): no output value above 1 |
| Off is exact | `EchoCompositeTests.testOffAndZeroEchoesAreBitIdenticalOnRandomContent`; `EffectChainSceneTests.testInactiveEchoRendersExactlyAsNoChainAndReloads` | Off, 0 echoes, a weight cap of 0 and disabled-with-4 are bit-identical to no feature over 3 frames (raw halves and screen output), no pass ran, no picture held; inactive scene entries render exactly as no chain |
| Reset | `EchoCompositeTests.testResetShowsNoEchoOfOldContent` | Red frames, `resetFeedback()`, blue: the first new frame is bit-identical to blue alone |

## Runs

| Suite | Where | Result |
|-------|-------|--------|
| Compositor (`swift test`) | Mac host | 722 tests, 0 failures, 10 skipped as before (15 new; 21 s of tests) |
| Compositor, Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`) | Mac host | builds; `EchoFeedbackModelTests` and `OutputEffectOrderTests` pass |
| SceneFormat | host | 214 tests, 0 failures |
| RenderGoldens | host | 111 tests, 0 failures, 1 skipped as before (existing goldens unchanged) |
| LibraryBackup | host | 88 tests, 0 failures |
| App unit tests (`projectM-iOSTests`) | own simulator | 1328 tests, 0 failures (50 s) |
| `EchoUITests`, `EffectChainUITests`, `RadialBlurUITests` | own simulator | 13.8 s, 12.1 s, 12.3 s, pass |
| Repo checks | host | compliance, docs, motion policy, permission catalog, status events OK; 186 script tests OK |
| Privacy manifest, network symbols | Debug simulator app | OK |

Results after merging `autonomous/integration` (FX-008 radial blur): the standard order is Trails, Color, Chromatic
split, Directional blur, Radial blur, Echo.

PosterBoard crash reports: 25 before and 25 after the simulator runs.

The type-check budget run (`-warn-long-function-bodies=300 -warn-long-expression-type-checking=150`) reports no FX-010
function or expression. Its one warning in a touched file, `EffectChainView.swift:21` (the first `coordinator.effectChain`
lookup, about 285 ms), is on a line this feature does not change and appears equally on the commit before the app work.

## Open

- FX-010-T17 `{device}`: on D1, the Camera visual with 4 echoes at 200 ms: four fading copies trail a moving hand and
  the frame rate with and without Echo is recorded.
