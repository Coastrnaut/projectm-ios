# Test report: CMP-011 Layer groups

Feature: `specs/109-cmp-011-layer-groups` (branch `feature/cmp-011`), ADR-0039. Host: the Mac Studio
(build machine of record), Xcode 27.2, Swift 6.4.2. Simulator results are not device evidence; no
device run was made.

## Baseline (CMP-011-T01, before any change, commit `b75c685f`)

`swift test --package-path Packages/Compositor`: 296 tests, 3 skipped (benches), 0 failures, 7.8 s.
`swift test --package-path Packages/SceneFormat`: 101 tests (run on an exported copy of the commit;
the one failure there was the QA-004 meta-test not finding app files outside the copy, an artefact of
the copy, not of the code).

## Model (`LayerGroupStackTests`, 12 tests, 0.002 s; host and Linux shape)

Make and ungroup keep every child's own settings (nothing baked in); every refusal (`emptyGroup`,
`layerAlreadyGrouped`, `unknownLayer`, `layersNotContiguous`, `unknownGroup`, `indexOutOfRange`,
`splitsGroup`) leaves the stack equal to before; the membership rule (insert between two members
joins, at the run's edge does not; moved out leaves, moved between members joins, reordered inside
stays; duplicate joins; removing the last member removes the group; a one-member group moves with its
layer); `moveGroup` moves the run and refuses a split; restore refusals (`duplicateGroup`,
`unknownGroup`, `emptyGroup`, `groupNotContiguous`) and group IDs continuing after the largest
restored one; equality includes groups; the composed matrix against hand values (move, 2× zoom about
the centre, a quarter turn on 16:9 keeping pixel lengths); an identity group gives the layer's own
matrix bit for bit; the isolation rule and opacity clamping.

## GPU read-back (`LayerGroupCompositeTests`, 9 GPU tests + 1 opt-in bench, 0.3 s)

96 × 64 `rgba16Float` output. `BoxLayer` blits an opaque 12 × 12 box into its output-sized picture.
A red box (local move −0.05, +0.1) and a green box (local scale 1.25, rotation 0.4) in one group;
each box's alpha-weighted centroid against G(a)·L(a) applied to its centre (CPU):

| Group transform | Child | Predicted centre (px) | Measured centre (px) | Error (px) |
|---|---|---|---|---|
| identity | red | (17.20, 36.40) | (17.20, 36.40) | 0.002 |
| identity | green | (52.51, 14.91) | (52.51, 14.91) | 0.002 |
| move right ¼ | red | (41.20, 36.40) | (41.20, 36.40) | 0.002 |
| move right ¼ | green | (76.51, 14.91) | (76.51, 14.91) | 0.002 |
| scale ½ | red | (32.60, 34.20) | (32.70, 34.00) | 0.223 |
| scale ½ | green | (50.26, 23.45) | (50.26, 23.45) | 0.004 |
| rotate 0.3 rad | red | (17.28, 27.10) | (17.28, 27.10) | 0.002 |
| rotate 0.3 rad | green | (57.36, 17.00) | (57.36, 17.01) | 0.003 |
| move + scale 0.75 + rotate −0.5, anchor (0.4, 0.6) | red | (33.33, 41.51) | (33.33, 41.51) | 0.005 |
| move + scale 0.75 + rotate −0.5, anchor (0.4, 0.6) | green | (48.84, 14.66) | (48.84, 14.67) | 0.005 |

Every error is under 1 px (CMP-011-S1; the 0.22 px is a 6 px box with bilinear edges). In every case
each child's own transform is unchanged in the stack and in what the compositor draws
(`shownTransform`), and the group is flattened (`isolatedGroupDraws` 0).

