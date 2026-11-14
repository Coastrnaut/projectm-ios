# Implementation Plan: REC-005 Record quality profiles

**Branch**: `feature/rec-005` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/150-rec-005-quality-profiles/spec.md`

## Summary

Recordings (REC-003) gain four documented quality profiles: Draft (720p, H.264, 4 Mb/s, 30 fps),
Standard (today's settings exactly: 1080p cap, HEVC then H.264, REC-003's per-pixel bit rate, 30 fps;
the default), High (1440p, HEVC, 20 Mb/s, 60 fps) and Max (screen size, HEVC, 40 Mb/s, 60 fps).
`RecordingSettings` gains an optional fixed bit rate (nil keeps REC-003's rule, so Standard is
`RecordingSettings.standard` unchanged); the writer and the disk guard read the bit rate through one
method. A plain-Swift catalog decides each profile's availability from an injected capability source
(can the encoder do codec C at W×H; the display's highest frame rate) and the drawable size; the real
source asks VideoToolbox (`VTCopySupportedPropertyDictionaryForEncoder`, public) at the exact output
size. Settings → Recording quality lists the profiles as selectable rows, disabled ones with their
reason; the choice is a device-local string. Record re-resolves with the actual drawable and falls
back down the list (announced as X9c). The read-back gains frame rate and video bit rate, and a GPU
fixture per available profile records 2 s of per-frame noise and checks codec, size, frame rate and
bit rate (±25%).

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 build machine; CI also Xcode 26).
**Primary Dependencies**: AVFoundation (writer, read-back), VideoToolbox (encoder capability query), Metal (fixture frames), SwiftUI.
**Storage**: one String in UserDefaults (`settings.recording.qualityProfile`), device-local.
**Testing**: XCTest. FrameRecording package: profile, availability, resolver and storage tests (plain Swift, Linux-buildable), default-settings equality and the GPU fixture per profile on the Mac host. App unit tests (setting persistence, coordinator fallback and refusal with injected capabilities), one UI test (picker).
**Target Platform**: iOS/iPadOS 26+.
**Project Type**: mobile app with SwiftPM packages.
**Performance Goals**: the capability query runs off the frame loop (Settings and Record), cached per codec and size; nothing is added per frame.
**Constraints**: Constitution I (public APIs only), X (simulator and host results are not device evidence); owner rule 7 (each fixture test under 10 s).
**Scale/Scope**: one package module extended, one setting, one Settings section, one coordinator edit.

## Constitution Check

| Principle | Check |
|---|---|
| I. Public APIs only | Pass. `VTCopySupportedPropertyDictionaryForEncoder`, `AVAssetWriter.canApply`, `UIScreen.maximumFramesPerSecond` and `nativeBounds` are public; no private keys. |
| IV. Truthful labeling | Pass. Rows state exactly what will be encoded on this screen; disabled rows say why; a fallback is announced. |
| VI. Modular boundaries | Pass. FrameRecording gets plain-Swift profile and availability types and an Apple-only capability source; the app only maps the setting and screen into them. |
| VII. Real-time safety | Pass. No per-frame work; queries are cached and run on the main actor outside the frame loop. |
| Privacy | Pass. One device-local preference; left out of the library backup; no new data leaves the device. |
| X. Evidence | Device read-back per profile is `{device}` (left open). |

Post-design re-check: unchanged (Pass).

## Project Structure

### Documentation (this feature)

```text
specs/150-rec-005-quality-profiles/
├── plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/quality-profiles.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/FrameRecording/
├── RecordingSettings.swift            # fixedBitRate (nil = REC-003 rule), averageBitRate(codec:width:height:)
├── RecordingQualityProfile.swift      # the four profiles, their settings and documentation (plain Swift)
├── RecordingQualityAvailability.swift # capability protocol, availability, reasons, resolver (plain Swift)
├── VideoToolboxEncoderCapabilities.swift  # the real capability source (Apple only)
├── VideoFileWriter.swift              # bit rate through settings
├── RecordingStorage.swift             # estimate through settings
└── RecordedVideoInspector.swift       # frame rate, video bytes, average bit rate
Packages/Compositor/Tests/FrameRecordingTests/
├── RecordingQualityProfileTests.swift # catalog, availability with injected capabilities, resolver, estimate, default = today
└── RecordingQualityFixtureTests.swift # GPU fixture per available profile, read back
Apps/projectM-iOS/Coordinators/
├── RecordingQualitySetting.swift      # key, default Standard, rows' availability
├── VideoRecordingCoordinator.swift    # resolve at Record, fallback notice, refusal
├── StatusEvents.swift                 # X9c
└── AppCoordinator.swift               # the setting, reset (small edit)
Apps/projectM-iOS/Views/RecordingQualitySection.swift  # Settings → Recording quality
Apps/projectM-iOS/Views/SettingsView.swift, VisualizerView.swift  # pass the setting (one line each)
Apps/projectM-iOS/Tests/RecordingQualityAppTests.swift
Apps/projectM-iOS/UITests/RecordingQualityUITests.swift
scripts/run_device_tests.py, Packages/LibraryBackup/.../LibrarySettings.swift  # the key's lists
```

**Structure Decision**: extend REC-003's module and coordinator; no new package, no ADR (Standard
keeps the default; the profiles add choices without overriding a recorded decision).

## Complexity Tracking

None.
