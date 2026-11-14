# Test report: CMP-014 Compositor transition bus

Feature: `specs/116-cmp-014-compositor-transition-bus` (branch `feature/cmp-014`), ADR-0042. Host: the Mac
Studio (build machine of record), Xcode 27.2, Swift 6.4.2. Simulator results are not device evidence; no
device run was made. GPU timings are Mac timings, recorded, not asserted, and not device evidence.

## Audit (2026-11-14, commit `9688f80a`)

| Existing transition | Where | CMP-014 |
|---|---|---|
| Show cue change (SHOW-001) | `AppCoordinator+Show.swift` sets the visual through the Settings path | A cut; unchanged (no stored transition until SCN-007) |
| SHOW-00x transition rows | SCN-007 (stored transitions) and SHOW-004 (overrides) not integrated | The Codable `SceneTransitionSpec` is what they will store |
| Blackout and Restore (OUT-010, SHOW-014) | A black cover layer above the visual in each slot | Unchanged, a safety fade, stays above any bus output |
| projectM preset blend (FR-043; PRE-015 warm-up 2.5 s later) | Inside the engine | Unchanged |
| PERF-014 placeholder | 0.5 s linear safety fade | Unchanged |
| Reduce Motion (ACC-001) | `MotionPolicy` | Gains `sceneTransition(_:)`: decorative → cut |
| Flash limiting (FX-019) | Per compositor, on its composite | The bus runs one guard on every shown frame |
| Render caching (CMP-013) | Level 2 reuses an unchanged composite | Stays per scene; the bus mixes every blended frame |
| External display (OUT-001) | The slot that holds the visual view; Photo/Text/Video/Camera hosts own one compositor each | Not moved onto the bus in this row |

Two whole scene outputs never existed at once before this row: the app swaps visual hosts in the output
slot. The bus makes two scene compositors coexist inside the Compositor package.

## Baseline (CMP-014-T01)

`swift test --package-path Packages/Compositor`: 359 tests, 6 skipped, 0 failures, 8.9 s (28.3 s wall).

## Acceptance (CMP-014-T06): red → blue, 64 × 64 rgba16Float, frames 25 ms apart, 0.1 s ease in-out

| Check | Result |
|---|---|
| Progress 0 vs red alone (`composite(into:)`, same frames) | byte-identical |
| Midpoint (progress 0.5) vs (0.5, 0, 0.5, 1) | within 0.002 in every channel |
| Progress 1 and the frame after vs blue alone | byte-identical |
| Pool checked-out textures before / during / after | 2 / 5 / 2 |
| Cancel at the midpoint: next frame vs red alone; pool before / after | byte-identical; 2 / 2 |
| Interruption at the midpoint (→ green): new start vs blue alone, end vs green alone; pool | byte-identical, byte-identical; 2 / 2 |
| Dip to black: quarter, midpoint, three quarters | (0.5,0,0,0.5); all zero; (0,0,0.5,0.5) |
| `encodeOutput` into a second target | byte-identical to the shown frame |
| Output size change mid-transition | same checked-out count after, no blend target held |

## Other checks

- Clock (model tests, injected times): 0, 0.25, 0.5, 0.75, 1 exactly; uneven 60 Hz frames reach exactly 1 on
  frame 6; a pause of 499 s leaves progress unchanged; a 2 s stall counts 0.1 s; backward times ignored.
- Bus clock: pause and a 10 s gap hold progress; the transition ends on the frame whose summed shown time
  reaches the duration.
- Reduce Motion: `transition(…, reduceMotion: true)` is a cut, 0 blended frames, next frame byte-identical
  to blue alone. App: `MotionPolicy.sceneTransition` returns `.cut` with Reduce Motion on.
- CMP-013: two static (cacheable) scenes report `compositeReused` on every blended frame, and every blended
  frame differs from the one before (3 of 3).
- Flash: a 10 Hz back-and-forth crossfade between white and black scenes with Reduce flashing went through
  the mix path (23 blended frames) and the bus guard's gain fell to 0.0125.

## GPU time (CMP-014-T12, recorded only)

1920 × 1080, `bgra8Unorm_srgb`, three solid layers per scene, Reduce flashing on, 10 frames each:
single-scene median 0.195 ms, transition median 0.275 ms (`gpuEndTime − gpuStartTime`).

## Test runs

Logs: `.autonomous/logs/CMP-014/` in the worktree (not committed).

| Command | Result |
|---|---|
| `swift test --package-path Packages/Compositor --filter SceneTransition` | 20 tests, 0 failures, 0.22 s |
| `swift test --package-path Packages/Compositor` | 379 tests, 6 skipped, 0 failures, 19.1 s (30.2 s wall) |
| Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`) | 199 tests, 0 failures, 1.3 s |
| `swift test --package-path Packages/RenderGoldens` | 39 tests, 0 failures, goldens identical (0 pixels changed) |
| `swift test --package-path Packages/SceneFormat` | 112 tests, 0 failures |
| `swift test --package-path Packages/ShowControl` | 42 tests, 0 failures |
| `swift test --package-path Packages/ImportFuzz` | 15 tests, 0 failures |
| `swift test --package-path Packages/SceneArchive` | 27 tests, 0 failures |
| App unit tests, private iOS 27.2 simulator "CMP14 iPhone 17" (`-only-testing:projectM-iOSTests`), deleted afterwards | 514 tests, 0 failures, 60.1 s (2 min 45 s wall with the build); no new PosterBoard reports (25 before, 25 after) |
| `check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events` | OK |
| `python3 scripts/test_scripts.py` | 153 tests, OK (1 skipped) |

## Not verified

- No device run; GPU timings are Mac only.
- The app's live output, external display and recording are not fed from the bus in this row (ADR-0042
  decision 11); cue changes in the app stay cuts.
