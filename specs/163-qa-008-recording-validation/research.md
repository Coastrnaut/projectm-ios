# Research: QA-008 Recording Validation Suite

## QA-008-D1: Where the validator lives

- **Decision**: in `FrameRecording`, split into a plain-Swift rules file and an AVFoundation reader.
- **Rationale**: the target already holds the inspector and the timelines; CI tests it on Linux, the
  macOS host and the simulators; the app's DEBUG probe can call it.
- **Alternatives**: a test-support target (cannot be used by the app's probe, adds a target to the
  scheme); a new package (more CI wiring for no gain).

## QA-008-D2: How fixtures are written without a GPU

- **Decision**: good fixtures use `VideoFileWriter` (`@testable`) with CPU-filled 32BGRA pixel buffers
  from its own pool, and its `appendAudio` for LPCM chunks; bad fixtures the real writer cannot make use
  a test-only AVAssetWriter helper.
- **Rationale**: the corpus then exercises the app's writer settings (codec preference, no reordering,
  Rec. 709, AAC) and runs on CI's macOS VMs, which may have no usable Metal device (the REC-003/004
  Metal tests skip there).
- **Measured 2026-11-14 on the Mac Studio** (scratch experiment): AVAssetWriter refuses a repeated
  presentation time in MP4 (`-11800` / `-16364`); it writes Motion JPEG (`jpeg`) in MP4 and MOV; it
  writes a QuickTime location item (`quickTimeMetadataLocationISO6709`) that reads back as one asset
  metadata item. Without `AVVideoAllowFrameReorderingKey: false`, H.264 files come back out of order in
  file order, so the helper always disables reordering.

## QA-008-D3: Duplicate times

- **Decision**: compare times on the 1/600 s grid; the duplicate fixture writes at timescale 90,000
  with one frame 1 tick after the previous one.
- **Rationale**: the recorder writes at 1/600 s, so the grid loses nothing for its files; frames closer
  than 1/600 s are not distinct frames for any frame rate the app records.

## QA-008-D4: Finding the A/V marker

- **Decision**: flash = the first decoded frame whose centre pixel's green channel is > 128 (BGRA
  output); click = the first decoded LPCM sample with |x| > 0.3 (Float32 stereo, 44.1 kHz). Both
  moved verbatim from REC-004's test into the validator (`RecordingValidator.markerTimes`).
- **Rationale**: same thresholds as the accepted REC-004 fixture, so REC-004's acceptance is unchanged.

## QA-008-D5: Audio contiguity

- **Decision**: decode the audio track to LPCM; each buffer's start must be the previous buffer's end
  within 1 sample; count breaks and total samples.
- **Rationale**: REC-004 never pads gaps with silence, so a break in the decoded stream is a real gap.

## QA-008-D6: Reason precedence (one reason per fault)

- **Decision**: `unreadable` alone; frame count only when timestamps and duration pass; marker missing
  instead of out of tolerance; audio format/contiguity/sync skipped when the track is missing or
  unexpected; `personalMetadata` instead of `unexpectedMetadata` for the same item.

## QA-008-D7: Device export check

- **Decision**: an on-demand test gated by `QA008_RECORDING`; no script or executable product.
- **Alternatives**: a Python script (cannot decode MP4 without third-party packages); a Swift executable
  (must also build on Linux and changes the package's products).

## QA-008-D8: REC-005

- **Decision**: REC-005's `RecordingQualityFixtureTests` are not on this branch (REC-005 is being
  implemented in parallel); QA-008 does not touch them. The validator's codec and size checks can
  replace their codec/size assertions after both integrate; bit rate stays theirs.
