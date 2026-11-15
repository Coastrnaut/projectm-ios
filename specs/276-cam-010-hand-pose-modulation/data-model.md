# Data Model: CAM-010 Hand Pose Modulation

- **HandFeature** (enum, raw = source suffix): present, x, y, pinch, open, size, second, secondX, secondY.
- **HandFeatureValues**: nine Doubles, each 0…1 when read (`value(_:)` clamps; non-finite reads neutral). Neutral:
  present 0, x 0.5, y 0.5, pinch 0, open 0, size 0, second 0, secondX 0.5, secondY 0.5.
- **HandJointPoint**: x, y (normalised picture coordinates, origin bottom-left), confidence 0…1.
- **HandObservationSample**: wrist, thumbTip, indexTip, middleTip, ringTip, littleTip, middleKnuckle (each a
  HandJointPoint). Memory only.
- **HandPoseFrame**: hands (0…2 samples), aspect (upright width ÷ height). Memory only; dropped after ingest.
- **HandFeatureTracker**: values, held target, held envelope, last time, snap flag. Transitions: reset → neutral;
  ingest(frame) → step toward held target, then hold the new target.
- **CameraAnalysisConsent**: switchKey, consentKey, isOn, hasConsent, sheetShown.
- **CameraVisualModulation**: modulator, base inner radius / gap, usesFace / usesHand, value readers.
