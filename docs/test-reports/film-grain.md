# Test report: FX-017 Film grain

Feature `specs/311-fx-017-film-grain`, ADR-0122. Run 2026-11-15 on the Mac Studio (Xcode 27.2), branch
`feature/fx-017`, own simulator "FX17 iPhone 17" (iOS 27.2). Simulator results are not device evidence.

## Roadmap acceptance: "Fixed seed produces stable snapshots and opacity zero is identity"

`Packages/Compositor/Tests/CompositorTests/FilmGrainCompositeTests.swift`, through the real Metal compositor
(`encodeScene`, half-float pixels read back):

| Test | Asserts | Result |
|------|---------|--------|
| `testFilmGrainOffAndZeroOpacityAreBitIdenticalWithNoPass` | off and opacity 0 (seeds 0, 1, 9999; sizes 1-3; colour; temporal on) on random content 37 × 29: scene and screen output bit-identical to a compositor without the feature; no pass, no picture | pass |
| `testFilmGrainPassAtZeroOpacityReturnsItsInputBitForBit` | the pass itself encoded at opacity 0 on 37 × 29, 2 × 2 and 3 × 64 (incl. a negative and an HDR value): output = input bit for bit | pass |
| `testFilmGrainGPUHashAndNoiseEqualTheCPUExactly` | a test kernel compiled with the compositor's own `CompositorShaders.library` (safe math) writes `cmp_grain_hash` and `cmp_grain_noise` for 3 × 1024 cells (seeds 0, 1, 9999; frames 0, 12345, 2³² − 1): equal to `FilmGrain.hash` and `noise` bit for bit | pass |
| `testFilmGrainMatchesTheReferenceAndIsStableForAFixedSeed` | monochrome size 1 and colour size 2, 41 × 23 with an HDR pixel: GPU = CPU reference within one half-float step, finite, alpha kept, transparent pixel unchanged; a second compositor and a later frame time give identical pixels; seeds 1 and 2 differ | pass |
| `testFilmGrainTemporalStepsChangeOnlyPerStepAndReduceFlashingKeepsItStatic` | temporal on: the same 1⁄24 s step (and the same time again) identical, the next step differs, another compositor agrees (stateless); Reduce flashing gives the static grain at any time | pass |
| `testFilmGrainKeepsTheMeanOfAUniformGreyWithinTheBound` | 96 × 64 grey at opacity 1 (monochrome, colour size 3): mean change < 0.005 per channel, every change ≤ 0.08, finite, monochrome channels equal | pass |
| `testFilmGrainIsLastFoldsColorBeforeItAndReturnsThePicture` | last in the standard order; Color listed before it folded before it; off returns the picture | pass |

CPU reference (`FilmGrainModelTests`, 6, plain Swift; the package also builds with `-DCOMPOSITOR_NO_METAL`, the Linux
shape): clamps and rounding; PCG vectors against an independent 64-bit implementation (`pcg(0)` = 129 708 002); noise an
exact multiple of 2⁻²³ in [−1, 1); 2 × 2 cells; colour red = monochrome; grain clock static off and under Reduce
flashing and Reduce Motion, ≤ 24 changes in one second at 120 Hz, wraps at 2³²; zero mean and bound on 96 × 64 grey;
alpha 0 and black floor; opacity 0 identity (NaN, ∞, negative input kept).

Stored goldens (`FilmGrainSceneGoldenTests.testFilmGrainMatchesTheGolden`): plasma run, opacity 0.6, size 2, colour,
seed 7, static, frame 7 at 128 × 96 and 256 × 192, recorded with `GOLDEN_RECORD=1` on the host (Apple M5 Max) and
`TEST_RUNNER_GOLDEN_RECORD=1` on the own simulator, then compared: identical on both (0 pixels changed).

## Scenes, goldens, app

| Suite | Result |
|-------|--------|
| Compositor package (host, real Metal) | CompositorTests 785, 0 failures (10 skipped); 43.9 s of tests, 68 s with the build |
| SceneFormat (host) | 226, 0 failures (`FilmGrainSceneEntryTests` 2), 3.3 s |
| RenderGoldens (host) | 127, 0 failures, 1 skipped (`FilmGrainSceneGoldenTests` 3, integrity 1), 18.6 s of tests, 23.4 s total |
| RenderGoldens film grain (own simulator) | 4, 0 failures; goldens identical |
| LibraryBackup (host) | 88, 0 failures, 7.7 s |
| App unit tests (own simulator) | 1378, 1 failure (an Effect order summary string in `ChromaticSplitSettingTests` missing "Film grain"; fixed, rerun with SettingsTests, LibraryBackupAppTests, LibraryEraseAppTests: 22, 0 failures), 56 s; `FilmGrainSettingTests` 6 |
| UI tests (own simulator) | `FilmGrainUITests` 9.4 s, `EffectChainUITests` 11.7 s, `VignetteUITests` 12.5 s |
| Repo checks | compliance, docs, motion policy, permission catalog, status events OK; 186 script tests (1 skipped); privacy manifest and network symbols OK on the Debug app |

Type-check budget: the build with `-warn-long-function-bodies=300 -warn-long-expression-type-checking=150` reported no
warning in any FX-017 file. It reported about 15 warnings of 306-411 ms in unrelated files (and `AppCoordinator.init`,
394 ms), all taken at once while the Mac ran other agents' builds (800 % CPU); not attributed to this feature.

## Open

- FX-017-T17 `{device}`: on D1, grain at 100 %, sizes 1-3, colour and monochrome, Vary over time (gentle, no strobing)
  and with Reduce Motion (still), and the frame rate with and without it.
