# Research: CAM-008 Person Silhouette Mask

Decisions are numbered `CAM-008-D1…`. Each is the conservative, local-first option (owner rule 4).

## CAM-008-D1 — Segmenter: the system's person segmentation behind a protocol

- **Decision**: Vision's `VNGeneratePersonSegmentationRequest` (public, on-device, iOS 15+), output
  `kCVPixelFormatType_OneComponent8`, wrapped in `VisionPersonSegmenter` behind a `PersonSegmenting`
  protocol. Tests and the stand-in camera use `FixturePersonSegmenter` (returns a fixture mask, or
  reports unsupported, or throws).
- **Rationale**: public API, no bundled model, no network; the protocol keeps the camera layer free of
  Vision and makes the acceptance testable on the Simulator.
- **Rejected**: a bundled Core ML model (size, licence review, no gain); `AVCaptureDepthDataOutput`
  person matte (portrait-effects matte needs photo capture or TrueDepth, not general video).

## CAM-008-D2 — Mask space: aligned with the camera picture

- **Decision**: a mask is a coverage bitmap (8-bit, 0…255) in one of two spaces: `texture` (same
  orientation as the camera texture) or `upright` (the picture turned upright by its rotation, not
  mirrored). The shader samples it at the same coordinate it samples the picture (`t`), or at the
  upright, unmirrored coordinate (`ab` after the mirror flip). The Vision segmenter passes the
  picture's orientation so the model sees an upright person and labels its mask `upright`.
- **Rationale**: the same geometry (CAM-001 rotation, CAM-002 mirror, CAM-007 crop) then applies to the
  mask with no extra transform state; both spaces are covered by GPU tests.
- **Rejected**: the generic CMP-007…CMP-010 `CMPMask` block: it works in layer-picture coordinates
  and would need the camera geometry duplicated in the compositor.
- **Open, device**: whether Vision reports the mask in the oriented (upright) space on a device is
  confirmed by CAM-008-T16 `{device}` (the Simulator probe records the mask's aspect only).

## CAM-008-D3 — Coverage arithmetic

- **Decision**: coverage `a = m` (Person) or `1 − m` (Background), `m` the linearly sampled mask in
  0…1; output `(colour × a, a)` (premultiplied). Off uses no mask (a 1×1 placeholder is bound) and
  is the CAM-007 arithmetic unchanged; Fit's bars stay transparent before any mask term.
- **Rationale**: a mask value of 255 gives exactly the unmasked colour (S1 within 1/255).

## CAM-008-D4 — Rate, concurrency and quality

- **Decision**: `PersonMasker` starts an analysis on a camera picture only when none is in flight and
  at least `stride` pictures were offered since the last start (stride 2 normally, 3 under a reduced
  power budget or Low Power Mode). Analyses run on one utility-QoS serial queue; the camera thread
  never waits (a try-lock on the mask slot), nor does the render thread. Quality: `.balanced`
  normally, `.fast` when power-saving; `.accurate` is never used for video.
- **Rationale**: bounds the extra work to at most one analysis per two frames, with no queue growth.

## CAM-008-D5 — Availability and the unsupported path

- **Decision**: `PersonMaskAvailability`: `available`, `unsupported` (the segmenter says so before any
  analysis), `failed` (an analysis threw; sticky for the life of the masker, so a broken segmenter is
  not retried every frame), `paused` (thermal serious or critical). In every state but `available`,
  and before the first mask, the camera layer draws exactly the Off picture.
- **Rationale**: the row's "unsupported path remains usable": nothing about the camera depends on
  segmentation.

## CAM-008-D6 — Thermal and power

- **Decision**: `PersonMaskPolicy.plan(thermal:reducedPower:)`: serious/critical → paused; otherwise
  run with stride 2 `.balanced`, or stride 3 `.fast` when `reducedPower` (Low Power Mode or a power
  profile capped below 60 fps, PERF-008). The host re-evaluates on the same notifications as its
  quality governor.

## CAM-008-D7 — Privacy

- **Decision**: masks live in the masker's single slot (newest only) and the layer's upload ring;
  dropped on stop. No file, log, export, scene field or diagnostic carries a mask. No new permission
  (the camera permission already covers capture; segmentation is on-device analysis of pictures the
  user chose to show). The privacy manifest needs no new entry (no required-reason API).
  ADR-0063 records the decision.

## CAM-008-D8 — Simulator

- **Decision**: the Simulator has no camera; app tests use the stand-in camera with
  `-uitestPersonSegmenter fixture|unsupported|failing`. A package test runs the real Vision request on
  a synthetic still image and records whether it runs there; its output is never device evidence.
- **Recorded 2026-11-14 (CAM-008-T10)**: on the Mac host the request ran on a synthetic 64 × 48 still turned a
  quarter and returned a 384 × 512 mask, i.e. in the upright picture's orientation (nothing covered: no person).
  On the iOS 27.2 Simulator it threw "E5RT is not supported"; `VisionPersonSegmenter.isSupported` is therefore
  false on the Simulator, which shows the unsupported note. Neither result is device evidence (CAM-008-T16).
