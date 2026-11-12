# Implementation Plan: AUD-001 Import DRM-free audio files

**Branch**: `feature/aud-001` (spec directory `003-aud-001-import-drm-free-audio-files`) | **Date**: 2026-11-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/003-aud-001-import-drm-free-audio-files/spec.md`

## Summary

Add an app-managed audio library to `CaptureKit` (`AudioLibrary`, an actor): it validates a picked
file as untrusted input, copies it atomically into `Application Support/AudioLibrary/assets/`
under its SHA-256, and lists it in a versioned, atomically written `index.json`. The existing
In-App Playback source gains a track selection (`InAppPlaybackTrack`: the bundled reference or a
library file), and its AVAudioEngine backend streams a library file in a loop instead of loading
it into memory. `CaptureUI` gets the strings and a "Your Audio" chooser section; the `projectM-iOS`
app adds a thin coordinator, the system file importer and the wiring. No new package, dependency,
entitlement, permission or network use.

## Technical Context

**Language/Version**: Swift 6.4.2, strict concurrency complete (Xcode 27.2, ADR-0002).

**Primary Dependencies**: system frameworks only, all public: AVFAudio (`AVAudioFile`,
`AVAudioEngine`, `AVAudioPlayerNode`, `AVAudioSession`), AVFoundation (`AVURLAsset`, protected-content
check), UniformTypeIdentifiers (`UTType`), CryptoKit (`SHA256`), Foundation (`NSFileCoordinator`,
`FileHandle`), SwiftUI (`fileImporter`). No third-party dependency.

**Storage**: files in the app container: `Library/Application Support/AudioLibrary/` with
`index.json` (versioned Codable, atomic write), `assets/<sha256>.<ext>` (immutable copies) and
`incoming/` (temporary files of imports in flight). No UserDefaults key is added.

**Testing**: XCTest. `CaptureKit` unit tests on the macOS host with audio fixtures generated at run
time (WAV and CAF sine tones; no committed or third-party media), including an offline
(manual-rendering) AVAudioEngine test of the playback graph. `CaptureUI` string tests. Python script
tests. App unit and UI tests are written but need the full app build (main session). Device checks
are deferred to the roadmap's final device phase.

**Target Platform**: iOS/iPadOS 26.0+ (unchanged); packages also build for macOS 15 (tests) and the
model types build on Linux.

**Project Type**: Mobile app (existing `projectM-iOS` target) plus Swift packages.

**Performance Goals**: a 10 MB file is listed within 2 s on D1 (AUD-001-S1); playback memory
independent of track length (AUD-001-S7); no new work on the real-time tap path.

**Constraints**: offline; public APIs only; no networking code; real-time callbacks unchanged
(tap → `PCMSink.write` only); import off the main actor; 500 MB per-file limit.

**Scale/Scope**: tens to hundreds of tracks; index of a few hundred small records, read once at
launch and rewritten on each change.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design: pass.*

| Principle | Status | How |
|---|---|---|
| I. Public Apple APIs only | Pass | Only the frameworks listed above. A DRM-protected file is refused (`AVURLAsset` protected-content check, then `AVAudioFile` open); nothing decrypts or strips protection (AUD-001-R7). |
| II. Capture feasibility first | N/A | In-App Playback of owned files does not depend on external capture. |
| III. ScreenCaptureKit-preferred | N/A | Untouched. |
| IV. Truthful source labeling | Pass | Imported tracks play through the existing `InAppPlaybackSource`, mode `.inAppPlayback`, label "In-App Playback" (AUD-001-R18). No new mode. |
| V. No universal-capture claims | Pass | No compatibility claim; "supported" means the system decoder opens the file. |
| VI. Modular boundaries | Pass | The library and backend live in `CaptureKit`; platform types stay inside it. The `AudioSource` contract is unchanged; `InAppPlaybackBackend.start` gains a `track` parameter. |
| VII. Real-time audio safety | Pass | The tap closure is unchanged. File reads happen on AVAudioPlayerNode's own non-real-time scheduling thread; the loop is rescheduled on the main actor (the player's completion callback only posts a task), so the render thread takes no lock and does no I/O. |
| VIII. Upstream ProjectM fidelity | N/A | No engine or analysis change. |
| IX. Pinned dependencies and license review | Pass | No new dependency. No media is bundled; test fixtures are generated tones. User files are the user's responsibility and are never redistributed. |
| X. Evidence-based quality | Pass | Unit tests for all deterministic logic; device-only checks tagged `{device}` and left open. |
| Security: untrusted imports | Pass | Type, size, protection, decode and channel checks before a file enters the library (AUD-001-R4); failures leave nothing behind (AUD-001-R5). |
| Privacy | Pass with a recorded amendment | "Audio MUST NOT be recorded to disk … by default": nothing captured is recorded. Storing files the user explicitly imports is new persistence; AUD-001-R22 amends FR-065, this spec is the "separate specification", `docs/privacy-policy.md` is updated, and the amendment is flagged for the owner (see Complexity Tracking). |

## Project Structure

### Documentation (this feature)

```text
specs/003-aud-001-import-drm-free-audio-files/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── audio-library.md      # AudioLibrary API, storage layout, index schema, playback seam
│   └── ui-strings.md         # every new user-visible string
├── checklists/requirements.md
└── tasks.md                  # /speckit-tasks
```

### Source Code (repository root)

```text
Packages/CaptureKit/Sources/CaptureKit/
├── AudioLibrary/
│   ├── AudioLibraryModel.swift      # ImportedTrack, AudioLibraryIndex (v1), AudioImportError, outcomes (all platforms)
│   ├── AudioFileInspector.swift     # AudioFileInspecting seam + AVFoundation implementation
│   └── AudioLibrary.swift           # the actor: load/recover, import, remove, file URLs
└── InAppPlayback/
    ├── InAppPlaybackSource.swift    # + InAppPlaybackTrack, `track` property, backend.start(track:…)
    ├── InAppPlaybackGraph.swift     # engine + player + tap + loop scheduling (host-testable)
    └── AVInAppPlaybackBackend.swift # session, observers; delegates the graph
