# Feature Specification: REC-001 Still Frame Capture

**Feature Branch**: `feature/rec-001` (spec directory `055-rec-001-still-frame-capture`)

**Created**: 2026-11-13

**Status**: Implemented 2026-11-13 (REC-001-T01-T18 verified on the Mac: host, Linux shape and iOS 27.2 simulator; T19-T20 `{device}` open)

**Input**: User description: "Implement REC-001 (Still frame capture) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Save current composited frame as
PNG or HEIF to Files." Acceptance, verbatim: "Export dimensions and alpha policy match selected
format." P0, effort M, depends on CMP-001 (integrated). Verification: fixture encoding + simulator +
device LAST stage. Implement only REC-001; REC-002 to REC-016 (batch export, video recording, audio
mux, Photos export, share sheet) must be able to build on it."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `REC-001-R1…`, success criteria `REC-001-S1…`, tasks `REC-001-T01…`. Requirements
of other features are cited by their own IDs: CMP-001 (compositor, ADR-0013), FX-019 (strobe
envelope, composite flash guard), FR-072 (Reduce flashing), FR-085 (Paused), FR-065 (what the app may
store), FR-070 (accessibility), OUT-001 (external display), OUT-010-R1 to R13 (output blackout),
PERF-011 (presentation loss), CAM-001 / CAM-012 (Camera visual), MED-001 / MED-002 (Photo, Video).

## Baseline: what exists today (audit of 2026-11-13, commit `8a7a923`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| projectM (ANGLE) | Renders into the window surface through the FX-019 post-pass; a test-only pixel readback exists. | No user-facing capture. |
| Native spectra | Draw straight into a display-only drawable (cannot be read back). | No readback path. |
| Camera, Photo, Video | CMP-001 compositor: linear half-float composite, flash guard, output pass into a display-only drawable. | No capture of the composite. |
| Export | Preset export (PRE-*) uses the system Files exporter. | No image export, no image encoder. |
| Recording (REC-*) | Nothing (no AVAssetWriter pipeline). | REC-001 is the first REC row. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: While the output is blacked out (OUT-010), should Save Frame capture the hidden live picture or refuse? → A: Refuse with a notice, also while the restore waits or fades in. During a blackout nobody sees the picture, and the blackout exists to hide it; a capture would record exactly what the user chose to hide, and a picture taken during the fade would not match the screen. Restoring takes one tap. Rejected: capture the hidden live frame on explicit action (records hidden content; needs a second confirmation for little value); capture the black cover (a useless file).
- Q: Should a PNG keep the frame's transparency or always be opaque like the screen? → A: Keep it, straight (unpremultiplied) alpha, but only when some pixel's coverage is below 1; a fully opaque frame is written without an alpha channel. PNG is the lossless format people use to reuse a picture over other content, and over black it reproduces the screen exactly, so nothing shown is lost. HEIF has no alpha (flattened onto black), so the two formats' alpha policies differ as the row's acceptance expects. Rejected: always opaque PNG (discards the compositor's coverage that later rows such as REC-002 can use); always RGBA (an alpha channel of all 255 doubles nothing but adds size and confuses viewers).
- Q: At what size is the frame saved: the drawable's pixels, the view's points, or a fixed 1× / 2× scale? → A: The drawable's pixel size, exactly the pixels the visual drew on the output it is on (device or external display), including the quality governor's render scale. That is the "current composited frame" with no resampling, so dimensions are testable and nothing is invented by upscaling. Rejected: points (loses detail); a fixed scale (resampling; another rendering pass that would change frame timing); re-rendering at a higher size (export presets belong to REC-014).
- Q: Where does the file go: the system Files exporter only, or also the photo library? → A: The Files exporter only (the user picks the folder; iCloud Drive and other providers appear there). No photo library permission or usage description in this row: "Export to Photos" is REC-011, with its own opt-in, explicit action and privacy review. Rejected: saving to Photos now (a new permission prompt and privacy surface not asked for by the row); writing into the app's Documents (a stored copy the user did not ask for, FR-065).
- Q: Should HEIF be 8-bit or 10-bit? → A: 8-bit sRGB, quality 0.9. Every drawable the app presents is 8-bit sRGB, so 10 bits would carry no information the screen showed, and 8-bit HEIF opens everywhere (including older Files previews). Rejected: 10-bit from the half-float composite (more than was shown; compatibility risk on iOS 26 viewers); lossless HEIF (PNG already covers lossless).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Save the frame on screen as a picture (Priority: P1)

A user sees a picture they like. They tap Save Frame in the visualizer's controls, choose PNG or
HEIF, and the system's Files sheet opens with a ready file; they choose a folder (On My iPhone,
iCloud Drive, a connected drive) and the picture of the frame that was on screen is saved there.

**Why this priority**: It is the row's observable behavior.

