# RenderGoldens (QA-002)

Golden render scenes: small scene documents rendered at fixed resolutions and compared with stored
PNGs, so a renderer change shows up as images a reviewer can look at. Spec:
`specs/066-qa-002-golden-render-scenes`; policy: `docs/adr/0030-golden-render-scenes.md`.

## Contents

| Folder | What |
|---|---|
| `Scenes/` | 7 canonical SCN-001 scene documents (`<name>.scene.json`) |
| `Sources/GoldenImages/GoldenSceneCatalog.swift` | each scene's seed, clock, audio, captured frames, generated photos |
| `Goldens/macos/`, `Goldens/ios-simulator/` | golden PNGs (`<scene>-<w>x<h>-f<frame>.png`) and `manifest.json` |

Licensing: everything is authored or generated in this repository (MIT, like the repository). Photos
are generated from the seed at run time; the graph is the repository's SHD-002 "Hue Rings" example;
the text uses the system font. No third-party image, font file or content.

The golden set is about 0.38 MB (budget 2 MB, checked by `GoldenIntegrityTests`).

## Generator goldens (VIS-003)

`GeneratorGoldens/<class>/` holds goldens of a native generator rendered directly, without a scene
(the oscilloscope is not a scene layer kind yet): `waveform-oscilloscope-sine-<w>x<h>-f1.png`, a 440 Hz
sine through `OscilloscopeGenerator` (`Tests/RenderGoldensTests/OscilloscopeGoldenTests.swift`). Same
rule, record switch, CI guard, diff artifacts and integrity check as the scene goldens; record with
`--filter OscilloscopeGoldenTests` (host) or `-only-testing:RenderGoldensTests/OscilloscopeGoldenTests`
(simulator).

`GeneratorGoldens/Lissajous/<class>/` (VIS-004) holds the Lissajous scope's goldens the same way:
`lissajous-inphase-<w>x<h>-f1.png` (L = R, a diagonal) and `lissajous-quadrature-<w>x<h>-f1.png`
(R = L shifted 90°, a circle), a 440 Hz sine through `LissajousGenerator`
(`Tests/RenderGoldensTests/LissajousGoldenTests.swift`); record with `--filter LissajousGoldenTests` or
`-only-testing:RenderGoldensTests/LissajousGoldenTests`.

`GeneratorGoldens/RadialWaveform/<class>/` (VIS-005) holds the radial waveform's goldens the same way:
`radial-sine-<w>x<h>-f1.png` (a 220 Hz sine wrapped around the ring) and `radial-silence-<w>x<h>-f1.png`
(the base circle), through `RadialWaveformGenerator`
(`Tests/RenderGoldensTests/RadialWaveformGoldenTests.swift`); record with `--filter RadialWaveformGoldenTests` or
`-only-testing:RenderGoldensTests/RadialWaveformGoldenTests`.

## Run

```bash
swift test --package-path Packages/RenderGoldens
cd Packages/RenderGoldens && xcodebuild test -scheme RenderGoldens -destination id=<simulator udid> \
  CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180
```

The macOS host compares with `Goldens/macos`, any iOS Simulator with `Goldens/ios-simulator`. A
physical device has no goldens yet: the suite reports "pending". The text scene is compared only on
the OS version (major.minor) its golden was recorded on.

## Review a failure

Rule (QA-003, `ImageDiffTolerance.golden`; `specs/133-qa-003-visual-diff`): equal pixel hashes are
"identical"; otherwise the images must have the same size and, counting only pixels whose largest
channel difference (alpha included) is above 2/255:

1. a pixel is *forgiven* when, within one pixel, the other image has a matching pixel in both
   directions (a one-pixel rasterization shift);
2. at most ⌊0.1 % × pixels⌋ pixels may remain *unmatched* (12 at 128 × 96, 49 at 256 × 192);
3. no 8-connected cluster of unmatched pixels may exceed 8 pixels (scattered noise passes; a moved,
   scaled or missing shape fails even when its pixel count is small).

Each failed capture writes `expected.png`, `actual.png`, `diff.png` and `summary.txt` to
`.build/golden-diffs/<class>/<capture>/` (set `GOLDEN_DIFF_DIR` to change it) and appends a line to
`.build/golden-diffs/<class>/summary.txt`; the same files are attachments of the failed test in the
`.xcresult`. The summary names the failed rules (`count`, `cluster`, `ssim`, `size`) and gives the
changed, exceeding, forgiven and unmatched counts, the largest channel difference, the largest
cluster, the bounding box of the differences and the mean luma SSIM. In `diff.png`, grey = unchanged,
yellow = within 2/255, orange = forgiven as a shift, red = unmatched (brighter = larger), magenta =
outside the overlap of differently sized images, cyan = outline of the bounding box.

