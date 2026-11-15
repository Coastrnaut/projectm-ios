# Test Report: FX-012 Mosaic Pixelation

Spec: `specs/299-fx-012-mosaic-pixelation` (ADR-0110). Run 2026-11-15 on the Mac Studio (Xcode 27.2) and the
feature's own iOS 27.2 simulator ("FX12 iPhone 17", deleted afterwards). Simulator results are never device evidence.

## Roadmap acceptance: "Block size one equals original frame; larger sizes are visibly discrete"

| Proof | Test | What it asserts |
|-------|------|-----------------|
| Size 1 = original frame | `MosaicCompositeTests.testMosaicOffAndSizeOneAreBitIdenticalOnRandomContent` | Seeded random premultiplied content (37 × 29) through the real compositor: off, and on at size 1 as squares and as hexagons, give raw half-float stack results equal to the input and identical screen output; no pass ran, no picture held |
| Size 1 = original frame (scenes) | `MosaicSceneGoldenTests.testMosaicSizeOneRendersExactlyAsNoChain` | The golden plasma scene with a size-1 hexagon or a disabled `fx.mosaic` entry equals the scene without a chain (`ImageDiff .exact`) |
| Larger sizes are discrete (squares) | `MosaicCompositeTests.testMosaicSquaresAreUniformBlocksOfTheirCentrePixelAndDiffer` | Random content (44 × 27), size 8: each of the 15 full 8 × 8 blocks from the top-left corner is one colour, bit-identical to its centre input pixel (bx·8 + 4, by·8 + 4); every pair of horizontally or vertically adjacent blocks differs; the whole frame, partial edge blocks included, equals the CPU reference bit for bit |
| Larger sizes are discrete (hexagons) | `MosaicCompositeTests.testMosaicHexagonCellsAreUniformAwayFromBorders` | Random content (61 × 47), hexagons at size 12: at every pixel whose four neighbours lie in the same cell by the CPU assignment (more than 60% of pixels), the GPU output equals the reference bit for bit; every cell (more than 15) is one uniform colour; fewer than 2% of all pixels differ from the reference (border ties) — in the run, none differed |
| Cell maths | `MosaicModelTests` (6 tests, CPU, Linux-buildable) | Clamps and defaults (NaN, rounding, bounds); size 1 inactive; square anchors and centre pixels incl. partial edge and odd sizes; hex assignment equals the brute-force nearest pointy-top centre for every pixel of a 40 × 40 frame; every sample inside the frame for both shapes at sizes 2, 7, 64; reference identity at size 1 and four uniform blocks at size 8 |
| Order and pool | `MosaicCompositeTests.testMosaicOrderFoldsColorBeforeItAndThePictureIsReturned` | Standard order runs the grade pass before the mosaic; mosaic-first does not; off returns the picture |
| Scene round trip | `MosaicSceneEntryTests` (2), `MosaicSceneGoldenTests.testMosaicSaveReloadPersistsValuesAndPicture` | `fx.mosaic` (size, shape) round-trips byte-identically, clamps and reports bad values, a disabled mosaic saves nothing, older lists read with it appended; a reloaded hexagon scene renders the identical picture, which differs from the plain one in more than 100 pixels |

## Runs

| Suite | Where | Result |
|-------|-------|--------|
| Compositor (`swift test`) | Mac host (real Metal device) | 717 tests, 0 failures, 10 skipped as before (10 new; about 50 s with the build) |
| Compositor, no-Metal shape (`-DCOMPOSITOR_NO_METAL`, with tests) | Mac host | builds |
| SceneFormat | host | 215 tests, 0 failures (2 new) |
| RenderGoldens | host | 112 tests, 0 failures, 1 skipped (on-demand soak) (2 new; existing goldens unchanged) |
| LibraryBackup | host | 88 tests, 0 failures |
| App unit tests (`projectM-iOSTests`) | own simulator | 1321 tests, 0 failures (59 s), incl. `MosaicSettingTests` 5/5, `SettingsTests`, `LibraryBackupAppTests`, `LibraryEraseAppTests` |
| `MosaicUITests` | own simulator | 1 test, 20.1 s and 16.4 s (first attempt failed: the drag started off the thumb; fixed to start at 8 px's position) |
| `EffectChainUITests` | own simulator | pass (13.1 s, 36.5 s, 17.1 s; the long run under a host load average of about 30) |
| Repo checks | host | compliance, docs, motion policy, permission catalog, status events OK; 186 script tests OK |
| Privacy manifest, network symbols | Debug simulator app | OK |

Type-check budget run: no FX-012 function or expression is listed. Listed under load: `AppCoordinator.init` (646 ms;
known since FX-006, one line added here) and `EffectChainSection.body` (320 ms; untouched, a three-line body).

PosterBoard crash reports: 25 before and 25 after the simulator runs.

## Open

- FX-012-T18 `{device}`: on D1, the Photo visual with Mosaic at 8 and 64 px in both shapes: blocks are flat and
  discrete, and the frame rate with and without it is recorded.

## Merge with FX-010 (echo feedback), 2026-11-15

`autonomous/integration` (with FX-010) merged into `feature/fx-012`: 26 files conflicted. They were resolved by keeping
both features, with `fx.echo` before `fx.mosaic`: Trails → Color → Chromatic split → Directional blur → Radial blur →
Echo → Mosaic. The order checks now use `firstIndex` (radial blur at 4, Echo at 5, Mosaic at 6), so they still hold
when another kind is appended. `MosaicUITests` now drags from the thumb's position as read from the readout and retries
up to three times: one run after the merge had missed the thumb.

| Suite | Where | Result |
|-------|-------|--------|
| Compositor `--filter "Mosaic|Echo|OutputEffectOrder|RadialBlur"` | host | 42 tests, 0 failures |
| SceneFormat | host | 216, 0 failures |
| RenderGoldens `--filter Golden` | host | 113, 0 failures, 1 skipped |
| LibraryBackup | host | 88, 0 failures |
| App: EffectChain, Echo, Mosaic, Radial/Directional/Chromatic settings, LibraryBackupApp, LibraryEraseApp, Settings | own simulator | 48 tests, 0 failures |
| `EchoUITests`, `EffectChainUITests` | own simulator | pass (27.5 s, 13.2 s) |
| `MosaicUITests` | own simulator | pass after the drag fix, three runs (22.9 s, 24.5 s, 22.9 s) |
