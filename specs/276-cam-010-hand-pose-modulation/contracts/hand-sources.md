# Contract: Hand sources (CAM-010)

- **H1 IDs**: `audio.hand.<present|x|y|pinch|open|size|second|secondX|secondY>` parse to `.hand(feature)` and back;
  unknown suffixes do not parse. Expressions refuse them (`unknownIdentifier`).
- **H2 Values**: `AudioFeatureSource.hand(f).value(in:)` reads `frame.hand?.value(f)`, else the neutral value; always finite,
  0…1.
- **H3 Detector**: `HandPoseDetecting.detect(_:rotation:) throws -> HandPoseFrame?` (nil: no hand). Called on the
  analyzer's queue only; returns only copied joints.
- **H4 Hook**: `CameraPictureAnalyzerGroup(_ analyzers:)` forwards every `offer` and `reset` to each member in order.
- **H5 Gate**: with the gate closed, `offer` returns before the schedule; the detector factory is never called.
- **H6 Camera modulation**: `CameraVisualModulation.load(_:)` takes the scene's bindings; `resolve(bands:timeNanoseconds:)`
  returns the circular spectrum's modulated inner radius and gap, nil when neither is bound.
