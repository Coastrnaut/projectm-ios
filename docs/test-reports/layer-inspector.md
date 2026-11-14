# CMP-015 Layer Inspector — test report (2026-11-14)

Spec: `specs/118-cmp-015-layer-inspector/`; decision: ADR-0044. All results are from the iOS 27.2
simulator (`CMP15 iPhone 17`, Xcode 27.2) on the Mac Studio. Simulator results are never device evidence
(Constitution X); no device run was made.

## Audit and scope

- Compositor stacks: Camera `[camera, spectrum.circular]`, Photo `[photo, spectrum.circular]`, Video
  `[video, spectrum.circular]`, Text `[spectrum.circular, text]`, each with default composites. Circular
  and Linear Spectrum draw one layer without the compositor; projectM and Oscilloscope have no layer.
- No live scene had a user-editable layer before this row. The inspector edits the drawn layers of the
  Photo, Video and Text scenes and lists carried and native-spectrum layers read-only.

## Acceptance

| Criterion | Evidence | Result |
|---|---|---|
| S1 selecting each of three layers shows its values | `LayerInspectorTests.testSelectingEachOfThreeLayersShowsThatLayersValues`; `LayerInspectorUITests.testSelectingEachLayerShowsItsParameters` (seed: photo 80 % fit Fit, spectrum 60 % Screen X 0.25, material 50 % Add) | pass |
| S2 undo of opacity and transform on layer 2 restores values and pixels | `LayerInspectorTests.testOpacityAndTransformEditsOnLayerTwoUndoToThePriorValues` (byte-equal document); `LayerInspectorRenderTests.testUndoOfOpacityAndTransformOnLayerTwoRestoresTheFramePixelForPixel` (64 × 64 read-back equal byte for byte) | pass |
| S3 one drag = one undo step | `testOneSliderDragIsOneUndoStepAndUndoRestoresTheExactValue`, `testAnAnchorDragOnTheDefaultFitIsOneStep`; UI `testOpacityDragIsOneStepAndUndoRestoresIt` | pass |
| S4 help for every parameter | `testEveryParameterHasHelpFromTheOneTable`; the UI test opens the Blend Mode popover | pass |
| S5 solo/mute not in undo or the saved scene | `testSoloAndMuteNeverEnterTheHistoryOrTheSavedScene`, `testSoloHidesTheOtherLayerWithoutAnUndoStep` | pass |
| S6 placement edit re-renders no cached layer | render test: the photo's picture `wasReused` after the spectrum's edit | pass |
| S7 type-check thresholds | `-warn-long-function-bodies=300 -warn-long-expression-type-checking=150`: no warning in a new file; slowest new function 26 ms (`LayerDetailView.showsFit`), `LayerInspectorView` under 20 ms after it stopped referencing `AppCoordinator` (was 159 ms) | pass |

GPU performance: only the CMP-013 reuse proxy on the simulator; device frame timing is pending a device.

## Runs

| Command (`-only-testing:`) | Result | Time |
|---|---|---|
| `projectM-iOSTests/LayerInspectorTests` + `LayerInspectorRenderTests` | 12 pass | 1.7 s |
| `projectM-iOSTests` (all) | 537 pass | 13.3 s of tests |
| `projectM-iOSUITests/LayerInspectorUITests` | 2 pass | 17.2 s, 19.9 s |
| `SceneUndoUITests`, `PhotoLayerUITests`, `SettingsUITests` | 6 pass | 15-36 s each |
| `check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events` | exit 0 | — |
| `test_scripts.py` | 153 tests OK (1 skipped) | 19 s |

PosterBoard reports: 25 before, 25 after.

## Not verified

- Device runs (VoiceOver by hand, GPU timing). Show cues do not carry composites (ADR-0044 item 7).
