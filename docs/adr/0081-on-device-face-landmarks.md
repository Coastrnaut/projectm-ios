# ADR-0081: Face Landmark Emitters Run Only After Explicit Consent, On the Device, From Pictures the Camera Already Captures

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: CAM-009 (`specs/270-cam-009-face-landmark-emitters`)
- **Constitution**: I (public APIs), VI (modular boundaries), X (evidence); Privacy constraints
- **Extends**: ADR-0017 (camera pictures stay in memory), ADR-0063 (the reviewed exception for person masking)

## Context

CAM-009 asks to "generate normalized on-device face landmark events, opt-in", accepted when the "consent gate
precedes capture and no face frames leave device". Face measurements are more sensitive than a person mask: the
default must be off, the user must agree with knowledge of what is measured, and nothing derived from a face may be
kept or leave the device.

## Decision

1. **Consent gate.** A separate "Face tracking" switch in Settings › Camera, off by default. Turning it on shows an
   explanation sheet; only its confirmation stores consent (`settings.camera.faceTrackingConsent`) and turns the
   switch on. Analysis runs only while switch ∧ consent ∧ camera authorization hold (`FaceTrackingGate`). The
   analyzer refuses every picture while the gate is closed, and the face detector is created lazily inside the first
   allowed analysis, so before consent no Vision face request exists.
2. **No new capture.** Face tracking adds no capture session, never starts the camera and asks for no permission: it
   receives the Camera visual's own pictures through a generic provider hook (`CameraPictureAnalyzing`, beside
   CAM-008's masker). No Info.plist key is added.
3. **Only scalars, only in memory.** Vision's face landmarks (public, on the device) measure the largest face; only
   eight normalized scalars are derived (present, x, y, size, roll, yaw, mouth, eyes) and smoothed. Pictures are
   released after each analysis; observations, landmark points and face prints are never stored, logged, exported,
   recorded, put in scenes or diagnostics, or sent. Saved frames and recordings contain the camera picture as before.
4. **Bounded cost.** At most 15 analyses a second (10 under reduced power), one in flight, on a utility queue; paused
   when the device is serious or critical warm.
5. **Visible.** The camera badge reads "Face tracking" while faces are analysed (iOS shows its own camera indicator);
   the performance overlay says only "Face tracking on/off".
6. **Consent stays on this device.** Both keys are excluded from settings backups, erased with Settings and deleted
   with the app, so restoring a backup or reinstalling never turns face tracking on.

## Consequences

- The acceptance test counts detector creations and detections with a spy factory: zero before consent, zero
  without camera access, zero after switching off.
- Face sources feed the native spectrum's modulation; the camera runs only in the Camera visual today, so outside it
  the sources read their neutral values until a native visual can carry a camera layer.
- Real faces, the indicator and the frame-rate cost need a device (CAM-009-T16).
