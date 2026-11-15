# ADR-0063: Person Silhouette Mask Uses Only the System's On-Device Segmentation, in Memory, at a Bounded Rate

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: CAM-008 (`specs/241-cam-008-person-silhouette-mask`)
- **Constitution**: I (public APIs), VI (modular boundaries), X (evidence); Privacy constraints
- **Extends**: ADR-0017 (CAM-001: camera pictures stay in memory, newest only, never analysed)

## Context

CAM-008 asks to "use on-device segmentation where supported for compositing", accepted when a "supported device
masks a person; unsupported path remains usable". ADR-0017 and CAM-001-R9 promised that camera pictures are
never written, sent or analysed. A person mask is an analysis of the picture, so that promise needs a reviewed,
narrow exception, and the extra work needs a bound.

## Decision

1. The only segmenter is Vision's `VNGeneratePersonSegmentationRequest` (public, on-device, no bundled model, no
   network), behind the `PersonSegmenting` protocol in `CameraLayer`; the camera layer itself never imports Vision.
2. Analysis runs only while the user's Person mask choice is Person or Background and the Camera visual runs.
   Pictures and masks stay in memory: the masker keeps the newest mask only, drops it on a camera stop or switch
   and when the choice is turned off, and no mask is written, logged, exported, put in a scene or diagnostics, or
   sent. A source test (`PersonMaskerTests.testMaskingSourcesNeverStoreOrSendMasks`) guards the masking files.
   No new permission: the camera permission already covers the pictures, and nothing leaves the device.
3. Bounded cost: at most one analysis in flight, at most one per two pictures (one per three under Low Power Mode or
   a PERF-008 profile below 60 fps, at `.fast` quality), on a utility-QoS queue; drawing never waits and reuses the
   newest mask. Thermal state serious or critical pauses segmentation.
4. Unsupported (including the iOS Simulator, where Vision reports "E5RT is not supported"), failed (sticky for the
   visual's life) or paused segmentation draws exactly the unmasked picture, and Settings explains why.

## Consequences

- The privacy manifest is unchanged (no required-reason API); `check_privacy_manifest.py` and
  `check_network_symbols.py` pass.
- Device behaviour (that Vision's mask is in the upright picture's orientation, real masking quality and the frame
  rate on D1) is CAM-008-T16 `{device}`; Simulator and Mac host results are never device evidence.
