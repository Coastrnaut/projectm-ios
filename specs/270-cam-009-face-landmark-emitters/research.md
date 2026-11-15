# Research: CAM-009 Face Landmark Emitters

## CAM-009-D1 Detector

- **Decision**: Vision `VNDetectFaceLandmarksRequest` on the camera's `CVPixelBuffer` through `VNImageRequestHandler`
  with the picture's orientation (as CAM-008-D2). The request is created lazily on the first analysis, never before
  the gate opens; the largest face (bounding-box area) is measured. Its `roll` and `yaw` (radians, optional), its
  bounding box (normalised, origin bottom-left), and the `innerLips`, `leftEye`, `rightEye` regions'
  `normalizedPoints` (relative to the box) are copied into a plain `FaceObservationSample`; the observation is then
  dropped.
- **Rationale**: public, on-device, no bundled model; landmarks give mouth and eye openness directly.
- **Alternatives**: ARKit face tracking (TrueDepth only, a second session: rejected by the brief); `VNDetectFaceRectanglesRequest` (no mouth/eyes).

## CAM-009-D2 Frame path

- **Decision**: A generic `CameraPictureAnalyzing` protocol in CameraLayer (`offer(_:rotation:position:)`, `reset()`);
  providers hold one `pictureAnalyzer` beside CAM-008's `personMasker` and offer each stored picture. The camera
  layer's `stop()` calls `reset()`. No second capture session; the analyzer never starts the camera.
- **Alternatives**: a second `AVCaptureVideoDataOutput` (rejected: second consumer of the session, more power).

## CAM-009-D3 Gate placement (defence in depth)

- **Decision**: `FaceTrackingGate` (pure) = switch ∧ consent ∧ camera authorized. The coordinator sets
  `analyzer.isEnabled` from it; the analyzer refuses offers while disabled (no schedule step, no detector creation).
  The detector factory is called only inside a started analysis, so with the gate closed the factory count stays 0.
- **Rationale**: the acceptance test counts factory calls and detects with a spy.

## CAM-009-D4 Rate

- **Decision**: `FaceAnalysisSchedule`: an analysis starts when none is in flight and at least the interval passed
  since the last start, on an injected nanosecond clock. Interval 1/15 s; 1/10 s under Low Power Mode or a power
  profile below 60 fps; paused at serious/critical heat (`FaceTrackingRate.interval`).

## CAM-009-D5 Normalisation and smoothing

- **Decision**: as spec Clarifications. Values are smoothed with MOD-005's `AudioFeatureEnvelope.step`: 80 ms toward a
  measured face, 300 ms toward neutral when no face. The first face after a reset snaps. Non-finite measurements
  hold the previous value. Degenerate eye or lip regions (fewer than 2 points, zero width) hold.
- **Mirroring**: x is flipped when the shown picture is mirrored (front camera default), so "left" is the viewer's left.

## CAM-009-D6 Consent storage and reinstall

- **Decision**: `settings.camera.faceTrackingConsent` (Bool) and `settings.camera.faceTracking` (Bool) in the app's
  UserDefaults: deleted with the app (reinstall re-asks), excluded from the FILE-005 backup (restoring can never
  grant consent), removed by FILE-011 erase (derived from the excluded list) and by `-uitestResetNotice`.

## CAM-009-D7 Privacy proofs

- Container snapshot (file paths and sizes) before and after a stubbed run: identical.
- Scene capture and performance report encoded during a run contain no `face`/`landmark` key and no value.
- Source scan: the face files contain no `print(`, `NSLog`, `os_log`, `FileManager`, `write(to:`, `URLSession`, and
  every `Logger` interpolation is `privacy: .private`.
- `check_network_symbols` and `check_compliance.py` on the build.

## CAM-009-D8 Where values are live

- **Decision**: face sources are read by the native spectrum host's modulation (as CAM-011); the camera runs only in
  the Camera visual, so in this release the sources read neutral outside it. Documented in the spec's Assumptions; a
  native visual with a camera layer is future work (CMP-015).
