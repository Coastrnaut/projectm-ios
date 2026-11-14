# Feature Specification: QA-003 Visual Diff Tolerances

**Feature Branch**: `feature/qa-003` (spec directory `133-qa-003-visual-diff`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (QA-003-T01-T16 verified on the Mac host, the Linux shape and the QA3 iOS 27.2 simulator; QA-003-T17 `{device}` open; CI pending)

**Input**: User description: "Implement QA-003 (Visual diff tolerances) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Compare GPU images with
configurable color and geometry thresholds." Acceptance, verbatim: "One-pixel noise passes while major
geometry regression fails." P1, effort M, depends on QA-002 (golden render scenes, integrated).
Verification: unit tests and the simulator during development; device in the FINAL stage."

Identifiers carry the roadmap ID: requirements `QA-003-R1…`, success criteria `QA-003-S1…`, tasks
`QA-003-T01…`. QA-002 (golden render scenes, `specs/066-qa-002-golden-render-scenes`, ADR-0030) owns
the scenes, goldens, manifest, record policy and diff artifacts; VIS-003 reuses them for the
oscilloscope's generator goldens.

## Baseline: what exists today (audit of 2026-11-14, commit `e8dde5c`)

| Area | Today | Gap for this row |
|---|---|---|
| Golden comparison | `GoldenComparison.compare` in `Packages/RenderGoldens/Sources/GoldenImages` with one fixed rule, `GoldenTolerance.qa002`: equal, or same size and at most ⌊0.1 % × pixels⌋ pixels whose largest channel difference exceeds 2/255. The file says QA-003 replaces the rule. | Colour only: no geometry rule, no way to tell scattered noise from a moved shape, no per-comparison configuration beyond the two numbers. |
| Callers | `GoldenRenderSuiteTests` (7 scenes × 2 resolutions; equal pixel hashes short-cut to "identical") and `OscilloscopeGoldenTests` (VIS-003). Both feed the result into `GoldenDecision.decide` and on failure `GoldenArtifacts.write` (expected, actual, diff PNG, summary). | No other image comparator in the repository: CMP and FX tests (Compositor, VisualGenerators) assert a few sampled pixels with `accuracy:`, not whole images. |
| Failure report | One line: changed pixels, pixels above the threshold, allowed count, largest channel difference; `GoldenDiffImage` marks grey/yellow/red/magenta. | No bounding box of differences, no geometry figures, no mark for differences forgiven as small shifts. |
| CI evidence | Last green run (43554817807): every compared capture "identical" except `material-plasma-256x192-f7`, 4 pixels changed by 1/255. | — |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Where does the reusable comparator live? → A: In QA-002's plain-Swift `GoldenImages` target (`Packages/RenderGoldens`), as `ImageDiff`. It already owns the RGBA image type, builds and tests on Linux, and is the only image-comparison code in the repository; a new package would duplicate `GoldenImage`. `GoldenTolerance` becomes a name for the new tolerance type so QA-002's API and tests keep compiling.
- Q: Which geometry rule? → A: Two parts, both on pixels that exceed the colour tolerance. (1) Neighbourhood forgiveness: such a pixel is forgiven when, within radius r (Chebyshev), the other image has a matching pixel in both directions (a one-pixel rasterization shift). (2) Cluster limit: the remaining "unmatched" pixels are grouped into 8-connected clusters, and the largest cluster must not exceed a limit. Scattered one-pixel noise makes clusters of 1-2 pixels; a moved, scaled or missing shape makes one large cluster. Both are exact integer rules, cheap and deterministic.
- Q: Is SSIM part of the pass rule? → A: It is computed and reported (mean SSIM of luma over 8 × 8 windows, stride 4) and a minimum can be set per comparison, but no preset sets one: a single white pixel on black drops its window's SSIM to about 0.05, so SSIM alone would fail the acceptance's noise case.
- Q: What do QA-002's goldens use? → A: A new preset `ImageDiffTolerance.golden`: QA-002's colour rule unchanged (2/255, ⌊0.1 %⌋ pixels) plus radius-1 forgiveness and a largest cluster of at most 8 pixels. It never fails a capture CI passes today (CI's only difference is 1/255, inside the colour tolerance), forgives one-pixel shifts and now fails a compact blob QA-002 would have let through. Exact match stays where determinism is guaranteed: equal pixel hashes are still reported "identical", and the run-to-run determinism checks keep comparing pixel hashes (preset `.exact` for comparator users).
- Q: How is the failure reported? → A: The report gives the largest channel difference, pixels over the colour tolerance, pixels forgiven as shifts, unmatched pixels and the allowed count, the largest cluster and its limit, the bounding box of unmatched pixels (or of all exceeding pixels when none is unmatched), SSIM, and which rules failed. The diff image adds orange for forgiven pixels and a cyan outline around the bounding box; QA-002's artifact folder and attachments carry it.
- Q: Size mismatch? → A: Always a failure with both sizes in the report; never a crash; the diff image keeps QA-002's magenta outside the overlap.
- Q: Which tolerance does a comparison use when the caller names none? → A: `golden` for new `ImageDiff` callers (the documented default); `GoldenComparison.compare` keeps an explicit tolerance parameter whose default becomes `golden` too, so both QA-002 callers move in one place.
- Q: When neighbourhood forgiveness looks for a "matching" pixel, which threshold counts as a match? → A: The same per-channel colour tolerance as the colour rule (largest channel difference ≤ tolerance); one number, no second knob.
- Q: How much may the comparator cost? → A: Linear in pixels times (2r + 1)² for exceeding pixels only; one 256 × 192 comparison of the acceptance fixtures must finish well inside the 1-2 s unit-test budget on the host (Debug), so no extra performance gate is added.

## User Scenarios & Testing *(mandatory)*

The "users" are developers and agents who change the renderer and the reviewers who read golden
failures.

### User Story 1 - Noise passes, geometry regressions fail (Priority: P1)

A developer runs a comparison of a GPU frame against its golden. Scattered one-pixel differences
(rounding, dithering, single bad pixels) pass. A shape that moved by several pixels, grew or shrank,
or disappeared fails, even when the number of changed pixels is small compared to the image.

**Why this priority**: It is the row's acceptance.

**Independent Test**: A seeded fixture image with shapes; add salt-and-pepper noise and small
per-channel deltas: passes. Move a shape, scale it or remove it: fails.

**Acceptance Scenarios**:

1. **Given** a fixture and a copy with seeded single-pixel noise, **When** compared with the default
   tolerance, **Then** the comparison passes.
2. **Given** a fixture and a copy with a shape moved by many pixels, scaled or removed, **When**
   compared with the same tolerance, **Then** the comparison fails and names the geometry rule.
3. **Given** a copy shifted by exactly one pixel, **When** compared with radius-1 forgiveness,
   **Then** it passes.

---

### User Story 2 - Thresholds are configurable per comparison (Priority: P1)

A test author chooses the colour tolerance (per channel, 0-255), the allowed share or count of pixels
over it, the neighbourhood radius, the largest allowed cluster and an optional minimum SSIM, or uses a
documented preset (exact, QA-002's rule, golden default).

**Independent Test**: The same image pair passes or fails as each threshold crosses its boundary.

**Acceptance Scenarios**:

1. **Given** a difference exactly at the colour tolerance, **When** compared, **Then** it passes; one
   step above, it counts as exceeding.
2. **Given** exactly the allowed number of exceeding pixels, **When** compared, **Then** it passes; one
   more fails.

---

### User Story 3 - A failure is readable (Priority: P2)

A reviewer gets a summary with the largest delta, the count over threshold, the bounding box of the
differences and the largest cluster, plus a diff image in the test's attachments and the diff folder.

**Acceptance Scenarios**:

1. **Given** a failing comparison, **When** the report is printed, **Then** it contains the figures
   above and the failed rules.
2. **Given** a failing golden capture, **When** the suite writes artifacts, **Then** the diff image
   marks forgiven pixels, failing pixels and the bounding box.

---

### User Story 4 - The QA-002 goldens move to the comparator (Priority: P2)

The golden scene suite and the oscilloscope golden use the comparator with the conservative golden
preset and still pass on the host, the simulator and CI.

### Edge Cases

- Size mismatch: fails with both sizes; no crash.
- An all-different image: fails every rule; the bounding box is the whole image.
- Tiny images (smaller than one SSIM window): SSIM is not computed and not required.
- Alpha differences count like colour differences (QA-002 rule).
- Results are symmetric in expected/actual for counts and identical between runs.

## Requirements *(mandatory)*

### Functional Requirements

- **QA-003-R1**: A reusable comparator MUST compare two 8-bit RGBA images of equal size and return a
  result with a pass/fail decision and a report; its logic MUST be plain Swift that builds and is
  tested on Linux.
- **QA-003-R2**: Colour threshold: a pixel exceeds when its largest channel difference (alpha
  included) is above a per-comparison tolerance (0-255); a comparison MUST allow at most a configured
  number of non-forgiven exceeding pixels, given as a fraction of the pixels (rounded down) and/or an
  absolute count (the smaller applies).
- **QA-003-R3**: Neighbourhood forgiveness: with radius r > 0, an exceeding pixel MUST be forgiven when
  the expected pixel matches (largest channel difference within the same colour tolerance) some actual
  pixel within r and the actual pixel matches some expected pixel within r; r = 0 disables it.
- **QA-003-R4**: Cluster limit: the unmatched pixels MUST be grouped into 8-connected clusters, and the
  comparison MUST fail when the largest exceeds a configured limit (no limit when unset).
- **QA-003-R5**: Structure: mean SSIM of luma over 8 × 8 windows (stride 4) MUST be reported when both
  sides are at least 8 × 8, and the comparison MUST fail below a configured minimum when one is set.
- **QA-003-R6**: Size mismatch MUST fail with both sizes reported.
- **QA-003-R7**: The report MUST include the largest channel difference, changed, exceeding, forgiven
  and unmatched pixel counts, the allowed count, the largest cluster, the bounding box, SSIM and the
  list of failed rules, as one readable summary.
- **QA-003-R8**: A diff image MUST show unchanged pixels dimmed, within-tolerance changes, forgiven
  pixels, unmatched pixels scaled by size, the bounding box outline, and the outside of the overlap for
  differently sized images.
- **QA-003-R9**: Presets MUST exist and be documented: `exact` (no difference), `qa002` (QA-002's rule
  unchanged), `golden` (QA-002's colour rule plus radius 1 and cluster ≤ 8); `golden` is the default
  when a caller names no tolerance.
- **QA-003-R10**: QA-002's scene goldens and VIS-003's oscilloscope golden MUST compare with `golden`;
  equal pixel hashes MUST still report "identical", and the run-to-run determinism checks MUST stay
  exact.
- **QA-003-R11**: The comparator MUST be deterministic: the same inputs give the same result.
- **QA-003-R12**: Tests MUST fit the owner's budgets (a unit test about 1-2 s, the package suite under
  1 minute on the host).

### Key Entities

- **Tolerance**: colour tolerance, allowed fraction and count, radius, cluster limit, minimum SSIM.
- **Diff report**: the figures of QA-003-R7 and the decision.
- **Diff image**: the reviewable picture of QA-003-R8.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **QA-003-S1**: Seeded single-pixel noise (salt-and-pepper within the allowed count, ±2 deltas
  everywhere) passes with `golden`; a shape moved by 12 pixels, scaled by 1.5 or removed fails.
- **QA-003-S2**: Boundary cases behave as specified: at the colour tolerance passes, all-different
  fails, size mismatch fails, exactly the allowed count passes and one more fails.
- **QA-003-S3**: Two comparisons of the same pair give equal results.
- **QA-003-S4**: Every QA-002 and VIS-003 golden still passes on the macOS host and the iOS 27.2
  Simulator with the new preset.
- **QA-003-S5**: The package suite passes on the host and the Linux shape in under 1 minute.

## Assumptions

- Physical devices have no goldens (QA-002); comparator use on a device is a FINAL-stage check.
- CMP and FX tests keep their sampled-pixel asserts; moving them would add a RenderGoldens dependency
  to packages that do not need whole images. Any future whole-image test uses `ImageDiff`.
- The comparator works on 8-bit images only; float images are converted by the caller (REC-001 already
  produces 8-bit sRGB).
