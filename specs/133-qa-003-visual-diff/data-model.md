# Data Model: QA-003 Visual Diff Tolerances

All types are value types in `GoldenImages` (plain Swift, `Sendable`, `Equatable`).

## ImageDiffTolerance (alias `GoldenTolerance`)

| Field | Type | Rule |
|---|---|---|
| `channelThreshold` | Int | 0-255 (clamped); a pixel exceeds when its largest channel difference is above it |
| `allowedFraction` | Double | ≥ 0; allowed unmatched pixels = ⌊fraction × total⌋ |
| `maxExceedingPixels` | Int? | when set, the allowed count is the smaller of this and the fraction's |
| `neighborhoodRadius` | Int | ≥ 0 (clamped 0-8); 0 disables forgiveness |
| `maxClusterPixels` | Int? | when set, the largest 8-connected unmatched cluster must not exceed it |
| `minimumSSIM` | Double? | when set and SSIM is computable, SSIM below it fails |

Presets: `exact`, `qa002`, `golden` (research D5). `allowedPixels(total:)` keeps QA-002's meaning.

## ImageDiffBoundingBox

`minX`, `minY`, `maxX`, `maxY` (inclusive), `width`, `height`; description `x a-b, y c-d`.

## ImageDiffReport

| Field | Meaning |
|---|---|
| `expectedSize`, `actualSize` | (width, height) of each side |
| `totalPixels` | pixels compared (larger side on mismatch) |
| `changedPixels` | any difference |
| `exceedingPixels` | above the colour tolerance |
| `forgivenPixels` | exceeding but matched within the radius |
| `unmatchedPixels` | exceeding − forgiven |
| `allowedPixels` | from the tolerance |
| `maxChannelDifference` | 0-255 (255 on a size mismatch) |
| `largestCluster` | pixels in the largest 8-connected unmatched cluster |
| `boundingBox` | of unmatched, else exceeding pixels; nil when none |
| `ssim` | Double? |
| `failures` | `[ImageDiffRule]`: `size`, `count`, `cluster`, `ssim` (empty = pass) |
| `passed`, `identical`, `summary` | derived |

## GoldenComparisonResult (QA-002, extended)

Keeps `outcome`, `changedPixels`, `exceedingPixels` (now: unmatched pixels, i.e. the pixels that count
against the allowance; equals QA-002's figure when radius = 0), `maxChannelDifference`, `allowedPixels`,
`totalPixels`; adds optional `report: ImageDiffReport?`. Outcome: `identical`, `withinTolerance`,
`sizeMismatch`, `exceedsTolerance` (any of count, cluster, ssim). `summary` is the report's summary when
present.
