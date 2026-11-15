# Test report: FX-014 Edge outline

Feature `specs/303-fx-014-edge-outline`, ADR-0114. Run 2026-11-15 on the Mac Studio (Xcode 27.2), branch
`feature/fx-014`, own simulator "FX14 iPhone 17" (iOS 27.2). Simulator results are not device evidence.

## Roadmap acceptance: "Flat image produces no outlines and checkerboard produces boundaries"

`Packages/Compositor/Tests/CompositorTests/EdgeOutlineCompositeTests.swift`, through the real Metal compositor
(`encodeScene`, one frame, half-float pixels compared bit for bit):

| Test | Asserts | Result |
|------|---------|--------|
| `testEdgeOutlineFlatPicturesAreUnchangedInOverlayAndBlackInOutlineOnly` | five flat colours (incl. black, white, a half-transparent one), 23 × 17: overlay output = input bit for bit with the pass running (threshold 0.02, width 3); outline-only output opaque black at every pixel, border included | pass |
| `testEdgeOutlineCheckerboardOutlinesExactlyTheBoundaries` | 8-pixel black/white checkerboard, 36 × 28 (partial squares at the edges), widths 1 and 3: the changed pixels are exactly the CPU reference mask; full-mask pixels are the outline colour; every pixel more than `width` from a boundary is unchanged; both sides of every boundary are outlined | pass |
| `testEdgeOutlineThresholdAboveTheContrastDrawsNothing` | contrast 0.25 checkerboard: threshold 0.3 → output = input; threshold 0.1 → outlined | pass |
| `testEdgeOutlineOffIsBitIdenticalAndThePictureIsReturned` | off: no pass, no picture, scene and screen output bit-identical to a compositor without the feature; Color listed before is folded before it; position 7 in the standard order; turning off returns the picture | pass |

CPU reference: `EdgeOutlineModelTests` (4): clamps and hex colour, flat pictures have zero strength everywhere
(clamped taps), a step is outlined on 2 × width columns, threshold at or above the contrast → no mask, NaN/Inf → 0,
ACC-012 Strict scales the colour by 0.25.

## Other runs

| Command | Result |
|---------|--------|
| `swift test` in `Packages/Compositor` | CompositorTests 741 (10 skipped), 0 failures; whole package 44 s |
| `swift test` in `Packages/SceneFormat` | 218, 0 failures (EdgeOutlineSceneEntryTests 2) |
| `swift test` in `Packages/RenderGoldens` | 115 (1 skipped), 0 failures (EdgeOutlineSceneGoldenTests 2: disabled = no chain; save/reload identical and differs from plain) |
| app unit tests (`-only-testing:projectM-iOSTests`) | 1344, 0 failures, 53 s (EdgeOutlineSettingTests 5, SettingsTests, LibraryBackupAppTests, LibraryEraseAppTests, effect setting tests) |
| `EdgeOutlineUITests.testEdgeOutlineControls` | pass, 20.7 s |
| `EffectChainUITests.testReorderEffects` | pass, 13.1 s |
| repo checks, 186 script tests, privacy manifest, network symbols | OK |

## Open

- FX-014-T18 `{device}`: on D1, outlines on the Camera visual and the frame rate with and without the outline.
