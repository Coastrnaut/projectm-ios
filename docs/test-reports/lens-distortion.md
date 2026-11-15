# Test report: FX-016 Lens distortion

Feature `specs/306-fx-016-lens-distortion`, ADR-0117. Run 2026-11-15 on the Mac Studio (Xcode 27.2), branch
`feature/fx-016`, own simulator "FX16 iPhone 17" (iOS 27.2). Simulator results are not device evidence.

## Roadmap acceptance: "Zero distortion is identity; corners remain safely sampled"

`Packages/Compositor/Tests/CompositorTests/LensDistortionCompositeTests.swift`, through the real Metal compositor
(`encodeScene`, one frame, half-float pixels compared bit for bit):

| Test | Asserts | Result |
|------|---------|--------|
| `testLensDistortionOffAndZeroStrengthAreBitIdentical` | off, strength 0 (zoom on and off) on random content 37 × 29: scene and screen output bit-identical to a compositor without the feature; no pass, no picture | pass |
| `testLensDistortionShaderWithZeroCoefficientIsBitIdentical` | the pass itself encoded with k = 0 (zoom on and off) on 37 × 29, 2 × 2 and 3 × 64 (incl. −0 and an HDR value): output = input bit for bit | pass |
| `testLensDistortionExtremesMatchTheReferenceAndStayFinite` | strength ±1, zoom on and off, 49 × 27 and 9 × 65 with HDR corners (60 000): every value finite; GPU = CPU reference within 2⁻⁸ relative + 0.002; the middle pixel exact; corners transparent black only for barrel without zoom; no outside sample otherwise | pass |
| `testLensDistortionOrderFoldsColorBeforeItAndThePictureIsReturned` | Color listed before the warp is folded before it, after it stays in the output pass; strength 0 returns the picture | pass |

CPU reference and dense-grid proof: `LensDistortionModelTests` (5), no GPU (also run with `-DCOMPOSITOR_NO_METAL`, the
Linux shape):

- clamps (NaN → +0.3, ±Inf → ±1), k = 0.3 × strength, 32-byte block, zoom only for barrel;
- strength 0: every pixel centre maps to itself on 37 × 29, 2 × 2, 3 × 1000, 1000 × 3; the reference keeps −0;
- strength ±1, 0.37, −0.63, zoom on and off, every pixel of 64 × 64, 160 × 90, 90 × 160, 4 × 256, 256 × 4, 2 × 2,
  2 × 4096 and 4096 × 2: every sample finite, every inside sample in 0…W × 0…H, every tap in 0…W − 1 × 0…H − 1 with
  weights in 0…1, outside samples only for barrel without zoom (and there the corner is outside);
- radial map r ↦ r (1 + k r²) ÷ z strictly increasing on 1001 radii at all 200 strength steps, zoom on and off;
- reference output finite and within the input's range on HDR input; the middle pixel unchanged.

## Scenes, goldens, app

| Suite | Result |
|-------|--------|
| Compositor package (host, real Metal) | CompositorTests 760, 0 failures (10 skipped); whole package 56.6 s |
| SceneFormat (host) | 222, 0 failures (`LensDistortionSceneEntryTests` 2: round trip, clamping and reporting, disabled = default, older lists read with it at index 8 and encode byte-identically), 5.0 s |
| RenderGoldens (host) | 117, 0 failures, 1 skipped (`LensDistortionSceneGoldenTests` 2: zero and off render exactly as no chain; a barrel scene round-trips, differs from the plain one and has black corners without zoom; pincushion and zoomed barrel fill the corners), 33.9 s |
| LibraryBackup (host) | 88, 0 failures, 23.7 s |
| App unit tests (own simulator) | 1359, 0 failures, 52 s (`LensDistortionSettingTests` 5) |
| UI tests (own simulator) | `LensDistortionUITests` 12.9 s, `EffectChainUITests` 13.6 s |
| Repo checks | compliance, docs, motion policy, permission catalog, status events OK; 186 script tests; privacy manifest and network symbols OK on the Debug app |

## Open

- FX-016-T17 `{device}`: on D1, the warp at ±100 % with zoom on and off, and the frame rate with and without it.
