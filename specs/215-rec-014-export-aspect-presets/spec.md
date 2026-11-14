# Feature Specification: REC-014 Export aspect presets

**Feature Branch**: `feature/rec-014` (spec directory `215-rec-014-export-aspect-presets`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement REC-014 (Export aspect presets) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Offer portrait, square, landscape and custom safe dimensions."
Acceptance, verbatim: "Export dimensions match preset and never exceed device memory cap." P1,
depends on REC-003 (integrated); REC-005 (quality profiles) and REC-006 (frame rate) are integrated too."

Identifiers carry the roadmap ID: requirements `REC-014-R1…`, success criteria `REC-014-S1…`, tasks
`REC-014-T01…`, research decisions `REC-014-D1…`.

## Baseline: what exists today (audit of 2026-11-14, commit `cd89f309`)

| Area | Today |
|---|---|
| Geometry | `RecordingGeometry` (REC-003-D3): the drawable cropped to even dimensions (last column/row) is the pixel buffer's size; the video keeps the drawable's aspect and only scales down so its long side fits the profile's cap (rounded to even). |
| Scaling | The writer scales source → output with `AVVideoScalingModeResizeAspect` when the sizes differ (`VideoFileWriter.outputSettings`). |
| Profiles | REC-005: Draft 1280, Standard 1920, High 2560 px long side; Max = the drawable's own size (`nativeLongSide` 16 384, i.e. no cap). Never upscales (REC-005-R2). The plan (`RecordingProfilePlan`) carries the geometry; Settings rows show "W×H · codec · rate · fps". |
| Frame rate | REC-006: Profile default / 24 / 30 / 60, resolved together with the profile at Record (`RecordingFrameRateCatalog.resolve`). |
| Hosts | Five visual hosts feed the recorder's pixel buffer from their own Metal output, copied from the top-left at the pixel buffer's size (compositor `encodeOutput`, the spectra's drawable blit). |
| Aspect | None: a recording always has the screen's aspect. No upper size limit other than the profile's long side and the encoder's `canEncode`. |
| Output aspect elsewhere | CMP-015/UIX-007 (output aspect correction) fit the *picture inside the screen*; they do not change what the recording's frame is. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the conservative, local-first option.

- Q: Which aspect choices? → A: Five: Match screen (the default; today's behaviour), Portrait 9:16, Square 1:1, Landscape 16:9, and Custom W×H. A user who never opens the setting records exactly as before.
- Q: How does a screen-shaped picture become another aspect: crop to fill or letterbox? → A: Crop to fill, centred. The whole recorded frame is picture (what portrait/square/landscape social formats expect), and the picture is never stretched (same scale on both axes). Letterboxing was rejected: on a phone, a landscape export would be mostly black bars around a small picture.
- Q: Does a preset upscale? → A: No (REC-005-R2 kept). The output is at most the size of the centred crop of the drawable; a landscape export from a portrait phone is therefore narrower than 1920 (for example 1152×648 from a 1179×2556 screen).
- Q: How does the aspect combine with the quality profile? → A: The profile's long-side size still caps the output's long side (Draft 1280, Standard 1920, High 2560, Max no profile cap); codec, bit-rate rule and frame rate are unchanged.
- Q: What is the "device memory cap"? → A: A documented per-device-class limit on the encoded frame size, applied to every recording (also Match screen): devices with less than 4 GiB of memory at most 2560 px per side and 3 686 400 pixels (2560×1440); others at most 4096 px per side and 8 294 400 pixels (3840×2160); never above the GPU's maximum texture side. Every current screen fits under its class's cap, so Match screen recordings are unchanged on real devices.
- Q: Which custom sizes are valid? → A: Width and height each even and between 128 and 4096 px; an odd value is rounded down to even and an out-of-range value is clamped, both when typed. A valid custom size that exceeds the crop, the profile size or the memory cap is reduced (same aspect, even sides) and the user is told, in Settings and at Record.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Record in a social format (Priority: P1)

A user opens Settings → Recording aspect, picks Portrait 9:16 (or Square, or Landscape) and records;
the file has exactly that aspect, filled with the centred picture, at the largest size the profile
and the screen allow.

**Why this priority**: It is the roadmap row: portrait, square and landscape presets whose export
dimensions match the preset.

**Independent Test**: A pure geometry test sweeps each preset × profile × representative drawables
(phone portrait, iPad landscape, small) and asserts the exact expected dimensions, even sides, exact
aspect and never above the cap; one short real encode reads back a file whose dimensions match the plan.

**Acceptance Scenarios**:

1. **Given** Square is selected with Standard on a 1179×2556 screen, **When** the user records, **Then** the file is 1178×1178 (the crop is the full width, not upscaled).
2. **Given** Portrait 9:16 with Standard on a 2048×2732 screen, **When** the user records, **Then** the file is 1080×1920.
3. **Given** Landscape 16:9 with Standard on a 1179×2556 screen, **When** the user records, **Then** the file is 1152×648 and shows the centre band of the picture, undistorted.
4. **Given** Match screen (the default), **When** the user records, **Then** the file is exactly what REC-005 recorded.

---

### User Story 2 - Custom size, kept safe (Priority: P1)

A user types a custom size such as 1080×1350; the recording is that size when it fits, and a smaller
size with the same aspect, never above the device's memory cap, when it does not, with a notice.

**Independent Test**: The same geometry sweep includes custom sizes that fit, that exceed the crop,
and that exceed the cap on each device class.

**Acceptance Scenarios**:

1. **Given** Custom 1080×1350 with Standard on a 2048×2732 screen, **When** the user records, **Then** the file is 1080×1350.
2. **Given** Custom 4096×4096 on a device of the compact class, **When** the user records, **Then** the file is at most 2560 per side and at most 3 686 400 pixels, the aspect is kept, and "Recording at W×H: Custom size reduced to fit this device." is shown and announced (row X9c).
3. **Given** the user types 1081 in the width field, **When** the field is committed, **Then** it reads 1080.

---

### User Story 3 - See the result before recording (Priority: P2)

Each aspect row in Settings shows the size it will record with the selected profile on this screen;
the profile rows show sizes for the selected aspect.

**Acceptance Scenarios**:

1. **Given** Square is selected, **When** Settings is opened, **Then** the Square row is checked and its detail reads "1178×1178" on a 1179×2556 screen with Standard; the Standard profile row shows 1178×1178 too.
2. **Given** the user picks Square, **When** the app is relaunched, **Then** Square is still selected.

### Edge Cases

- A drawable smaller than the aspect's smallest even size (for example 16:9 needs 32×18): no picture to record (the profile is unavailable with "No picture to record.").
- The drawable changes size during a recording: the recording stops as before (REC-003 size check on the drawable).
- A custom size whose reduced aspect has no exact even multiple below the limits (for example 1918×1080 reduced): both sides are scaled by the same factor and rounded down to even; the aspect differs by at most one rounding step (2 px per side).
- The encoder refuses the planned size: REC-005's fallback to a lower profile applies (with the same aspect).
- External display or rotation: the drawable's current size is used at Record; the crop is centred on it.

## Requirements *(mandatory)*

### Functional Requirements

- **REC-014-R1**: The app MUST offer an aspect choice with exactly these values: Match screen (default), Portrait 9:16, Square 1:1, Landscape 16:9, Custom W×H.
- **REC-014-R2**: Match screen MUST record exactly what REC-005/REC-006 record today, except for the memory cap (R5).
- **REC-014-R3**: Portrait, Square and Landscape MUST produce a file whose width:height equals the preset's ratio exactly, with even sides, the largest such size whose long side is at most the profile's long-side size, which is no larger than the centred crop of the drawable in either dimension, and within the memory cap.
- **REC-014-R4**: The recorded frame MUST be the centred crop of the shown picture at the output's aspect, scaled uniformly (no distortion, no bars).
- **REC-014-R5**: Every output MUST be at most the device class's memory cap (side and pixel count) and the GPU's maximum texture side: compact (< 4 GiB memory) 2560 px and 3 686 400 px; regular 4096 px and 8 294 400 px.
- **REC-014-R6**: A custom size MUST be validated when entered: each side even (odd rounds down) and within 128...4096 px (clamped). It MUST record at exactly that size when it fits R3's limits; otherwise it MUST be reduced by one uniform factor, sides rounded down to even, and Settings and Record MUST say so ("Recording at W×H: Custom size reduced to fit this device." at Record, row X9c).
- **REC-014-R7**: The choice and the custom size MUST be stored on the device (keys `settings.recording.aspect`, `settings.recording.customWidth`, `settings.recording.customHeight`; absent or unknown reads as Match screen and 1080×1350), reset by the UI-test reset, erased with the Settings category and left out of the library backup.
- **REC-014-R8**: Settings MUST show a "Recording aspect" section under "Recording frame rate": one row per choice with the size it records now (or why it cannot), a checkmark on the selected one, and, for Custom, width and height fields; VoiceOver MUST read each row with its size and selected state.
- **REC-014-R9**: The quality profile and frame-rate rows and Record's plan MUST use the selected aspect; codec, bit-rate rule and frame rate stay the profile's (the bit rate of Standard follows the output's pixels).
- **REC-014-R10**: A running recording MUST keep the aspect it started with.
- **REC-014-R11**: The crop MUST add no work to the frame loop beyond today's copy (the encoder's own scaler crops).

### Key Entities

- **Aspect choice**: Match screen, Portrait, Square, Landscape, or Custom with a validated even size.
- **Output cap**: the device class's maximum side and pixel count, limited by the GPU's texture side.
- **Recording geometry**: source size (drawable, even), output size, and whether the output crops to fill.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **REC-014-S1**: For every preset × profile × representative drawable (and custom sizes), the planned output equals the expected dimensions exactly, both sides are even, presets have the exact ratio, custom sizes keep their ratio within one rounding step, and 100% of outputs are within the device class's cap.
- **REC-014-S2**: A short real recording with a preset reads back with exactly the planned width and height.
- **REC-014-S3**: With Match screen selected, every existing recording test passes unchanged.
- **REC-014-S4**: The aspect picker UI test selects Square and sees it selected in under 30 s.
- **REC-014-S5**: On a device, a Square and a Portrait recording play back at the planned size with the centre of the picture (device stage, `{device}`).

## Assumptions

- `AVVideoScalingModeResizeAspectFill` makes the writer's scaler crop the source's centre to the output's aspect; the encode fixture checks the size and that the centre (not a bar) is what is written.
- Physical memory (`ProcessInfo.physicalMemory`) is a sufficient public proxy for the device class.
- Rotation of the recorded frame, per-recording crop offsets, letterboxing and upscaling are out of scope.
