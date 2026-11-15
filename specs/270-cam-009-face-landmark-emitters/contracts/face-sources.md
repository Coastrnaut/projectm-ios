# Contract: CAM-009 face sources and gate

## F1 Source IDs

`audio.face.present`, `audio.face.x`, `audio.face.y`, `audio.face.size`, `audio.face.roll`, `audio.face.yaw`,
`audio.face.mouth`, `audio.face.eyes`. `AudioFeatureSource(id:)` parses exactly these; `id` round-trips. Bindings,
layers and threshold triggers accept them; `ExpressionCatalog` refuses them. Without face values in the frame each
reads its neutral value.

## F2 Values

`FaceFeatureValues.value(_:)` is finite and within 0…1 for any stored value (non-finite → neutral).

## F3 Gate

No `FaceLandmarkDetecting` is created and no detection runs unless `FaceTrackingGate.allowsAnalysis`. Disabling the
analyzer bumps its generation (a result in flight is dropped) and resets the values to neutral.

## F4 Provider hook

`CameraFrameProvider.pictureAnalyzer: (any CameraPictureAnalyzing)?` (default none). A provider offers each picture it
stores; `CameraLayerSource.stop()` calls `reset()`. The analyzer never retains a picture after its analysis.

## F5 Privacy

The analyzer and coordinator write no file, log no value and use no network API. Only the two preference keys are
stored.
