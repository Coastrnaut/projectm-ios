# ADR-0087: Hand Pose Modulation Runs Only After Its Own Consent, On the Device, and the Camera Visual Evaluates Bindings for What It Draws

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: CAM-010 (`specs/276-cam-010-hand-pose-modulation`)
- **Constitution**: I (public APIs), VI (modular boundaries), X (evidence); Privacy constraints
- **Extends**: ADR-0081 (face landmark emitters), ADR-0017 (camera pictures stay in memory), ADR-0063

## Context

CAM-010 asks to "map on-device hand joints to scene parameters", accepted when "recorded synthetic pose frames drive
deterministic parameter changes". It is a second camera analysis next to CAM-009's face tracking, and CAM-009
recorded (CAM-009-D8) that camera-derived values reached no parameter in the app: only native visuals evaluate
bindings, and the camera runs only in the Camera visual.

## Decision

1. **Own consent gate.** A separate "Hand tracking" switch in Settings › Camera, off by default, with its own
   explanation sheet and stored consent (`settings.camera.handTrackingConsent`); face consent never counts. The gate
   (switch ∧ consent ∧ camera authorization) closes the analyzer; Vision's hand pose request is created lazily inside
   the first allowed analysis.
2. **Shared analysis, one hook.** CAM-009's analyzer becomes a generic `CameraFeatureAnalyzer` (face and hand are two
   instances, each with its own gate, schedule, queue and failure state) and its consent logic a shared
   `CameraAnalysisConsent`. The camera's one analysis slot holds a fixed `CameraPictureAnalyzerGroup` of both. No
   capture session, permission or Info.plist key is added.
3. **Only scalars, only in memory.** Up to two hands; seven joints each are copied and dropped after measuring nine
   normalized scalars (present, wrist x/y, pinch, openness, size, second hand present and x/y). Joints below
   confidence 0.3 are ignored. Nothing is stored, logged, exported, recorded, put in scenes or diagnostics, or sent.
4. **Deterministic smoothing.** MOD-005's one-pole, hold-then-step, so values at a time depend only on the pose
   sequence and its times, not on frame cadence. Recorded synthetic poses stand in for Vision in the tests.
5. **The Camera visual evaluates bindings for what it draws.** It owns the native visuals' `AudioFeatureModulator` over
   the visual catalog, loaded with the scene's bindings and replaced on modulation-matrix edits, advanced on its frame
   clock with band, face and hand values, and applied to its circular spectrum's inner radius and gap. Other targets
   are carried without effect there; triggers stay with the native visuals. This closes CAM-009-D8 for both features
   without new parameter IDs.
6. **Bounded cost and visible.** At most 15 analyses a second (10 reduced, paused warm); the badge says "Hand
   tracking"; the overlay says only "Hand tracking on/off". Keys excluded from backups, erased with Settings.

## Consequences

- Face and hand sources now move the Camera visual's ring while the camera runs; the native visuals still read them
  only when a camera picture is analysed, which never happens while a native visual is shown.
- Two Vision handlers may run on the same picture when both features are on; their frame-rate cost and real hands are
  device checks (CAM-010-T17).