## Compare images in other tests (QA-003)

`ImageDiff` (module `GoldenImages`, Foundation-free, runs on Linux) compares any two RGBA8
`GoldenImage`s:

```swift
let report = ImageDiff.compare(expected: golden, actual: frame, tolerance: .golden)
XCTAssertTrue(report.passed, report.summary)
```

| Preset | Colour | Allowed unmatched | Shift radius | Largest cluster | Use |
|---|---|---|---|---|---|
| `.exact` | 0 | 0 | 0 | — | output that is deterministic by construction |
| `.qa002` | 2/255 | 0.1 % | 0 | — | QA-002's original colour-only rule |
| `.golden` (default) | 2/255 | 0.1 % | 1 | 8 | GPU goldens |

Custom: `ImageDiffTolerance(channelThreshold:allowedFraction:maxExceedingPixels:neighborhoodRadius:maxClusterPixels:minimumSSIM:)`
(colour 0-255, radius 0-8; `maxExceedingPixels` caps the fraction's count; `minimumSSIM` is opt-in,
because single noise pixels lower SSIM sharply). Run-to-run determinism checks keep comparing pixel
hashes.

## Re-record on purpose

Only when a change is intended:

```bash
GOLDEN_RECORD=1 swift test --package-path Packages/RenderGoldens --filter GoldenRenderSuiteTests
cd Packages/RenderGoldens && TEST_RUNNER_GOLDEN_RECORD=1 xcodebuild test -scheme RenderGoldens \
  -destination id=<iOS 27.2 simulator udid> CODE_SIGNING_ALLOWED=NO \
  -only-testing:RenderGoldensTests/GoldenRenderSuiteTests
git diff --stat Packages/RenderGoldens/Goldens
```

Recording writes missing goldens, replaces failing ones and leaves passing ones untouched; review the
changed PNGs before committing them with the manifests. When `CI` or `GITHUB_ACTIONS` is set,
recording is refused: the test fails and writes nothing. Without the switch a missing golden fails.

## Add a scene

Write the scene as canonical SCN-001 bytes (`SceneDocument.encoded()`), add its run to
`GoldenSceneCatalog.runs` and a test method to `GoldenRenderSuiteTests`, then record both classes.

## Render soak (QA-006)

`RenderSoakDriver` (module `SceneRenderHarness`; `specs/155-qa-006-render-soak`) switches six of the
scenes above (all but strobe-guarded) through CMP-014's `SceneTransitionBus` with one shared texture
pool: each switch builds the next scene anew from its document, crossfades for 0.25 s (every third
switch is a cut), dwells 30 frames, and feeds seeded fixture bands on an injected 60 Hz clock. Frames
are committed and awaited, so the soak runs faster than real time; nothing asserts wall time.

The verdict (`RenderSoakRecorder`, Compositor) passes only with zero render errors (build, encode,
command buffer, PERF-014 faults), a flat memory trend (after 2 warm-up cycles, the least-squares slope of
the per-cycle high-water marks ≤ max(64 KiB, 0.5 %) per cycle and no high-water above warm-up +
max(2 MiB, 10 %)), pool checkouts equal to each scene's baseline at every dwell end, one scene alive per
dwell end, and nothing checked out or alive after release. Memory is `MTLDevice.currentAllocatedSize`;
the iOS Simulator reports 0 there, so it falls back to the pool's live bytes (the report's
`memorySource` says which) and also records the process footprint for information.

| Test (`RenderSoakTests`) | What |
|---|---|
| `testDefaultSoakIsBoundedAndErrorFree` | 30 s simulated, 60 scenes shown, must pass |
| `testPooledLeakFailsTheSoak`, `testDeviceLeakFailsTheSoak` | negative controls: one leaked texture per cycle must fail |
| `testOnDemandLongSoak` | skipped unless `QA006_SOAK_SECONDS=<n>` |

`ProjectMPresetSoakTests` (Packages/ANGLERendering, simulator) soaks projectM preset switches the same way.
Each run writes a JSON report to `QA006_REPORT_DIR` (else `<tmp>/qa006-render-soak/`) and attaches it.
Long soak on demand:

```bash
python3 scripts/run_render_soak.py --seconds 600                                # macOS host
python3 scripts/run_render_soak.py --seconds 600 --simulator <udid> --angle     # simulator, + projectM
```