**Independent Test**: A UI test with a DEBUG option that replaces the Files sheet with a temporary
folder: tap Save Frame, choose PNG; the file read back is a PNG at the visual's pixel size.

**Acceptance Scenarios**:

1. **Given** a visual is running on the visualizer, **When** the user taps Save Frame and chooses
   PNG, **Then** the Files sheet offers a PNG file of the next frame shown, at the size the visual
   is drawn in pixels.
2. **Given** the same, **When** the user chooses HEIF, **Then** the Files sheet offers a HEIF file
   of that frame at the same size, with no transparency.
3. **Given** the Files sheet is open, **When** the user cancels it, **Then** nothing is saved, the
   app keeps no copy, and the visual never stopped.
4. **Given** any visual (projectM, Circular or Linear Spectrum, Camera, Photo, Video), **When** the
   user saves a frame, **Then** the file shows what that visual showed (after the flash limiter).

---

### User Story 2 - The file matches its format's rules (Priority: P1)

The saved picture has exactly the frame's pixel dimensions; a PNG keeps the frame's transparency
where the visual has any (and shows exactly the screen's picture when viewed over black); a HEIF has
no transparency and is the screen's picture (transparent parts flattened onto black). Colors match
the screen.

**Why this priority**: It is the row's acceptance criterion.

**Independent Test**: Fixture encoding: a 64 × 48 frame with known colors and a half-transparent
region is encoded as PNG and HEIF and read back: width, height, alpha presence and pixel values
match the policy within the stated tolerances.

**Acceptance Scenarios**:

1. **Given** a frame with a half-transparent region, **When** it is saved as PNG, **Then** the PNG
   has an alpha channel, the region's alpha is 128 ± 1 and its colors are the unpremultiplied
   colors ± 1/255.
2. **Given** the same frame, **When** it is saved as HEIF, **Then** the HEIF has no alpha channel
   and the region is the color over black within the documented lossy tolerance.
3. **Given** a fully opaque frame, **When** it is saved as PNG, **Then** the PNG has no alpha
   channel.
4. **Given** any saved file, **When** its properties are read, **Then** it carries no location,
   device, date or camera details, at most an sRGB color profile.

---

### User Story 3 - Saving never surprises the audience or the user (Priority: P2)

While the output is blacked out (OUT-010), or the visualization is paused, Save Frame does not
capture a picture the user cannot see; it explains why. Saving never changes what the external
display shows and never stalls the visual.

**Why this priority**: Capture must not reveal or record what the user chose to hide, and must not
disturb a show.

**Independent Test**: Coordinator tests: with blackout on, or paused, Save Frame returns a refusal
with its notice and no file; with a display connected, the capture comes from the visual on that
display.

**Acceptance Scenarios**:

1. **Given** the output is blacked out or restoring, **When** the user taps Save Frame, **Then** no
   capture is made and a notice says to restore the output first.
2. **Given** the user paused, **When** the user taps Save Frame, **Then** no capture is made and a
   notice says to resume first.
3. **Given** the visualization is on an external display, **When** the user saves a frame, **Then**
   the file is the frame drawn on that display, at that display's pixel size, and the display shows
   nothing of the capture (no flash, no overlay).

### Edge Cases

- No frame arrives within 1 s of the request (the visual stalled or lost presentation): the request
  fails with a notice; nothing is saved.
- A second Save Frame while one is in progress: ignored (one capture at a time).
- The visual changes, or the app goes to the background, while a capture is pending: the pending
  capture is cancelled with a notice.
- The device cannot encode HEIF: HEIF is not offered; PNG is.
- A very large drawable (iPad Pro external 4K display): capture holds at most one frame's pixels in
  memory (about 66 MB for 3840 × 2160 half-float) and releases them when the file is handed over.
- Reduce flashing on: the saved frame is the limited frame that was shown (the limiter is not
  bypassed for capture).
- The Camera visual: saving captures the camera's picture as shown, only on the user's tap.
- VoiceOver: Save Frame and the format choice have labels; the result is announced as a notice.

## Requirements *(mandatory)*

### Functional Requirements

- **REC-001-R1**: The visualizer's controls MUST offer Save Frame for every visual. It asks for a
  format: PNG, and HEIF when the device can encode it.
- **REC-001-R2**: Capture MUST happen only on the user's explicit Save Frame action; nothing is
  captured, encoded or stored otherwise.
- **REC-001-R3**: The captured frame MUST be the next frame the visual presents after the request,
  as shown: after the flash limiter or composite flash guard (FX-019) and any glow, at the drawable's
  pixel size (the size the visual is drawn at, including the quality governor's render scale, on the
  output it is on: the device or the external display, OUT-001).
- **REC-001-R4**: Capture MUST NOT change the frame shown, the frame rate beyond the capturing frame,
  the visual's state, the flash history, or the audio.
- **REC-001-R5**: PNG policy: 8 bits per channel, sRGB. If any pixel of the frame has coverage
  below 1, the PNG has an alpha channel with straight (unpremultiplied) color; otherwise it has no
  alpha channel. Opaque visuals (projectM, native spectra) are always written without alpha. Viewed
  over black, a PNG reproduces the screen's picture.
- **REC-001-R6**: HEIF policy: 8 bits per channel, sRGB, no alpha channel; partially transparent
  pixels are flattened onto black (the picture as shown); lossy quality 0.9.
- **REC-001-R7**: Color conversion MUST be exact by rule: linear premultiplied color is clamped,
  unpremultiplied (for PNG with alpha) and encoded with the sRGB transfer function, rounded to the
  nearest 8-bit value; frames already sRGB-encoded at 8 bits are copied without re-encoding.
- **REC-001-R8**: Readback, conversion and encoding MUST run off the main thread; the main thread
  only starts the request and receives the result.
- **REC-001-R9**: The result MUST be typed: format, pixel width, pixel height, whether alpha is
  present, and the encoded bytes; or a typed failure with a user-visible reason.
- **REC-001-R10**: The file MUST be handed to the system Files exporter; the user chooses the
  location. The app MUST NOT write to the photo library in this row, and MUST keep no copy after the
  exporter finishes or is cancelled.
- **REC-001-R11**: The file MUST carry no metadata beyond the image and its sRGB color profile: no
  location, date, device, camera, user or app identifiers. The suggested file name is
  "Visualizer Frame" plus the local date and time; the user may change it in the Files sheet.
- **REC-001-R12**: While the output is blacked out or restoring (OUT-010), Save Frame MUST refuse
  with a notice ("Restore the output to save a frame") and capture nothing.
- **REC-001-R13**: While the user paused (FR-085), Save Frame MUST refuse with a notice ("Resume to
  save a frame").
- **REC-001-R14**: A request MUST fail with a notice if no frame is presented within 1 s, if the
  visual changes or the app loses presentation (PERF-011) before the frame; one request at a time.
- **REC-001-R15**: Conversion and encoding rules MUST be testable without a device or the simulator,
  on fixture frames; the pure conversion builds on Linux.
- **REC-001-R16**: Only public, documented platform APIs (Constitution I), no new Metal shader
  source, no networking; builds for iOS 26 and 27.
- **REC-001-R17**: Save Frame, the format choice and the notices MUST have accessibility labels
  (FR-070).

### Key Entities

- **Capture format**: PNG or HEIF, with its alpha policy and quality.
- **Captured pixels**: width, height and one of: linear premultiplied half-float RGBA (compositor
  visuals), 8-bit sRGB BGRA top-down (native spectra), 8-bit sRGB RGBA bottom-up (projectM).
- **Captured frame**: format, width, height, alpha present, encoded bytes.
- **Capture failure**: blacked out, paused, no frame, cancelled, encoding unavailable or failed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **REC-001-S1**: For the 64 × 48 fixture, PNG and HEIF read back with the selected format's width,
  height and alpha presence in 100% of runs; PNG pixels within ±1/255 of the expected 8-bit values;
  HEIF pixels within ±12/255 per channel on flat regions (lossy).
- **REC-001-S2**: Captures from a running compositor and a native spectrum at a known size have
  that size and the expected colors (simulator / Mac GPU), and the projectM capture has the surface
  size.
- **REC-001-S3**: The app UI test saves a PNG through the DEBUG folder option and reads back its
  format and the visual's pixel size, in under 30 s.
- **REC-001-S4**: Blackout and pause refusals produce no file in 100% of coordinator test cases.
- **REC-001-S5**: Saved files carry no metadata beyond the color profile (property read-back).
- **REC-001-S6**: On D1 and D3 (iPadOS 26.5), a PNG and a HEIF save to Files and iCloud Drive and
  open in Files, including with an external display active (device stage, owner's hands).

## Privacy Review

- Data: one picture of the screen, made only when the user taps Save Frame and chooses a format;
  held in memory until the Files sheet finishes; the app keeps no copy and stores no setting about
  it (FR-065).
- Destination: chosen by the user in the system Files sheet. No photo library access is requested;
  no new permission or usage description. Nothing is sent over a network.
- Content: what the visual showed. For the Camera visual this includes the camera's picture: it is
  captured only by the user's own tap, like a screenshot, and the privacy policy says so.
- Metadata: none beyond the color profile (R11).
- App Store privacy label: still Data Not Collected (the owner confirms in App Store Connect).

## Assumptions

- "Current composited frame" is the frame the active visual presents next after the tap (one frame
  later than the tap); the controls and badges are app UI, not part of the frame.
- One visual and one output exist at a time (OUT-001).
- Device behavior of the Files sheet, iCloud Drive and HEIF on iPadOS 26.5 is checked last, on
  devices, by the owner (`{device}` tasks).
- Simulator results are never device evidence (Constitution X).