Packages/CaptureKit/Tests/CaptureKitTests/
├── AudioFixtures.swift              # run-time WAV/CAF tone writer
├── AudioLibraryModelTests.swift
├── AudioLibraryTests.swift
├── InAppPlaybackGraphTests.swift
└── SourceAdapterTests.swift         # track selection through the source
Packages/CaptureUI/Sources/CaptureUI/
├── UIStrings.swift                  # + import strings and messages
├── ImportedAudioSection.swift       # "Your Audio" section
└── SourceChooserView.swift          # optional extra sections
Packages/CaptureUI/Tests/CaptureUITests/ImportStringsTests.swift
Apps/projectM-iOS/
├── Coordinators/AudioLibraryCoordinator.swift
├── Coordinators/AppCoordinator.swift   # owns the coordinator; play(track)
├── ProjectMApp.swift                   # section, fileImporter, result alert
├── Tests/AudioLibraryCoordinatorTests.swift
└── UITests/ImportedAudioUITests.swift
scripts/run_device_tests.py, scripts/test_scripts.py   # privacy check allows the library folder only
docs/privacy-policy.md
```

**Structure Decision**: extend `CaptureKit` and `CaptureUI`; no new package, so `project.yml` and
the CI package lists do not change. The app layer holds only presentation state and the picker.

## Design

Details are in [research.md](research.md), [data-model.md](data-model.md) and
[contracts/audio-library.md](contracts/audio-library.md). In short:

1. **Import transaction** (per file, serialized inside the actor):
   type check → coordinated, security-scoped read → streaming copy to `incoming/<uuid>.<ext>` while
   hashing and enforcing the size limit → duplicate check by hash → inspect the temporary copy
   (protection, decode, channels) → rename into `assets/` → atomic index write. Any failure deletes
   the temporary file; a failed index write also deletes the new asset and restores the in-memory
   list (rollback). The security scope ends when the copy ends; the picked URL is never stored.
2. **Load and recovery**: missing index → empty library. Unreadable index → moved to
   `index.damaged.json`, list rebuilt from assets that still inspect. Newer `schemaVersion` →
   library unavailable, nothing touched. Then orphan sweep: `incoming/*`, unreferenced assets,
   entries without a file.
3. **Playback**: `InAppPlaybackSource.track` selects `.reference` or `.file(URL)`.
   `InAppPlaybackGraph` builds the engine; a file track is streamed with
   `AVAudioPlayerNode.scheduleFile`, two passes queued, and rescheduled on the main actor each time
   a pass is consumed (research AUD-001-D7); the
   reference track keeps its in-memory looping buffer. The tap and session handling are unchanged.
4. **UI**: `SourceChooserView` shows `ImportedAudioSection` below the sources. The app presents
   SwiftUI's `fileImporter` for `UTType.audio` with multiple selection, hands the URLs to the
   library off the main actor, then shows one alert summarizing failures and duplicates and posts
   a VoiceOver announcement.

## Testing strategy (deterministic)

- Fixtures: sine tones written by the test at run time with `AVAudioFile` (WAV 16-bit, CAF float),
  into a per-test temporary directory. Clocks and IDs are injected (`now`, `makeID`).
- The inspector is a seam; a fake reports "protected" and decode failures that cannot be produced
  with generated media. The real inspector is tested on real fixtures and on garbage bytes.
- Index writes are tested through an injected `writeIndex` hook that fails, to prove rollback.
- Relaunch = a second `AudioLibrary` over the same directory after deleting the original file.
- Playback = `InAppPlaybackGraph` in AVAudioEngine's offline manual-rendering mode: render more
  frames than the track holds and assert the sink received non-silent PCM past the loop point.
- Not coverable without the app build, a simulator UI run or a device: the Files picker, security
  scope on real providers, the session, routes, interruptions, memory on long tracks. These are
  explicit open tasks.

## Rollback

The feature only adds files under `Application Support/AudioLibrary/`. Reverting the code leaves
that folder unused; no existing data, default or format changes. A later version that changes the
index format bumps `schemaVersion` and adds a pure migration (data-model.md, "Versioning").

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Amends FR-065 (persistence was limited to settings and favorites) | The roadmap row is "copy into a managed local library"; the acceptance needs the copy to survive a relaunch | Keeping a security-scoped bookmark instead of a copy would store a reference to the user's file location, breaks when the original moves, and is ruled out by the acceptance ("without a security-scoped URL") |
