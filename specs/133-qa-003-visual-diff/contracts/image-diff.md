# Contract: ImageDiff (QA-003)

Module `GoldenImages` (product `RenderGoldens`).

## I1 — Compare

```swift
ImageDiff.compare(expected: GoldenImage, actual: GoldenImage,
                  tolerance: ImageDiffTolerance = .golden) -> ImageDiffReport
```

1. Different sizes → `failures == [.size]`, `maxChannelDifference == 255`, no other rule evaluated.
2. Per pixel: d = largest channel difference. `changed` if d > 0; `exceeding` if d > channelThreshold.
3. Radius r > 0: an exceeding pixel at p is forgiven iff ∃ q within Chebyshev distance r with
   d(expected[p], actual[q]) ≤ t and ∃ q' within r with d(actual[p], expected[q']) ≤ t.
4. `unmatched` = exceeding − forgiven. Fails `.count` when unmatched > allowedPixels.
5. Fails `.cluster` when `maxClusterPixels` is set and the largest 8-connected unmatched cluster exceeds it.
6. Fails `.ssim` when `minimumSSIM` is set, SSIM is computable (both sides ≥ 8 × 8) and below it.
7. Deterministic and symmetric in counts when r = 0.

## I2 — Summary

One line: `PASS|FAIL [rules]: <changed>/<total> changed, <exceeding> over <t>/255 (<forgiven> forgiven
as shifts, <unmatched> unmatched, allowed <allowed>), max delta <d>/255, largest cluster <c>
[(limit <L>)], box <x a-b, y c-d>|none, SSIM <s>|n/a`. Size mismatch: `FAIL [size]: expected WxH, actual WxH`.

## I3 — Golden adoption

- `GoldenTolerance` == `ImageDiffTolerance`; `GoldenComparison.compare(expected:actual:tolerance:)`
  default `.golden`; result carries `report`.
- Scene suite and oscilloscope golden pass `.golden` explicitly; equal pixel hashes stay `identical`.
- `GoldenDiffImage.make(expected:actual:tolerance:)` default `.golden`: grey unchanged, yellow within
  tolerance, orange forgiven, red unmatched (128 + 2 × (d − t), cap 255), magenta outside the overlap,
  cyan bounding-box outline over grey pixels.
