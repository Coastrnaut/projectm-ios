# Data Model: QA-002 Golden Render Scenes

## GoldenImage (GoldenImages)

- `width`, `height` (> 0), `rgba: [UInt8]` (width × height × 4, straight alpha, 8-bit sRGB, rows top-down).
- `pixelSHA256`: hex SHA-256 of `rgba` (lowercase, 64 characters).

## GoldenTolerance / GoldenComparison

- Tolerance: `channelThreshold: Int` (2), `allowedFraction: Double` (0.001); `allowedPixels(total)` =
  ⌊fraction × total⌋. `GoldenTolerance.qa002` is the only value in this row (QA-003 replaces it).
- Result: `outcome` ∈ { `identical`, `withinTolerance`, `sizeMismatch`, `exceedsTolerance` },
  `changedPixels` (any difference), `exceedingPixels` (> threshold), `maxChannelDifference`,
  `allowedPixels`; `passed` is true for the first two outcomes; `summary` is one line.

## GoldenSceneRun (catalog)

- `name` (file `Scenes/<name>.scene.json`), `seed: UInt64`, `frameCount` (8), `startNanoseconds`
  (1 s), `intervalNanoseconds` (16,666,667), `capturedFrames` (sorted, each ≥ 1 and < frameCount),
  `audio` ∈ { `silent`, `seededBands(count)`, `alternating(count)` }, `reduceFlashing` (true),
  `osSensitive` (text scenes), `photos: [storeID: GoldenPhotoRecipe]`.
- `GoldenPhotoRecipe`: width, height, seed → RGBA pixels (opaque gradient with seeded stripes).
- Resolutions: `GoldenResolution.all` = 128 × 96 and 256 × 192.

## GoldenManifest (one per platform class)

- `formatVersion` (1), `platform` (`macos` | `ios-simulator`), `recordedOS` ("27.2"), `recordedGPU`
  (informational), `entries` sorted by (scene, width, frame).
- Entry: `scene`, `frame`, `width`, `height`, `file` (`<scene>-<w>x<h>-f<frame>.png`),
  `pixelSHA256`, `fileSHA256`, `osSensitive`.
- Canonical JSON: sorted keys, two-space indentation, trailing newline (byte-stable rewrites).

## GoldenPlatformClass / GoldenRecordPolicy

- Class from the build: macOS → `macos`; iOS simulator → `ios-simulator`; anything else → nil (pending).
- Policy from the environment: `compare` (default), `record` (`GOLDEN_RECORD=1`), `refused`
  (record asked while `CI` or `GITHUB_ACTIONS` is set).

## GoldenIntegrityIssue

- `missingFile(file)`, `fileHashMismatch(file)`, `unlistedFile(file)`, `missingEntry(scene, width,
  frame)`, `duplicateEntry(file)`, `platformMismatch`, `overBudget(bytes, limit)`. The budget is
  2,000,000 bytes for all classes' PNGs and manifests together.

## Diff artifact set

- Folder `<diffRoot>/<class>/<scene>-<w>x<h>-f<frame>/` with `expected.png`, `actual.png`, `diff.png`,
  `summary.txt`; one line per failure appended to `<diffRoot>/<class>/summary.txt`.
