# Contract: golden render suite (QA-002)

## G1 Scenes

Every `Packages/RenderGoldens/Scenes/<name>.scene.json` decodes with `SceneDocument.decode` without
warnings, its `encoded()` bytes equal the file's bytes, `liveState(registry:)` succeeds with the
visual + material registry, and it has exactly one `GoldenSceneCatalog` run with the same name. No
camera, video or unknown kind (the harness refuses them with `GoldenRenderError.unsupportedLayer`).

## G2 Rendering

`GoldenSceneRenderer.render(run, document, resolution)` renders `frameCount` frames at
`start + n × interval` with the run's audio and flash setting, settles asynchronous layers and resets the composite flash history after
frame 0, and returns one `GoldenImage` per captured frame. Two calls give identical pixels.

## G3 Comparison

`GoldenComparison.compare(expected:actual:tolerance:)` is pure and symmetric in its counts; it passes
only for `identical` or `withinTolerance` (data-model).

## G4 Suite behavior per capture

| Golden present | Policy | Result |
|---|---|---|
| yes, passes | any but refused | pass (record: file untouched) |
| yes, fails | compare | fail + diff artifacts |
| yes, fails | record | file and entry replaced, test passes with a note |
| no | compare | fail ("missing golden … run with GOLDEN_RECORD=1") |
| no | record | written |
| any | refused | fail, nothing written |
| OS-sensitive, recorded OS ≠ current | compare | rendered, not compared (noted) |
| no platform class (device) | any | skipped: pending device stage |

## G5 Integrity (no GPU)

`GoldenIntegrity.check(root:catalog:)` returns no issues for the committed set; it reports each
doctored case (data-model issues).

## G6 Regression proof

Rendering `material-plasma` with its `material.plasma.scale` changed from 3 to 3.5 and comparing with
the committed golden yields `exceedsTolerance`, and the artifact writer produces the three PNGs and the
summary (in a temporary folder, so it is not mistaken for a real failure).