| Check | Result |
|---|---|
| Identity group vs no group; one child in a moved group vs that move as its own transform | bit-identical pixels |
| Group opacity 0.5, two overlapping opaque boxes over blue, vs CPU isolated reference | max error 0.0; overlap (0, 0.5, 0.5, 1); all 400 overlap pixels differ from per-child multiplication |
| Disabled group; group opacity 0 | only the backdrop (exact); children still `.rendered` |
| Group at opacity 1 (normal children) vs the same layers ungrouped | bit-identical, 0 isolated draws |
| Group at opacity 0.999 (isolated) vs flattened | within 0.002 (half-float rounding) |
| Group fade 1 → 0.2 over 0.1 s | monotonic, reaches 0.2; group picture created once; 0 pool misses over 3 steady frames |
| Masked child (circle) in a group moved and rotated | 0 non-zero pixels outside the moved mask, 0 inside violations, centre followed the group |
| Screen child in a group over a grey layer below the group | max error 5.6e-17 vs CPU reference (isolated); 800 pixels differ from pass-through; 1 isolated draw, 1 blend draw |
| Fitted portrait photo in a moved group vs the move as its own transform | bit-identical |

Mutation check: with group placement and isolation switched off in `Compositor.swift`, the fit, mask,
one-child, opacity, flatten and fade tests failed (at least 6 of the 9; the printed list was cut short).

## GPU time (CMP-011-S5; Mac, not device evidence)

`CMP011_BENCH=1 swift test -c release -Xswiftc -DDEBUG --package-path Packages/Compositor --filter
testBenchGroup`: four solid layers (opacity 0.8, scaled 0.6) at 1920 × 1080, 120 frames after 10
warm-up frames, GPU start to end per command buffer:

| Case | Median (ms) | p95 (ms) | Isolated draws |
|---|---|---|---|
| 4 layers, ungrouped | 0.301 | 0.603 | 0 |
| 4 layers, group flattened (opacity 1) | 0.301 | 0.492 | 0 |
| 4 layers, group isolated (opacity 0.5) | 0.360 | 0.467 | 1 |

## Scene format (`SceneGroupTests`, 9 tests, 0.06 s; host and Linux shape)

Decode → encode byte-identical with two groups (one moved, one disabled at 0.5 with an unknown
field); load → capture → load a fixed point and capture → encode → decode → capture byte-identical;
children's own transforms equal the saved ones after load and after moving the group, saving and
reloading; a scene without groups writes no `groups` and is unchanged, version 1; defaults, opacity
clamping (`valueClamped`) and unknown group fields kept; 9 groups and 9 children are `tooMany`.
Degenerate structures — missing child, repeated child, layer in two groups, gap, empty, repeated ID,
ID 0, nested child object — each give `invalidGroup` warnings at the expected paths, appear in the
SCN-012 report under "Damaged file" as problems with "Fix layer groups", open as is, are drawn
ungrouped, are kept verbatim through decode → encode and load → capture, and are fixed (idempotently,
layers untouched) by `repairGroups`. Repair keeps a group's good references; a layer removed by
`removeBrokenLayers` leaves no dangling reference; a group of only unknown-kind layers is preserved.

## Regression

| Command | Result |
|---|---|
| `swift test --package-path Packages/Compositor` | 318 tests, 4 skipped (benches), 0 failures (8.3 s in XCTest) |
| Compositor, Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`) | 176 tests, 0 failures (1.3 s) |
| `swift test --package-path Packages/SceneFormat` (QA-004 meta-test included) | 110 tests, 0 failures (2.7 s) |
| SceneFormat, Linux shape | 110 tests, 0 failures (2.2 s) |
| `swift test --package-path Packages/RenderGoldens` | 39 tests, 0 failures (goldens unchanged) |
| `swift test --package-path Packages/ImportFuzz` | 15 tests, 0 failures |
| `swift test --package-path Packages/ShowControl` | 31 tests, 0 failures |
| `swift test --package-path Packages/SceneArchive` | 27 tests, 0 failures |
| App unit tests (`-only-testing:projectM-iOSTests`, dedicated iOS 27.2 simulator) | see below |
| `check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events` | OK |
| `python3 scripts/test_scripts.py` | 153 tests, 1 skipped, OK |

No UI was added: no screen edits a layer stack's composite settings (re-checked 2026-11-14).
