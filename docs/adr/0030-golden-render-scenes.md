# ADR-0030: Golden Render Scenes

- **Status**: Accepted 2026-11-13 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: QA-002 (`specs/066-qa-002-golden-render-scenes`)
- **Constitution**: I (public APIs), VI (modular boundaries), IX (no new dependency, licensed
  content), X (evidence: simulator results are regression evidence for the simulator only)
- **Builds on**: ADR-0028 (scene document), ADR-0013 (compositor), REC-001 (frame capture), FX-019
  (composite flash guard), ADR-0024 (graphs are imported, never executed)
- **Number**: the next free number on `autonomous/integration` when written (0029 was the highest);
  0015, 0016, 0025 and 0026 stay unused. If a parallel feature takes 0030 first, renumber at
  integration.

## Context

QA-002 asks to "store small licensed test scenes with deterministic seeds and clocks", accepted when
"renderer changes produce reviewable image diffs at fixed resolutions". Until now renderer checks were
per-feature signatures (a few means and sampled pixels per layer) that a reviewer cannot look at.

## Decisions

1. **Package.** `Packages/RenderGoldens`: plain-Swift `GoldenImages` (Linux-tested) and Metal
   `SceneRenderHarness`; scenes in `Scenes/`, goldens in `Goldens/<class>/` with `manifest.json`.
2. **Scenes.** Seven canonical SCN-001 documents authored in this repository (MIT): photo, material,
   graph, circular and linear spectra, a three-layer stack with opacity and transforms, a strobe for
   the composite flash guard, and a text layer. Photos are generated from the run's seed; graphs are
   the repository's SHD-002 examples, imported through SHD-011; text uses the system font. No camera,
   video or projectM/ANGLE content (live input, movie timing, separate renderer).
3. **Determinism.** 8 frames at 60 Hz from 1 s, seeded audio bands (SplitMix64), flash guard on.
   Frame 0 is a warm-up: asynchronous photo and text loads are awaited and the composite flash
   history is reset after it, so captured frames never depend on loading speed (found when the
   simulator raced the photo load). Captured: frame 7 (and 6 for the strobe).
4. **Capture.** REC-001's path: the compositor's post-guard capture, converted to 8-bit sRGB straight
   alpha, PNG with no metadata. Fixed resolutions 128 × 96 and 256 × 192.
5. **Platform classes.** `macos` (host GPU) and `ios-simulator`, each with its own goldens; GPU name
   and OS are informational. A physical device has no class (pending the device stage, QA-011).
   Text scenes compare only on the recorded OS major.minor.
6. **Comparison (until QA-003).** Equal pixel hashes pass; otherwise same size and at most
   ⌊0.1 % × pixels⌋ pixels above 2/255 in any channel (`GoldenTolerance.qa002`).
7. **Artifacts.** On failure: expected, actual, diff (grey unchanged, yellow within, red above,
   magenta outside the overlap) and a summary, attached to the XCTest result (kept always) and
   written to `Packages/RenderGoldens/.build/golden-diffs/<class>/` (`GOLDEN_DIFF_DIR` overrides).
8. **Recording.** Only with `GOLDEN_RECORD=1` (simulator: `TEST_RUNNER_GOLDEN_RECORD=1`); refused
   (failure, nothing written) when `CI` or `GITHUB_ACTIONS` is set; unchanged pixels leave files
   untouched; missing goldens fail. A GPU-free integrity check (files, hashes, completeness, < 2 MB)
   runs everywhere, including Linux CI.

## Consequences

- Any renderer change that moves pixels shows up as images in review; intended changes are
  re-recorded on purpose and reviewed as PNG diffs in the commit.
- Host and iOS 27.2/26.5 simulators gave identical pixels across runs; the iOS 26.5 simulator matched
  the iOS 27.2 goldens exactly. CI's virtualized GPU and OS 26 host were not checked before the first
  push: if they differ beyond the tolerance, the job's xcresult carries the diffs, and QA-003's
  configurable tolerance or an extra class is the follow-up.
- A freshly created simulator pays a one-time cold start (6-17 s) on the first photo render; later
  runs take about 0.2 s per scene.
