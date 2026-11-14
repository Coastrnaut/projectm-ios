# Test report: FX-020 Effect chain presets

- **Feature**: FX-020 (`specs/142-fx-020-effect-chains`, ADR-0052)
- **Date**: 2026-11-14, Mac Studio (Xcode 27.2), private simulator "FX20 iPhone 17" (iOS 27.2)
- **Simulator results are not device evidence.** The device GPU check is FX-020-T19 `{device}` (open).

## Acceptance ("Reorder effects and reload; rendered order and values persist")

`Packages/RenderGoldens/Tests/RenderGoldensTests/EffectChainSceneTests.swift`, through the golden scene renderer (SCN-001
decode → live state → layers → `Compositor` with the flash guard on → REC-001 capture), animated SHD-001 plasma scene at
10 fps with Trails (half-life 0.5 s) and a strong grade (gamma 2, saturation 0.4, temperature 0.3, hue 25):

| Test | Asserts | Result |
|---|---|---|
| `testReorderSaveReloadPersistsOrderValuesAndPicture` | Trails → Color reordered to Color → Trails, encoded, written to a file, read back: order `[fx.grade, fx.trails]`, all grade values, flag and half-life equal; frame 7 equals Color → Trails rendered directly (QA-003 `ImageDiff`, `.exact`, `identical`) and differs from Trails → Color (> 100 changed pixels) | Pass |
| `testSafetyEntriesCannotMoveSafety` | `[fx.flashGuard, fx.toneMap, fx.grade, fx.trails]` → order Color → Trails, two `fixedEffectStage` warnings, frame identical (`.exact`) to the list without them | Pass |
| `testAbsentChainRendersAsBefore` | no `effects` field vs. the default chain (Trails off, Color on and neutral): identical frames | Pass |

## Other tests

| Command | Result |
|---|---|
| `swift test --package-path Packages/Compositor` (host GPU) | all pass; new `OutputEffectOrderTests` (5) and `EffectOrderCompositeTests` (4: order matters with Trails and a grade; standard order bit-identical to an unset order; Trails off or neutral grade: both orders byte-identical; grade pass runs only when needed, resets counted) |
| `swift test --package-path Packages/SceneFormat` | 133 tests pass (new `SceneEffectChainTests`, 9: absent list byte-identical; round trip; `malformed` for wrong types; `tooMany` at 17; clamping reported; unknown entry kept at its index through load → reorder → capture and listed by SCN-012; repeated and fixed kinds never move the order; presets save/replace/round-trip and limits); QA-004 meta-test passes |
| `swift test --package-path Packages/RenderGoldens` | 58 tests pass (goldens unchanged) |
| Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`) Compositor and SceneFormat | pass (SceneFormat 132, Metal-only tests compiled out) |
| `swift test --package-path Packages/LibraryBackup` | 45 pass |
| App unit tests (`EffectChainSettingTests` 6, `ColorGradeSettingTests`, `MotionFeedbackSettingTests`, `LibraryBackupAppTests`, `LibraryEraseAppTests`, `SceneAutosaveCaptureTests`, `SceneHistoryCoordinatorTests`, `SceneAutosaveCoordinatorTests`, `SceneAutosaveMigration*`) | all pass |
| UI `EffectChainUITests.testReorderEffects` | pass, 24.1 s (drag Color above Trails; Settings row reads "Color → Trails") |
| UI `TrailsUITests`, `ColorGradeUITests` (neighbouring Settings sections) | pass (12.7 s, 39.7 s; the latter is FX-003's existing test) |
| Repository checks: compliance, docs, motion policy, permission catalog, status events, 153 script tests, privacy manifest (Debug app), network symbols | all OK |
| Type-check budget (`-warn-long-function-bodies=300 -warn-long-expression-type-checking=150`) | no warning in FX-020 files |

PosterBoard crash reports: 25 before and 25 after the simulator runs.
