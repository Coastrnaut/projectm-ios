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

Rule (until QA-003): pixels identical, or the same size with at most 0.1 % of pixels differing by more
than 2/255 in any channel. Each failed capture writes `expected.png`, `actual.png`, `diff.png` and
`summary.txt` to `.build/golden-diffs/<class>/<capture>/` (set `GOLDEN_DIFF_DIR` to change it) and
appends a line to `.build/golden-diffs/<class>/summary.txt`; the same files are attachments of the
failed test in the `.xcresult`. In `diff.png`, grey = unchanged, yellow = within 2/255, red = above
(brighter = larger), magenta = outside the overlap of differently sized images.

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
