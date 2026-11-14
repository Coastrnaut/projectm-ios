# Implementation Plan: REC-004 Recording audio mux

**Branch**: `feature/rec-004` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/134-rec-004-recording-audio/spec.md`

## Summary

Recordings (REC-003) gain an AAC audio track, but only for audio the app owns or the user consented
to: In-App Playback (imported, non-protected files), and the Microphone when the permission is
granted and the new "Include microphone audio" setting is on (off by default). System/App Capture
audio is never muxed. The decision is made at Record and fixes the file's tracks; a source switch,
stop or consent change ends the audio for good (no silence). Audio comes from a new, armed-only
recording tap on the normalized ring (Float32 stereo 44.1 kHz) that carries a host-time stamp of its
newest sample; the recorder places each chunk relative to the first video frame on the same uptime
clock, keeps the track contiguous within a 100 ms window and re-anchors beyond it. The owned-audio
fixture (flash and click at one injected host time) proves ≤ 20 ms alignment. ADR-0053 records the
policy (it overrides REC-003's "no audio track" default and applies the constitution's privacy rule).

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 build machine; CI also Xcode 26).
**Primary Dependencies**: AVFoundation (`AVAssetWriterInput` AAC, `AVAssetReader` in tests), Core Media (LPCM sample buffers), Synchronization (`Atomic<WordPair>`), SwiftUI.
**Storage**: one Bool in UserDefaults (`settings.recording.includeMicrophone`); recordings stay in `<tmp>/Recordings` as before.
**Testing**: XCTest. Package tests: AudioCore (recording tap, Linux-buildable), Compositor/FrameRecording (policy and timeline plain Swift; fixture encode and read-back on the Mac host with Metal). App unit tests (setting, decision mapping, status texts, coordinator audio end), one UI test (the toggle).
**Target Platform**: iOS/iPadOS 26+.
**Project Type**: mobile app with SwiftPM packages.
**Performance Goals**: no work added to audio callbacks; the producer adds one ring write and one atomic store per normalized write, only while armed; the frame loop drains the tap into a preallocated buffer.
**Constraints**: Constitution I (no DRM circumvention), VII (real-time safety, bounded queues), privacy (no audio to disk by default: audio is written only into a recording the user starts, and kept only if the user saves it).
**Scale/Scope**: one new setting, one Settings section, two package modules extended, one app coordinator extended.

## Constitution Check

| Principle | Check |
|---|---|
| I. Public APIs only, no DRM circumvention | Pass. Only In-App Playback (files that passed the import's protected-content refusal, decoded by `AVAudioFile`) and the Microphone feed recordings; System/App Capture audio is never muxed. No new decode or protected-stream path. |
| IV. Truthful labeling | Pass. The audio status names what the file contains, and "no audio" with its reason. |
| V. No universal-capture claims | Pass. Nothing claims other apps' audio can be recorded; the UI says it never is. |
| VI. Modular boundaries | Pass. FrameRecording gains plain-Swift policy and timeline types with no AudioCore import; AudioCore gains the tap; the app maps one to the other. |
| VII. Real-time safety | Pass. The tap is written on the analysis work queue (not an audio callback), preallocated, lock-free, drop-oldest; the consumer never blocks. |
| Privacy | Pass with ADR-0053: audio reaches disk only inside a recording the user started, in the temporary folder, until the user saves it; microphone audio needs a separate opt-in plus the permission; the usage text and privacy policy are updated (REC-004-R11). |
| X. Evidence | Device alignment is `{device}` (left open); simulator and host results are not device evidence. |

Post-design re-check: unchanged (Pass).

## Project Structure

### Documentation (this feature)

```text
specs/134-rec-004-recording-audio/
├── plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/recording-audio.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/AudioCore/Sources/AudioCore/
├── NormalizedPCMReader.swift        # recording tap: arm/disarm, stamped reader (new code in the ring)
└── RecordingTap.swift               # RecordingTapReading protocol, chunk value, reader
Packages/Compositor/Sources/FrameRecording/
├── RecordingAudioPolicy.swift       # source kinds, decision, reasons, status texts (plain Swift)
├── RecordingAudioTimeline.swift     # host time → sample position, contiguity window, end (plain Swift)
├── VideoFileWriter.swift            # optional AAC input, LPCM sample buffers
├── MetalFrameRecorder.swift         # audio flag, appendAudio, endAudio, statistics
└── RecordedVideoInspector.swift     # audio track facts in the read-back
Packages/Compositor/Tests/FrameRecordingTests/
├── RecordingAudioPolicyTests.swift, RecordingAudioTimelineTests.swift
└── RecordingAudioMuxTests.swift     # fixture: flash + click alignment, consent, system capture, switch
Packages/AudioCore/Tests/AudioCoreTests/RecordingTapTests.swift
Apps/projectM-iOS/Coordinators/
├── RecordingAudioSetting.swift      # the setting (key, default off)
├── VideoRecordingCoordinator.swift  # decision at Record, audio feed, early end, status
└── AppCoordinator.swift             # context: mode, permission, setting, tap (small edit)
Apps/projectM-iOS/Views/RecordingAudioSection.swift   # Settings → Recording
Apps/projectM-iOS/Tests/RecordingAudioAppTests.swift
Apps/projectM-iOS/UITests/RecordingAudioUITests.swift
docs/adr/0053-recording-audio-policy.md
```

**Structure Decision**: extend the existing REC-003 module and coordinator; no new package.

## Complexity Tracking

None.
