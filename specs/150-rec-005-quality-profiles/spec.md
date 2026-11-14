# Feature Specification: REC-005 Record quality profiles

**Feature Branch**: `feature/rec-005` (spec directory `150-rec-005-quality-profiles`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (REC-005-T01-T13 verified on the Mac: package fixtures on the host, app and UI tests on the REC5 iOS 27.2 simulator; device task T14 `{device}` open)

**Input**: User description: "Implement REC-005 (Record quality profiles) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Offer documented resolution and bitrate presets within device
capabilities." Acceptance, verbatim: "Selected preset matches encoded metadata and unsupported modes
are disabled." P1, M, depends on REC-003 (integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `REC-005-R1…`, success criteria `REC-005-S1…`, tasks `REC-005-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `4bad23aa`)

| Area | Today |
|---|---|
| Recorder | REC-003 (ADR-0027): `MetalFrameRecorder` → `VideoFileWriter`, one `AVAssetWriter` MP4. The pixel buffers are the drawable cropped to even dimensions (`RecordingGeometry.sourceWidth/Height`); the encoded size fits a long-side cap with the same aspect (`outputWidth/Height`, `isScaled`), never larger than the source. |
| Settings in use | Only `RecordingSettings.standard`, hard-coded in `VideoRecordingCoordinator.start()`: long side at most 1920, at most 30 fps, 10-minute limit, 3 frames in flight, codecs HEVC then H.264 (the first the writer accepts). No user setting exists. |
| Bit rate | `RecordingCodec.averageBitRate`: 0.12 bits per pixel per frame for HEVC, 0.2 for H.264, at least 1 Mb/s. At 1080×1920 and 30 fps that is about 7.5 Mb/s (HEVC). Key frames at most every 2 s, no frame reordering, Rec. 709 colour tags, H.264 High profile (auto level). |
| Audio | REC-004 (ADR-0053): optional AAC-LC 44.1 kHz stereo 128 kb/s track, decided at Record. Unchanged here. |
| Disk guard | REC-015: `RecordingStorageEstimate` = the highest bit rate among the preferred codecs at the output size and frame rate, plus 25%; Record needs a 200 MiB reserve plus 60 s at that rate. |
| Read-back | `RecordedVideoInspector`: codec four-character code, encoded size, frame times, track counts, metadata, audio format. No frame rate or bit rate yet. |
| Settings → Recording | REC-004's section: "Include microphone audio" and the next recording's audio status. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the conservative, local-first option.

- Q: Which profiles are offered? → A: Four, in this order: Draft, Standard, High, Max (table in REC-005-R1). Standard is the default and is exactly today's recording settings, so a user who never opens the picker gets byte-for-byte the same encoder configuration as before.
- Q: Does Standard change to a fixed 10 Mb/s? → A: No. Standard keeps REC-003's per-pixel bit rate (about 7.5 Mb/s at 1080×1920, 30 fps, HEVC) so the default stays bit-compatible with today's output settings. The other profiles use fixed bit rates.
- Q: Is the frame rate a separate choice? → A: No: each profile carries its frame rate (Draft and Standard 30 fps, High and Max 60 fps). One choice keeps the picker short and every row fully documented; a frame rate the display cannot reach disables the profile.
- Q: Does any profile upscale? → A: Never. Every profile caps the long side and only scales down; on a screen smaller than the cap the profile records at the screen's (even-cropped) size, and its row shows the size it will actually record.
- Q: How are unsupported profiles shown? → A: Disabled, in place, with a one-line reason (for example "Needs HEVC, which this device cannot encode."). They are never hidden.
- Q: What happens when Record is tapped with a profile that is not available at that moment (the screen size changed, the selection came from an earlier state)? → A: The recording falls back to the best available profile below the selected one (Max → High → Standard → Draft), starts, and announces "Recording at <profile>: <reason>." through the status router. The stored selection is not changed. If no profile is available, Record refuses with REC-003's encoder-unavailable notice. A fallback beats a refusal: the user asked to record.
- Q: Does High or Max fall back to H.264 inside the profile? → A: No. A profile's codec is part of its documented promise; without HEVC those profiles are disabled. Only Standard keeps REC-003's HEVC-then-H.264 order (it is today's behaviour).

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: Can the profile change while a recording runs? → A: The picker stays usable, but a recording keeps the profile it started with (its encoder is fixed at Record); the change applies to the next recording. Re-configuring a running encoder would split the file.
- Q: Which screen size do the rows describe when no visual is shown (Settings opened from the chooser)? → A: The size of the shown visual's drawable when one is shown, else the device screen's native size in pixels (portrait). Record always re-checks with the actual drawable (REC-005-R6).
- Q: Does a profile change the audio? → A: No. REC-004's audio (AAC-LC 44.1 kHz stereo 128 kb/s, when permitted) is the same in every profile; profiles change only the video.
- Q: Is the fallback only spoken, or also visible? → A: Both: it is shown as the recording notice and announced once through the status router as row X9c (cause: user, after X9 "Recording started"), so sighted and VoiceOver users learn the same thing.
- Q: How is a file's average bit rate measured for the acceptance check? → A: The video track's compressed bytes × 8 divided by the video's duration, read from the compressed samples (no decoding). Audio bytes are not counted. Tolerance ±25% for the noise fixture of at least 2 s (REC-005-S1); research REC-005-D4 records the measured values.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Pick a documented recording quality (Priority: P1)

A user opens Settings → Recording quality, reads what each profile records (size, codec, bit rate,
frame rate), and picks one; the next recording is encoded with exactly that profile's values.

**Why this priority**: It is the row's acceptance criterion: the selected preset matches the encoded
metadata.

**Independent Test**: Fixture encoding: for each profile available on the test machine, a short clip
of injected frames is recorded and read back; codec, encoded size, frame rate and average bit rate
match the profile within the documented tolerance.

**Acceptance Scenarios**:

1. **Given** profile P is selected and available, **When** a recording is made, **Then** the file's codec is P's codec, its size is P's size for that screen, its frame rate is P's frame rate and its average bit rate is within the documented tolerance of P's bit rate.
2. **Given** a fresh install, **When** the user opens Settings, **Then** Standard is selected, and a recording uses exactly today's settings.
3. **Given** the user picks High, **When** the app is relaunched, **Then** High is still selected.

---

### User Story 2 - Unsupported profiles are disabled with a reason (Priority: P1)

On a device whose encoder cannot do HEVC or a large size, or whose display cannot reach the frame
rate, the affected profiles are shown disabled with a reason and cannot be picked; Record never uses
them.

**Why this priority**: The acceptance names it ("unsupported modes are disabled").

**Independent Test**: A test capability source that says "no HEVC" or "at most 1920 pixels" disables
exactly the affected profiles with their reasons; a Record attempt with a disabled profile falls back
to the next available one and says so.

**Acceptance Scenarios**:

1. **Given** the encoder cannot do HEVC, **When** the profiles are listed, **Then** High and Max are disabled with the HEVC reason and Draft and Standard (which uses H.264) stay available.
2. **Given** the encoder supports at most 1920 pixels on the long side and the screen is larger, **When** the profiles are listed, **Then** High and Max are disabled with the size reason.
3. **Given** Max is selected but unavailable at Record, **When** the user records, **Then** the recording uses the best available profile below it and the app announces the fallback; the selection stays Max.

---

### User Story 3 - Room for a larger recording (Priority: P2)

The disk guard's room check uses the selected profile's bit rate, so a Max recording needs more free
space to start than a Draft recording.

**Independent Test**: Unit test: the storage estimate of each profile equals its bit rate (plus the
guard's 25% headroom) at its size and frame rate.

**Acceptance Scenarios**:

1. **Given** Max is selected, **When** the user records with less free space than Max needs but more than Draft needs, **Then** Record refuses with the low-storage notice.

### Edge Cases

- The screen is smaller than a profile's cap: the profile records at the screen size and its row shows that size (no upscaling). Two profiles may then record the same size; their bit rate and frame rate still differ.
- The window changes size during a recording (rotation, Stage Manager): REC-003 stops the recording as today.
- The stored value is unknown or not a string: Standard is used.
- The capability check cannot run (no encoder answer): the profile is treated as unavailable; Standard keeps its H.264 fallback.
- External display output, projectM and the 10-minute limit are unchanged.
- The user changes the profile during a recording: the running recording keeps its profile; the next one uses the new choice.

## Requirements *(mandatory)*

### Functional Requirements

- **REC-005-R1**: The app MUST offer exactly these profiles, documented in-app with the same values:

  | Profile | Long side at most | Codec | Average bit rate | Frame rate |
  |---|---|---|---|---|
  | Draft | 1280 (720p) | H.264 | 4 Mb/s | 30 fps |
  | Standard (default) | 1920 (1080p) | HEVC, else H.264 | 0.12 bit/pixel/frame (HEVC) or 0.2 (H.264), at least 1 Mb/s: about 7.5 Mb/s at 1080×1920 | 30 fps |
  | High | 2560 (1440p) | HEVC | 20 Mb/s | 60 fps |
  | Max | the screen's size | HEVC | 40 Mb/s | 60 fps |

- **REC-005-R2**: No profile MUST ever encode a larger picture than the shown frame (even-cropped); a profile only scales down to its cap, keeping the aspect ratio.
- **REC-005-R3**: Standard MUST produce exactly today's encoder settings (size cap, frame rate, codec order, bit rate, key frames, colour tags).
- **REC-005-R4**: A profile MUST be available only when the device's encoder supports its codec at the size it would record on this screen, and the display can show its frame rate. Availability MUST be determined with public system interfaces only.
- **REC-005-R5**: An unavailable profile MUST be shown disabled with a one-line reason and MUST NOT be selectable; profiles MUST never be hidden.
- **REC-005-R6**: Record MUST check availability again with the current screen size. With an unavailable selection it MUST fall back to the best available profile below it, show and announce "Recording at <profile>: <reason>." through the status router (row X9c), and leave the stored selection unchanged; with no available profile it MUST refuse with the encoder-unavailable notice.
- **REC-005-R7**: The selection MUST be stored on the device (default Standard; an unknown value reads as Standard), reset by the UI-test reset, erased with the Settings category, and left out of the library backup (it depends on the device's capabilities).
- **REC-005-R8**: The disk guard's estimate MUST use the profile's bit rate, size and frame rate.
- **REC-005-R9**: The picker MUST be in Settings, in a "Recording quality" section next to REC-004's "Recording" section; each row MUST name the profile and what it records on this screen (size, codec, bit rate, frame rate), and VoiceOver MUST read the row, its selected state and, when disabled, its reason.
- **REC-005-R10**: The recording's read-back facts MUST include frame rate and the video track's average bit rate (compressed video bytes × 8 / video duration), so tests can compare a file with its profile.
- **REC-005-R11**: A recording MUST keep the profile it started with; audio (REC-004) MUST be identical in every profile.
- **REC-005-R12**: The rows MUST describe the shown visual's drawable size, or the screen's native pixel size when no visual is shown.

### Key Entities

- **Recording quality profile**: name, long-side cap (or the screen's size), codec order, bit rate rule (fixed, or REC-003's per-pixel rule), frame rate.
- **Encoder capabilities**: whether a codec can encode a given size; the display's highest frame rate.
- **Profile availability**: available with the size it records, or unavailable with a reason.
- **Recording quality setting**: the selected profile, device-local, default Standard.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **REC-005-S1**: For every profile available on the test machine, a recorded fixture reads back with the profile's codec, its exact encoded size, its frame rate within ±1 fps and its average bit rate within ±25% of the target (high-detail fixture of at least 2 s; tolerance documented in research).
- **REC-005-S2**: With "no HEVC" or "at most 1920 pixels" capabilities, 100% of the affected profiles are disabled with their reason and 0 unaffected profiles are disabled.
- **REC-005-S3**: The default profile's encoder settings are identical to today's (dictionary equality).
- **REC-005-S4**: The picker UI test selects a profile and sees it selected in under 30 s.
- **REC-005-S5**: On a device, a recording in each available profile reads back with that profile's values (device stage, `{device}`).

## Assumptions

- The test machine's hardware encoder (host Mac, simulator) supports HEVC; profiles it cannot do are skipped in the fixture test and covered by the injected capability tests.
- A high-detail moving fixture (per-frame noise) makes the encoder use its target bit rate; simple content would encode well below the target, so the tolerance is checked on the high-detail fixture.
- Bit rate is an average target, not a constant rate; short clips vary, hence the ±25% tolerance.
- HDR, ProRes, 4K-only presets, per-recording overrides and a separate frame-rate choice are out of scope.
