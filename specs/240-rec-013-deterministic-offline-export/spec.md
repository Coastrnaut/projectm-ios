# Feature Specification: REC-013 Deterministic Offline Export

**Feature Branch**: `feature/rec-013` (spec directory `240-rec-013-deterministic-offline-export`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: Roadmap row REC-013 (P2, effort XL, depends on SCN-001 and ANL-016, both integrated). Observable behavior,
verbatim: "Render scene from fixed audio fixture and clock without real-time pacing." Acceptance, verbatim: "Two exports
with same seed and inputs match frame checksums on same GPU class."

Identifiers carry the roadmap ID: requirements `REC-013-R1…`, success criteria `REC-013-S1…`, tasks `REC-013-T01…`,
research decisions `REC-013-D1…`. Other features are cited by their own IDs: REC-002 (image batch export), REC-003
(video recording), REC-004 (recording audio), REC-011 (Save to Photos), REC-012 (Save… / Share…), REC-014 (export
shapes), REC-016 (recording recovery), SCN-001 (scene document), SCN-015 (scene lock), ANL-016 (analysis event bus),
PRE-005 (pinned projectM clock), QA-002 (golden scene renders), VIS-001…VIS-009 (native visuals), FX-001 (glow),
ACC-004 (announcer lanes), ACC-012 (sensory safety).

## Baseline (audit of 2026-11-14, commit `c035898f`)

| Existing piece | What it does today | Use in REC-013 |
|---|---|---|
| REC-002 `SnapshotStillRenderer`, `SnapshotBatchJob`, `SnapshotBatchPlanner` | One offscreen still of the open scene's native visual with the glow, at a fixed frame time with seeded synthetic audio; a job captured at Export; native visuals only | The same generator factory, glow chain, safety clamp and job capture; the export renders many frames instead of four, and its input comes from real analysis of the chosen audio |
| ANL-016 `AnalysisPipeline` (`attach`, `step`, injected clock) | The analysis bus: spectra, bands and events from a normalized PCM reader; `step()` reads synchronously | Fed from the export's audio at exact sample positions, stepped once per frame, with a fixed clock |
| VIS-003/004 `WaveformTap` | Mono and stereo histories for the oscilloscope, Lissajous and radial waveform | Wraps the export's audio reader exactly as on screen |
| VIS-006/008/009 triggers (`BeatRingTrigger`, `ParticleFountainTrigger`) | Turn bus events into rings, bursts and pulses | Drained per frame, as the live host does |
| REC-003/004/014/016 `MetalFrameRecorder`, `VideoFileWriter` | GPU-fed MP4 writer with an AAC track; exact frame grid; fragments | `VideoFileWriter` writes the export (through a new offline wrapper, research D5): frame n at n/fps, the audio track from the same samples |
| REC-011 `PhotosSaveCoordinator`, REC-012 sharing | Add-only Save to Photos of a recording; Save… and Share… of files | Offered for the finished export |
| QA-002 `GoldenSceneRenderer`, `GoldenSHA256` | Fixed-time, seeded renders for golden tests (test package) | Its determinism rules; checksums use the system's SHA-256 in the app |
| PRE-005 `setFrameTime` | Pins projectM's clock for preset thumbnails | Not enough for determinism: projectM's presets also draw from the engine's own random numbers, which the app cannot seed without an engine patch (Constitution VIII), so projectM scenes are not exported (D3) |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the conservative,
local-first option.

- Q: What does an export render? → A: The open scene's native visual as it is when Export is tapped (the visual, its options, the glow, Reduce flashing and the sensory safety profile), frozen for the whole export, exactly as REC-002 captures a batch. Show segments are out of scope for this version: a show's cues change the scene over time, which needs a timeline of scene states.
- Q: Which visuals? → A: The native visuals (Circular and Linear Spectrum, Oscilloscope, Lissajous, Radial Waveform, Beat Rings, Mandala, Particle Fountain, Particle Orbit). projectM is refused: its presets draw from the engine's own unseeded random numbers, so two exports could differ, and making them repeatable would need an engine patch. Camera, Photo, Video and Text are refused too (live or external media). The sheet says "Offline export works with the native visuals. Choose one in Settings › Visual."
- Q: Which audio? → A: Either the built-in fixture (10 s of seeded synthetic music: a bass pulse at 120 BPM, chords and seeded noise hits) or an audio file the user picks with the system file picker. The file is read locally, converted to 44.1 kHz stereo and never copied into the library. The export lasts as long as the audio, at most 10 minutes.
- Q: What is the seed? → A: A whole number (default 1) that drives every random choice of the export: the fixture's noise and the particle visuals' simulations. Visuals without randomness ignore it (with an audio file, a Circular Spectrum export is the same for every seed). The seed is chosen in the sheet each time, not stored.
- Q: How is time handled? → A: Frame n is drawn at exactly n / fps seconds; the analysis has then read the audio up to sample round(n × 44,100 / fps). Nothing waits for the real clock: frames render as fast as the device can, and a frame is never dropped (the encoder is waited for).
- Q: Which sizes and rates? → A: REC-002's shapes (Landscape 1920 × 1080, Portrait 1080 × 1920, Square 1080 × 1080) at 30 or 60 frames per second, chosen per export.
- Q: What is written? → A: An MP4 video (HEVC, else H.264) with the audio as an AAC track, and next to it a checksum sidecar `<name>.checksums.json`: the export's inputs (visual, size, rate, seed, audio source and its SHA-256, GPU name) and one SHA-256 per frame of the rendered pixels before encoding. Two exports with the same inputs on the same GPU class have identical checksum lists; the video file itself may differ, because encoders are not bit-exact.
- Q: Where do the files go? → A: Into a new temporary folder used only by that export. The finished export offers Save… (both files), Share… (both files) and Save to Photos (the video, add-only, REC-011). Done deletes the folder; leftovers from a killed app are deleted at the next launch.
- Q: Progress and cancel? → A: "Rendering frame 120 of 600" with a progress bar and Cancel. Cancel stops before the next frame and deletes the folder: no file remains. "Export cancelled" is shown and announced.
- Q: Does exporting touch the live scene? → A: No. The export never writes the live values, the scene file, the snapshot list or the undo history, it never draws to the screen, and the live visual keeps running. It works while the scene is locked.

### Session 2026-11-14 (speckit-clarify)

- Q: What happens when the app goes to the background during an export? → A: iOS does not let a background app use the GPU, so the export stops: its folder is deleted and "Export stopped: the app left the screen." is shown and announced. Nothing partial is kept.
- Q: Does the live visual keep running while an export renders? → A: Yes. The export uses its own renderer, analysis and command queue at a lower priority than the screen; the screen may slow down meanwhile, but it never shows export frames and the export never reads the live audio.
- Q: Which seed values are allowed? → A: Whole numbers from 0 to 4,294,967,295 (default 1), typed in a number field; anything else is refused with "Enter a whole number from 0 to 4294967295."
- Q: What does the sidecar record to identify the GPU class and the inputs? → A: The GPU name reported by the system, the OS version, the app version, the visual and its options, the glow, Reduce flashing, the safety profile, the size, the rate, the seed, the audio source (fixture or the file's name) with the SHA-256 of the exact 44.1 kHz samples used, the frame count and the frame checksums (lowercase hex). Two sidecars are compared by their checksum lists; the GPU name says whether the comparison applies.
- Q: Is the export's file name fixed? → A: `projectM-offline-<visual>-<seed>.mp4` and `projectM-offline-<visual>-<seed>.checksums.json`, with the visual's name (for example `circularSpectrum`); the folder is new per export, so names never collide.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Export a repeatable video of a look (Priority: P1)

A VJ wants a video of the Circular Spectrum with glow reacting to a track, made at full quality regardless of how fast
their phone could render it live. They open Export Video Offline…, pick the track, choose Landscape at 30 fps and tap
Export. A few seconds later they save the MP4 to Photos.

**Why this priority**: This is the roadmap row: a scene rendered from fixed audio and a fixed clock, not real time.

**Independent Test**: Export 2 s of the fixture at 30 fps; the video has 60 frames, an audio track, and the sidecar
lists 60 checksums.

**Acceptance Scenarios**:

1. **Given** the Circular Spectrum and the fixture, **When** the user exports at 30 fps, **Then** an MP4 with 300 frames (10 s × 30) and an audio track, and a sidecar with 300 checksums, are offered.
2. **Given** an audio file of 2 s, **When** it is exported at 60 fps, **Then** the video has 120 frames and lasts 2 s.

---

### User Story 2 - Prove an export is repeatable (Priority: P1)

A tester exports the same look twice with the same audio and seed and compares the sidecars.

**Independent Test**: Two exports with the same inputs have identical per-frame checksum lists; changing the seed (for
a seeded visual) or the audio changes them.

**Acceptance Scenarios**:

1. **Given** two exports with the same scene state, audio, seed, size and rate on the same device, **Then** their checksum lists are identical.
2. **Given** the Particle Fountain, **When** the seed changes, **Then** the checksum lists differ.
3. **Given** the Circular Spectrum, **When** the audio changes, **Then** the checksum lists differ.

---

### User Story 3 - Cancel a long export (Priority: P2)

**Acceptance Scenarios**:

1. **Given** an export rendering, **When** the user taps Cancel, **Then** rendering stops before the next frame, the temporary folder is gone and "Export cancelled" is shown.

### Edge Cases

- projectM or a media visual shown: the sheet explains and Export is disabled.
- The audio file cannot be read (damaged, protected, no audio track, unreadable format): "This audio file can't be read." and nothing is rendered.
- The audio file is longer than 10 minutes: only the first 10 minutes are exported, and the sheet says so.
- The audio file is shorter than two frames: refused ("The audio is too short.").
- An encoder or storage failure: the export stops, its folder is deleted, "Export failed" is shown.
- The app is backgrounded: the export stops and its folder is deleted ("Export stopped: the app left the screen."); a killed app's folder is deleted at the next launch.
- A new export while one is offered: the earlier folder is deleted first (one export at a time).
- A live change (cue, MIDI) during an export: the export keeps the state captured at Export.

## Requirements *(mandatory)*

### Functional Requirements

- **REC-013-R1**: Settings › Visual MUST offer "Export Video Offline…", opening a sheet with the audio choice (Fixture, or a file picked with the system file picker), the seed (a whole number 0…4,294,967,295, default 1), the shape (Landscape, Portrait, Square) and the rate (30 or 60 fps).
- **REC-013-R2**: The export MUST capture the visual, its options, the glow values, Reduce flashing and the safety profile when Export is tapped, and use them for every frame (REC-002's capture).
- **REC-013-R3**: Frame n MUST be rendered offscreen at time n / fps with the analysis having read the audio up to sample round(n × 44,100 / fps); frames MUST NOT be paced to the real clock and none may be dropped.
- **REC-013-R4**: The analysis MUST be the live one (bands, waveform histories and events) fed from the export's audio, with a fixed analysis clock, so the output does not depend on when the export runs.
- **REC-013-R5**: The seed MUST drive the fixture's noise and the particle visuals' simulations; nothing else in the export may be random.
- **REC-013-R6**: The export MUST write an MP4 video with the audio as its AAC track, frame count = round(duration × fps), and a checksum sidecar with the inputs and one SHA-256 per frame of the rendered pixels before encoding.
- **REC-013-R7**: Two exports with the same captured state, audio, seed, shape and rate on the same GPU class MUST produce identical checksum lists.
- **REC-013-R8**: projectM, Camera, Photo, Video and Text MUST be refused with the sheet's explanation.
- **REC-013-R9**: An audio file MUST be read locally, converted to 44.1 kHz stereo, limited to 10 minutes, and refused when unreadable or shorter than two frames.
- **REC-013-R10**: The sheet MUST show progress ("Rendering frame N of M") and Cancel; Cancel or a failure MUST delete the export's folder so no file remains.
- **REC-013-R11**: A finished export MUST offer Save… and Share… (video and sidecar) and Save to Photos (video, add-only).
- **REC-013-R12**: Exporting MUST NOT write the live values, the scene, its snapshots or the undo history, and MUST NOT draw to the screen.
- **REC-013-R13**: Outcomes MUST be announced on the library lane (ACC-004).
- **REC-013-R14**: No new stored setting, scene field, permission or network use.
- **REC-013-R15**: Leaving the foreground MUST stop a running export and delete its folder; the live visual MUST keep running during an export and never show export frames.

### Key Entities

- **Offline export job**: captured visual state, audio source, seed, shape, rate, frame count.
- **Checksum sidecar**: format version, inputs (visual and options, glow, Reduce flashing, safety profile, size, rate, seed, audio source, audio SHA-256), environment (GPU name, OS version, app version), frame count, frame checksums in order (lowercase hex).
- **Export**: temporary folder, state (idle, rendering frame N of M, finished with files, cancelled, failed).

## Success Criteria *(mandatory)*

- **REC-013-S1**: Two exports with the same inputs on the same device produce identical per-frame checksum lists (the roadmap acceptance).
- **REC-013-S2**: An export of D seconds at F fps contains exactly round(D × F) frames and an audio track, and its sidecar lists the same number of checksums.
- **REC-013-S3**: Changing the seed of a seeded visual, or the audio, changes the checksum list.
- **REC-013-S4**: Cancel leaves zero files.
- **REC-013-S5**: The live scene's values and file are unchanged by an export.
- **REC-013-S6**: The automated acceptance test (two tiny 2 s exports and the variations) finishes in under 10 s on the simulator.

## Assumptions

- "Same GPU class" means the same device model and GPU (the sidecar names the GPU); results across GPU models may differ.
- The checksums cover the rendered frames; the encoded video file is not required to be byte-identical.
- projectM scenes, media layers and show segments are out of scope for this version (D3).
- Simulator results are never device evidence (Constitution X); a `{device}` task checks speed and repeatability on D1.
