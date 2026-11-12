# Implementation Plan: AUD-002 Support common audio containers

**Branch**: `feature/aud-002` (spec directory `006-aud-002-support-common-audio-containers`) | **Date**: 2026-11-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/006-aud-002-support-common-audio-containers/spec.md`

## Summary

AUD-001's library already imports and plays whatever the system decoder opens, but it trusts the
file name, checks only the start of a file and has one message for every decode problem. This
feature adds, inside `CaptureKit`: (1) `AudioContainer`, a bounded, pure recognition of MP3, raw
AAC (ADTS), MPEG-4/M4A, WAV and AIFF from a file's leading bytes; (2) three import errors
(`unsupportedFormat`, `unsupportedEncoding`, `noAudio`) and a classification of decoder failures
in `AVAudioFileInspector`, which now also decodes the end of the file; (3) naming the staged file
and the stored copy for the recognized container, so the system reads it with the right parser at
import and at every later playback; (4) a decode check when playback starts. `CaptureUI` gets
three strings. Tests add a generated format matrix (including an MP3 stream assembled by test
code) through import and the offline playback graph, plus corruption sweeps. No new package,
dependency, entitlement, stored field or schema version; the app target's sources do not change.

## Technical Context

**Language/Version**: Swift 6.4.2, strict concurrency complete (Xcode 27.2, ADR-0002).

**Primary Dependencies**: system frameworks only, all public and already used by AUD-001: AVFAudio
(`AVAudioFile`, `AVAudioEngine`, `AVAudioPlayerNode`), AVFoundation (`AVURLAsset`), Foundation
(`FileHandle`). Tests also use `AVAudioFile` for writing. No third-party dependency, no decoder
of our own.

**Storage**: unchanged layout (`Application Support/AudioLibrary/`), unchanged `index.json`
schema version 1. The only difference: the extension of a stored copy is the recognized
container's canonical extension instead of the picked file's.

**Testing**: XCTest in `CaptureKit` and `CaptureUI` on the macOS host and on an iOS 27.2 simulator
(decoder availability can differ between the two), Python script tests for the string contract.
Fixtures are generated at run time; nothing binary is committed.

**Target Platform**: iOS/iPadOS 26.0+ (unchanged); packages build for macOS 15 (tests);
`AudioContainer` and the model build on Linux.

**Project Type**: Mobile app plus Swift packages.

**Performance Goals**: validation cost independent of file size apart from AUD-001's copy: at most
`AudioContainer.maxHeaderBytes` (8 KiB) plus 10 bytes read for recognition, and at most two decodes
of 4,096 frames (start and end).

**Constraints**: offline; public APIs only; no networking; nothing new on the real-time tap path;
no hang or unbounded allocation on malformed input.

**Scale/Scope**: about 250 lines of production Swift, about 600 lines of tests.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design: pass.*

| Principle | Status | How |
|---|---|---|
| I. Public Apple APIs only | Pass | `AVAudioFile`, `AVURLAsset`, `FileHandle`. Decoder errors are read from the public `NSError` code (Core Audio `OSStatus`). DRM handling unchanged (AUD-001-R7). |
| II, III. Capture | N/A | In-App Playback of owned files only. |
| IV. Truthful source labeling | Pass | No new mode or label; every format plays as "In-App Playback". |
| V. No universal-capture claims | Pass | The format guarantee is limited to what the tests generate and run; real-encoder files and devices are tagged `{device}` and left open. |
| VI. Modular boundaries | Pass | Everything stays in `CaptureKit`; `AudioSource` and `InAppPlaybackBackend` are unchanged. |
| VII. Real-time audio safety | Pass | The tap closure is untouched. The new decode check runs in `InAppPlaybackGraph.load` on the main actor before the engine starts. |
| VIII. Upstream ProjectM fidelity | N/A | No engine or analysis change. |
| IX. Pinned dependencies and license review | Pass | No dependency. No media committed; fixtures are synthesized (AUD-002-R15). |
| X. Evidence-based quality | Pass | Unit tests for all deterministic logic, on host and simulator; device checks tagged `{device}`. |
| Security: untrusted imports | Pass | Bounded recognition and decode probes; corruption sweeps for every container; failures leave nothing behind (AUD-002-R9, R11). |
| Privacy | Pass | No new persistence, no network, no diagnostics field. |

## Project Structure

### Documentation (this feature)

```text
specs/006-aud-002-support-common-audio-containers/
├── plan.md, research.md, data-model.md, quickstart.md
├── contracts/
│   ├── audio-containers.md   # AudioContainer, error classification, naming, playback check
│   └── ui-strings.md         # the three new strings
├── checklists/requirements.md
└── tasks.md                  # /speckit-tasks
```

### Source Code (repository root)

```text
Packages/CaptureKit/Sources/CaptureKit/
├── AudioLibrary/
│   ├── AudioContainer.swift         # NEW: recognition from leading bytes (Foundation only)
│   ├── AudioLibraryModel.swift      # + 3 AudioImportError cases, AudioFileInfo.container, stored-name rule
│   ├── AudioFileInspector.swift     # failure classification, start and end decode probes
│   └── AudioLibrary.swift           # staged file and asset named for the container; empty file → noAudio
└── InAppPlayback/InAppPlaybackGraph.swift   # load(): decode probe before playback
Packages/CaptureKit/Tests/CaptureKitTests/
├── AudioFixtures.swift              # + AIFF, M4A, ADTS, ALAC writers, hand-written AIFF, corruption helpers
├── MP3Fixture.swift                 # NEW: MPEG-1 Layer III stream writer (test code)
├── AudioContainerTests.swift        # NEW: recognition (pure; also runs on Linux)
├── AudioFormatMatrixTests.swift     # NEW: matrix through inspector, library and playback graph
├── AudioCorruptionTests.swift       # NEW: refusal reasons, sweeps, recovery, playback failure
├── AudioLibraryTests.swift, InAppPlaybackGraphTests.swift   # two AUD-001 expectations amended (AUD-002-R8)
Packages/CaptureUI/Sources/CaptureUI/UIStrings.swift          # + 3 messages
Packages/CaptureUI/Tests/CaptureUITests/ImportStringsTests.swift
scripts/test_scripts.py                                       # + contract check for this feature's strings
```

**Structure Decision**: extend `CaptureKit` and `CaptureUI`. `project.yml`, the CI workflow and
`AppCoordinator.swift` are not touched; the app picks the new messages up through
`UIStrings.message(_:)`.

## Design

Details: [research.md](research.md), [data-model.md](data-model.md),
[contracts/audio-containers.md](contracts/audio-containers.md).

1. **Recognition** (`AudioContainer.detect`): read at most 8 KiB from the start. `RIFF…WAVE` → WAV;
   `FORM…AIFF|AIFC` → AIFF; `ftyp` at offset 4 → MPEG-4; an ID3v2 tag is skipped by its declared
   size (one seek, no read of the tag); then an MPEG audio header decides: layer bits `00` with a
   valid ADTS header → AAC, Layer III with a valid header → MP3. When the stream does not start
   at offset 0, two consecutive consistent headers are required. Anything else → nil ("other").
2. **Import** (`AudioLibrary.importLocked`): after the copy to `incoming/`, an empty file fails
   with `noAudio`; otherwise the staged file is recognized and, if its extension is not the
   container's, renamed in place (same folder) before inspection. The asset is stored as
   `<sha256>.<canonical ext>`. Unrecognized content keeps the picked extension (AUD-001 behavior).
   Rollback is unchanged: every failure removes the staged file under whichever name it has.
3. **Inspection** (`AVAudioFileInspector`): open with `AVAudioFile` (the API playback uses);
   classify an open failure by recognition and by the decoder's status (`'fmt?'` → unsupported
   encoding); zero frames → `noAudio`; decode up to 4,096 frames at the start and, for longer
   files, the last 2,048 frames; a decode error is `unsupportedEncoding` for `'fmt?'`, else
   `unreadable`. `AudioFileInfo.container` reports what was recognized.
4. **Playback** (`InAppPlaybackGraph.load`): after opening, decode up to 4,096 frames from the
   first handle and rewind it; failure throws, which the backend reports as "In-App Playback
   failed" before the session or engine starts.
5. **Strings**: three cases in `UIStrings.message(_: AudioImportError)`.

## Testing strategy (deterministic)

- **Fixtures** (run time, per-test temporary directory): WAV, AIFF(-C), M4A/AAC, ADTS and ALAC
  written with `AVAudioFile`; a classic AIFF and WAV variants written byte by byte; MP3 assembled
  by `MP3Fixture` (constant-bit-rate MPEG-1 Layer III frames whose only content is one quantized
  frequency line per channel, so the decoded signal is a steady tone at a known frequency). Stereo
  fixtures carry different frequencies left and right.
- **Matrix**: each fixture → `AVAudioFileInspector` (duration, rate, channels, container) →
  `AudioLibrary.importFile` → `InAppPlaybackGraph` rendered offline at 48 kHz and 44.1 kHz stereo;
  assert non-silence and the per-channel frequency (zero-crossing count) within 3%.
- **Recognition**: byte-level unit tests of `AudioContainer` including ID3, misleading names and
  near-miss headers; misnamed fixtures through the library and the graph, including a second
  library over the same folder (relaunch).
- **Corruption**: for every container: cut at fixed fractions, overwrite fixed byte ranges with a
  seeded generator, keep the header only. Each case must return an outcome (no crash; XCTest
  time allowance catches a hang), leave the library tree and `index.json` identical on refusal,
  and render through the graph when imported. One fixture per refusal reason asserts the exact
  error.
- **Recovery**: after refusals, a valid import and playback succeed; a graph that is rendering
  keeps rendering while a corrupt file is refused; a stored copy overwritten after import fails
  `load` and the next track plays.
- **Red run recorded** before the production change (tasks.md).
- **Simulator**: the same package suites on the iOS 27.2 simulator. Not covered anywhere before
  the device phase: real-encoder files, the audio session, routes and interruptions per format.

## Local persistence and rollback

- No schema change: `index.json` stays version 1 and holds the same fields. A library written by
  AUD-001 loads unchanged; a library written by this feature loads in AUD-001 code unchanged
  (stored names still satisfy `<sha256>.<ext>`, at most 8 characters).
- Import stays a transaction (AUD-001-D3): the rename for the container happens inside
  `incoming/`, before anything is visible in `assets/` or the index.
- Reverting the code needs no data step.

## Complexity Tracking

No constitution violation. One recorded amendment of AUD-001 wording (AUD-002-R8): two refusals
change from "unreadable" to the more specific reason.
