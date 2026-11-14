# Implementation Plan: QA-003 Visual Diff Tolerances

**Branch**: `feature/qa-003` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/133-qa-003-visual-diff/spec.md`

## Summary

A reusable comparator, `ImageDiff`, joins QA-002's plain-Swift `GoldenImages` target in
`Packages/RenderGoldens`. It compares two `GoldenImage`s under an `ImageDiffTolerance` (colour
tolerance, allowed fraction/count, neighbourhood radius, cluster limit, optional minimum SSIM) and
returns an `ImageDiffReport` (counts, largest delta, forgiven/unmatched pixels, largest 8-connected
cluster, bounding box, SSIM, failed rules, summary). `GoldenTolerance` becomes a type alias of
`ImageDiffTolerance`; `GoldenComparison.compare` delegates to `ImageDiff` and carries the report, so
`GoldenDecision`, the scene suite and the oscilloscope golden move to the new `golden` preset without
changing their flow. `GoldenDiffImage` gains forgiven (orange) pixels and a cyan bounding-box outline.
New Linux-runnable tests cover the acceptance pair (seeded noise passes; moved, scaled, removed shape
fails), boundaries, size mismatch and determinism.

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the Mac, Xcode 26 and Linux in CI: explicit
closure types, no long untyped numeric expressions, no C stdio globals)

**Primary Dependencies**: none new; Foundation only in `GoldenImages`

**Storage**: none (diff artifacts keep QA-002's gitignored `.build/golden-diffs/`)

**Testing**: XCTest; `swift test --package-path Packages/RenderGoldens` on the host and in the Linux
shape (`-Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`);
`xcodebuild test -scheme RenderGoldens` on the QA3 iOS 27.2 simulator

**Target Platform**: iOS 26+ / macOS 15 packages, Linux CI

**Project Type**: Swift package (test infrastructure)

**Performance Goals**: each new unit test ≤ 1-2 s on the host (Debug); package suite < 1 minute

**Constraints**: deterministic (seeded `SplitMix64`-style generator in tests, integer rules); no
Metal; public API of QA-002 kept source-compatible (`GoldenTolerance(channelThreshold:allowedFraction:)`,
`.qa002`, `allowedPixels(total:)`, `GoldenComparisonResult` initializer)

**Scale/Scope**: images up to 16,384² (QA-002 limit); goldens are 128 × 96 and 256 × 192

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs only | Foundation only. Pass. |
| VI Modular boundaries | Stays inside the test-infrastructure package; no app, engine or capture change. Pass. |
| VII Real-time safety | Test-only code. Pass. |
| IX Dependencies and licenses | No dependency; SSIM and connected components written here. Pass. |
| X Evidence-based quality | Acceptance pair, boundaries and golden suite on host, Linux shape and simulator; device left `{device}`. Pass. |

Post-design re-check: unchanged (all Pass).

## Project Structure

### Documentation (this feature)

```text
specs/133-qa-003-visual-diff/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/image-diff.md
└── checklists/requirements.md
```

### Source Code

```text
Packages/RenderGoldens/
├── Sources/GoldenImages/
│   ├── ImageDiff.swift            # new: tolerance, report, comparator (colour, forgiveness, clusters, bbox)
│   ├── ImageDiffSSIM.swift        # new: luma SSIM, 8×8 windows stride 4
│   ├── GoldenComparison.swift     # GoldenTolerance = ImageDiffTolerance; compare delegates; result carries report
│   └── GoldenDiffImage.swift      # forgiven colour, bounding-box outline
├── Tests/RenderGoldensTests/
│   ├── ImageDiffFixtures.swift    # new: seeded generator, shape fixture, noise/move/scale/remove
│   ├── ImageDiffAcceptanceTests.swift  # new: QA-003 acceptance pair
│   ├── ImageDiffBoundaryTests.swift    # new: boundaries, size mismatch, determinism, report, diff image
│   ├── GoldenArtifacts.swift      # diff image + report from the comparison's tolerance
│   ├── GoldenRenderSuiteTests.swift, OscilloscopeGoldenTests.swift  # explicit `.golden`
│   └── GoldenComparisonTests.swift     # QA-002 tests pinned to `.qa002`
└── README.md                      # rule, presets, diff colours
```

**Structure Decision**: extend `GoldenImages` (research D1); no new package.

## Complexity Tracking

None.
