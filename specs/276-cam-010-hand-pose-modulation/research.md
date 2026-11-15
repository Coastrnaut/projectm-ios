# Research: CAM-010 Hand Pose Modulation

## CAM-010-D1 Detector

- **Decision**: Vision `VNDetectHumanHandPoseRequest` (`maximumHandCount = 2`) on the camera's `CVPixelBuffer` through
  `VNImageRequestHandler` with the picture's orientation (as CAM-009-D1). Created lazily inside the first analysis.
  For each observation, seven joints are read with `recognizedPoint(_:)`: wrist, thumb tip, index tip, middle tip,
  ring tip, little tip, middle MCP (location normalised, origin bottom-left; confidence). Copied into a plain
  `HandPoseFrame` with the upright picture's aspect (width ÷ height after rotation); the observations are dropped.
- **Alternatives**: ARKit body/hand (second session, rejected); `VNDetectHumanBodyPoseRequest` (no fingers).

## CAM-010-D2 One analysis hook, two analyzers

- **Decision**: CAM-009's provider slot holds one analyzer. `CameraPictureAnalyzerGroup` (CameraLayer) is an immutable
  list that forwards `offer` and `reset` to each member; the app installs a group of the face and hand analyzers. Each
  member keeps its own gate, schedule, queue and failure state, so one feature's failure or switch never touches the
  other.
- **Alternative**: one Vision handler performing both requests (one picture decode). Rejected for now: it couples the
  two gates and failure states; the cost of a second handler is measured on device (CAM-010-T17).

## CAM-010-D3 Generic analyzer

- **Decision**: `CameraFeatureAnalyzer<Tracker: CameraFeatureTracking>` holds CAM-009's state machine unchanged
  (enabled, supported, failed, mirrored, position, schedule, generation, started, detectorsMade, lazy detector, tracker)
  with a type-erased detect closure made by the factory. `FaceLandmarkAnalyzer` and `HandPoseAnalyzer` are typealiases
  with constrained convenience inits taking their detector protocols, so CAM-009's API and tests are unchanged.

## CAM-010-D4 Shared consent model

- **Decision**: `CameraAnalysisConsent` (struct: switch key, consent key, isOn, hasConsent, sheetShown) holds the
  switch/consent/sheet transitions; `CameraAnalysisStatus` the row status. Face and hand coordinators each store one;
  texts and keys differ. Gate, schedule and rate reuse CAM-009's `FaceTrackingGate`, `FaceAnalysisSchedule`,
  `FaceTrackingRate` (pure, already generic in content).

## CAM-010-D5 Normalisation

- As spec Clarifications. Distances use `dx · aspect, dy` (picture-height units). Palm length = wrist → middle MCP; a
  palm below 0.01 is degenerate (pinch, open, size hold). Joints below confidence 0.3 are dropped; a hand needs ≥ 6
  confident joints of the seven read, else it is ignored. Hands are ordered by palm length (larger first).

## CAM-010-D6 Deterministic smoothing

- **Decision**: hold-then-step: on each ingest the values first move toward the *held* target (with its envelope) over
  the elapsed time (capped 0.25 s), then the new measurement becomes the held target (a first hand after a reset snaps).
  Because MOD-005's step is exponential, k steps of dt₁…dtₖ toward a constant target equal one step of Σdt, so values
  at a time depend only on the pose sequence and its times, not on the frame cadence (up to rounding, < 1e-9).
- **Alternative**: CAM-009's step-toward-new-target (depends on the previous frame's time); kept for face to avoid
  changing shipped behaviour.

## CAM-010-D7 Closing CAM-009-D8: the Camera visual evaluates bindings

- **Finding**: bindings are evaluated only by `NativeSpectrumHost`; the Camera visual composites a camera layer and a
  circular spectrum layer and evaluates none. The visual catalog already has two parameters of that circular spectrum:
  `visual.circularSpectrum.innerRadius` and `.gap` (continuous, modulatable). Its glow is off and not catalog-driven
  in the Camera visual; person-mask strength and layer opacity are not catalog parameters (adding permanent IDs is out
  of scope).
- **Decision**: `CameraVisualModulation` owns an `AudioFeatureModulator` over `VisualParameterCatalog`, loaded with the
  scene's bindings when the Camera visual is created and replaced on every modulation-matrix edit (as the native host).
  Each composited frame it advances with the frame's bands, face and hand values at the frame's target time and writes
  the modulated inner radius and gap into the circular spectrum's configuration (allocation-free; clamped by the
  configuration); unbound, the base values return. Other targets are carried but have no effect in the Camera visual.
  LFO, band-envelope and motion sources read their no-input values there; threshold triggers stay native-only.
- **Feasibility**: one new file (~120 lines), one stored property and one call in `CameraVisualHost`, two lines in
  AppCoordinator. No refactor.

## CAM-010-D8 Storage and privacy

- `settings.camera.handTracking`, `settings.camera.handTrackingConsent`: excluded from backup, erased with Settings and
  by `-uitestResetNotice`; container snapshot, scene and report token scans, source scan as CAM-009-D7.
