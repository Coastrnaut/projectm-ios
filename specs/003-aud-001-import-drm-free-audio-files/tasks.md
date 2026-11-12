# Tasks: AUD-001 Import DRM-free audio files

**Input**: Design documents in `specs/003-aud-001-import-drm-free-audio-files/` (spec.md, plan.md,
research.md, data-model.md, contracts/, quickstart.md)

**Tests**: test-first. Each test task comes before the code it covers and must fail (or not
compile) before that code exists.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. `[P]` = can run in parallel
(different files). Tags: `{device}` = needs a physical device, done only in the roadmap's final
device phase; `{app}` = needs the full `projectM-iOS` build or a simulator UI run, which this
worktree cannot do (no preset submodules), so the main session verifies it after the merge.

A task is ticked only when its acceptance evidence was produced, with
" — Verified <date>: <how>" appended.

Inside task descriptions, "T07" is short for `AUD-001-T07`. Phase (Constitution, Workflow): all
tasks belong to the roadmap's AUD area, after feature 001's Phase E. Every task needs macOS with
Xcode except AUD-001-T29 and AUD-001-T30 (any OS); only `{device}` tasks need a physical device.

## Phase 1: Setup

- [X] AUD-001-T01 Confirm the baseline before any change: `swift test --package-path Packages/CaptureKit`, `swift test --package-path Packages/CaptureUI`, `python3 scripts/test_scripts.py`, `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py` all pass; record the test counts. Evidence: command output. — Verified 2026-11-12: CaptureKit 80 and CaptureUI 10 tests passed, compliance and docs OK; `test_scripts.py` had 1 failure caused by the new spec folder (a hard-coded newest-feature name), fixed in the test, then 88 passed.

## Phase 2: Foundational (blocks every story)

**Purpose**: the model, the index format and the test fixtures every story uses.

- [X] AUD-001-T02 [P] Write `Packages/CaptureKit/Tests/CaptureKitTests/AudioFixtures.swift`: helpers that write a sine tone at run time with `AVAudioFile` (WAV 16-bit and CAF float; parameters: seconds, sample rate, channels, frequency), write garbage bytes, and make a unique temporary directory removed in teardown. No committed media. Evidence: used by T03 and later tests. — Verified 2026-11-12: fixtures are used by every `AudioLibraryTests`, `AVAudioFileInspectorTests` and `InAppPlaybackGraphTests` case; `swift test --package-path Packages/CaptureKit` on the Mac Studio (129 tests, 0 failures); same 129 on the iOS 27.2 simulator (`xcodebuild test -scheme CaptureKit`, iPhone Air).
- [X] AUD-001-T03 [P] Write `Packages/CaptureKit/Tests/CaptureKitTests/AudioLibraryModelTests.swift` (fails until T04): a version 1 golden `index.json` literal decodes to the expected `ImportedTrack` values; encode → decode round trip; encoding has `schemaVersion` 1, sorted keys and ISO-8601 dates; unknown keys are ignored; the version probe reports a newer `schemaVersion`; track validation rejects each broken field from data-model.md (`sha256` not "64 lowercase hex digits", `fileName` containing `/` or `..`, `byteCount` outside "1 … 524 288 000", `durationSeconds` or `sampleRate` not "> 0", `channelCount` not "1 or 2"); title rule "trimmed; at most 200 characters; "Untitled" if empty"; stored-extension rule "lowercased and reduced to at most 8 ASCII letters or digits". — Verified 2026-11-12: failed to compile before T04 (`cannot find type 'ImportedTrack'`), then `AudioLibraryModelTests` 10 of 10 passed.
- [X] AUD-001-T04 Implement `Packages/CaptureKit/Sources/CaptureKit/AudioLibrary/AudioLibraryModel.swift`: `ImportedTrack`, `AudioLibraryIndex` (`currentSchemaVersion = 1`, `encoded()`, `decode(_:)` with version probe and migration hook), `AudioLibraryState`, `AudioImportError`, `AudioImportOutcome`, `AudioFileInfo`, title and extension helpers. Foundation only, compiles on Linux. Evidence: T03 passes. — Verified 2026-11-12: `AudioLibraryModelTests` 10 of 10 passed on the host and the simulator. Linux build not run (no Linux host here).
- [X] AUD-001-T05 [P] Write the inspector tests in `Packages/CaptureKit/Tests/CaptureKitTests/AudioLibraryTests.swift` (`AVAudioFileInspectorTests`, fails until T06): a WAV and a CAF fixture report the right duration (±1 ms), sample rate and channel count; garbage bytes named `.wav` and an empty file throw `.unreadable`; a 4-channel fixture throws `.unsupportedChannelCount(4)`. — Verified 2026-11-12: `AVAudioFileInspectorTests` 4 of 4 passed (written together with T06; no separate red run recorded).
- [X] AUD-001-T06 Implement `Packages/CaptureKit/Sources/CaptureKit/AudioLibrary/AudioFileInspector.swift`: `AudioFileInspecting` and `AVAudioFileInspector` per research AUD-001-D5 (protected-content check, open, length, sample rate, channels, one read of up to 4096 frames). Evidence: T05 passes. — Verified 2026-11-12: `AVAudioFileInspectorTests` 4 of 4 passed; the protected-content branch is covered only through the inspector seam (no DRM fixture can be generated).

**Checkpoint**: model and inspector tested on the host.

## Phase 3: User Story 1 - Import my own audio and watch it (P1)

**Goal**: pick audio in Files, see it under "Your Audio", tap it, it plays as In-App Playback.

**Independent test**: quickstart A (package tests) and D steps 1-3.

### Tests first

- [X] AUD-001-T07 [US1] Write `AudioLibraryTests` import cases in `Packages/CaptureKit/Tests/CaptureKitTests/AudioLibraryTests.swift` (fail until T08): importing a valid WAV returns `.imported` with title from the file name, the injected id and date, byte count equal to the file size and the SHA-256 of the bytes; the asset exists at `assets/<sha256>.wav` and equals the source byte for byte; `incoming/` is empty; `index.json` on disk lists exactly that track and no path or source location; `importFiles` returns outcomes in input order; `fileURL(for:)` resolves inside `assets/`. — Verified 2026-11-12: `AudioLibraryTests` import cases passed (written together with T08; no separate red run recorded).
- [X] AUD-001-T08 [US1] Implement `Packages/CaptureKit/Sources/CaptureKit/AudioLibrary/AudioLibrary.swift`: the actor per contracts/audio-library.md with `defaultDirectory()`, `load()` (create folders, read index), the import transaction of plan.md Design 1 (type check, security scope and file coordination, streaming copy with SHA-256 and size cap, inspect, rename, atomic index write), `importFiles`, `tracks`, `fileURL(for:)`, and the serial chain of research AUD-001-D9. Evidence: T07 passes. — Verified 2026-11-12: `AudioLibraryTests` 26 of 26 passed; `swift test --package-path Packages/CaptureKit` on the Mac Studio (129 tests, 0 failures); same 129 on the iOS 27.2 simulator (`xcodebuild test -scheme CaptureKit`, iPhone Air).
- [X] AUD-001-T09 [P] [US1] Write `Packages/CaptureKit/Tests/CaptureKitTests/InAppPlaybackGraphTests.swift` (fails until T10): a graph built on a 0.25 s stereo tone fixture as `.file`, in offline manual-rendering mode, delivers to a `PCMSink` more than three passes of the track as non-silent samples at the tone's amplitude (so the loop rescheduled); a missing or undecodable file throws; `stop()` twice is safe and nothing is scheduled after it. — Verified 2026-11-12: failed to compile before T10 (`cannot find type 'InAppPlaybackGraph'`); the first implementation then hung in `play()` (research AUD-001-D7 finding); after the fix `InAppPlaybackGraphTests` 5 of 5 passed, four runs in a row.
- [X] AUD-001-T10 [US1] Implement `Packages/CaptureKit/Sources/CaptureKit/InAppPlayback/InAppPlaybackGraph.swift` (engine, player, mixer tap into `PCMSink`, in-memory loop for a buffer, streaming loop for a file per research AUD-001-D7, offline rendering entry point for tests) and move the engine code of `AVInAppPlaybackBackend.swift` onto it without changing the tap closure's behavior. Evidence: T09 passes; iOS Simulator build of CaptureKit succeeds. — Verified 2026-11-12: `InAppPlaybackGraphTests` 5 of 5 passed on the host and the simulator (offline manual rendering); `xcodebuild -scheme CaptureKit -destination 'generic/platform=iOS Simulator' build` succeeded with no warnings. Real-time playback through the audio session was exercised only by the simulator UI test of T19.
- [X] AUD-001-T11 [US1] Extend `Packages/CaptureKit/Tests/CaptureKitTests/SourceAdapterTests.swift` (fails until T12): `InAppPlaybackSource.track` defaults to `.reference`; the backend receives the selected `.file(url)` at `start`; a backend failure for a file track surfaces `.inAppPlaybackFailed` and the fake records no fallback start; `mode` is `.inAppPlayback` for both tracks; a restart through `CaptureManager` starts the same track again. — Verified 2026-11-12: `InAppPlaybackSourceTests` 7 of 7 passed (4 new).
- [X] AUD-001-T12 [US1] Add `InAppPlaybackTrack` and `InAppPlaybackSource.track`, change `InAppPlaybackBackend.start` to `start(track:sink:onEvent:)` in `Packages/CaptureKit/Sources/CaptureKit/InAppPlayback/InAppPlaybackSource.swift`, and make `AVInAppPlaybackBackend.swift` open `.reference` from the bundle and `.file` from its URL (never substituting one for the other). Evidence: T11 and the existing CaptureKit suite pass. — Verified 2026-11-12: CaptureKit suite 129 of 129 passed; CaptureLab builds unchanged (`xcodebuild build -scheme CaptureLab`, simulator).
- [X] AUD-001-T13 [P] [US1] Write `Packages/CaptureUI/Tests/CaptureUITests/ImportStringsTests.swift` (fails until T14): every `AudioImportError` maps to its string in contracts/ui-strings.md; the size limit is formatted ("500 MB"); `importSummary` returns nil for an empty or all-cancelled result, "Imported 1 track." / "Imported ‹n› tracks.", one line per duplicate and per failure in input order; duration text `m:ss` and `h:mm:ss`; spoken duration; the unavailable messages. — Verified 2026-11-12: `ImportStringsTests` 9 of 9 passed (written together with T14; no separate red run recorded).
- [X] AUD-001-T14 [US1] Add the strings and helpers of contracts/ui-strings.md to `Packages/CaptureUI/Sources/CaptureUI/UIStrings.swift`, and add a `UIStringsImportContractTests` case to `scripts/test_scripts.py` that checks every string of that contract is in the Swift file. Evidence: T13 and the script test pass. — Verified 2026-11-12: `swift test --package-path Packages/CaptureUI` 19 of 19 passed (host and iOS 27.2 simulator); `UIStringsImportContractTests` passed in `python3 scripts/test_scripts.py` (90 tests OK).

### Implementation

- [X] AUD-001-T15 [US1] Add `Packages/CaptureUI/Sources/CaptureUI/ImportedAudioSection.swift` (section title, import button with progress state, track rows newest first with title, duration, accessibility label and hint, empty and unavailable texts, footer, remove action) and give `SourceChooserView.swift` an optional trailing-sections builder that defaults to nothing; add a preview in `Previews.swift`. Evidence: CaptureUI builds for macOS and the iOS Simulator; existing CaptureUI tests pass; CaptureLab's call site is unchanged. — Verified 2026-11-12: CaptureUI builds for macOS and the iOS Simulator with no warnings, 19 tests passed; CaptureLab's call site is unchanged and builds; the section was shown and used in `ImportedAudioUITests`.
- [X] AUD-001-T16 [US1] {app} Write `Apps/projectM-iOS/Tests/AudioLibraryCoordinatorTests.swift` (before T17): with a library in a temporary directory, `importPicked(.success(urls))` lists the track newest first, sets and clears `isImporting`, sets the summary message for a rejected file and none for a clean single import; `importPicked(.failure)` for a cancelled picker shows nothing. — Verified 2026-11-12: `AudioLibraryCoordinatorTests` 9 of 9 passed, built and run from a scratch XcodeGen project (`project.yml` minus the preset build phase, because this worktree has no preset submodules) on the iOS 27.2 simulator (iPhone Air). Written with T17 (no separate red run). To be repeated by the main session on the full build.
- [X] AUD-001-T17 [US1] Add `Apps/projectM-iOS/Coordinators/AudioLibraryCoordinator.swift` (`@MainActor @Observable`: `tracks`, `isImporting`, `unavailableMessage`, `resultMessage`; `load()`, `importPicked(_:)`, `remove(_:)`, `fileURL(for:)`; VoiceOver announcement of the result) and wire it into `Apps/projectM-iOS/Coordinators/AppCoordinator.swift` (`audioLibrary`, `play(_ track:)` selecting `.file` and starting In-App Playback, `select(.inAppPlayback)` selecting `.reference`, the Debug launch argument `-uitestImportAudio <path>`). Evidence {app}: app builds; T16 passes. — Verified 2026-11-12: the app and its test bundles build (`xcodebuild build-for-testing`, simulator, scratch project as in T16); T16 passed.
- [ ] AUD-001-T18 [US1] Show the section in `Apps/projectM-iOS/ProjectMApp.swift`: `ImportedAudioSection` in the chooser, SwiftUI `fileImporter` for `UTType.audio` with multiple selection, and the result alert. Evidence {app}: app builds; quickstart D steps 1-3 on a simulator. — Open: the app builds and `ImportedAudioUITests` shows the section, opens the system Files picker and cancels it (`testImportAudioOpensTheFilesPickerAndCancelChangesNothing`, iOS 27.2 simulator, 2026-11-12). Picking a file inside the system picker (quickstart D steps 1-3) was not done: it needs a person or the device phase.
- [X] AUD-001-T19 [US1] {app} Write `Apps/projectM-iOS/UITests/ImportedAudioUITests.swift`: launch with `-uitestImportAudio` pointing at a tone the test writes, find the row under "Your Audio", tap it, and read "In-App Playback" from the source indicator. Evidence: the UI test passes on an iOS 27.2 simulator. — Verified 2026-11-12: `ImportedAudioUITests.testImportPlayRelaunchWithoutOriginalAndPlayAgain` passed (indicator "In-App Playback · …"), built and run from a scratch XcodeGen project (`project.yml` minus the preset build phase, because this worktree has no preset submodules) on the iOS 27.2 simulator (iPhone Air). Simulator only, never device evidence.

**Checkpoint**: US1 works from the package level up; app-level evidence is `{app}`.

## Phase 4: User Story 2 - Still there offline, without the original (P1)

**Goal**: the copy is the track; a relaunch needs nothing else.

**Independent test**: quickstart D step 4; `AudioLibraryTests` relaunch cases.

- [X] AUD-001-T20 [US2] Write relaunch and recovery cases in `Packages/CaptureKit/Tests/CaptureKitTests/AudioLibraryTests.swift` (fail until T21 where behavior is missing): after an import, delete the original and open a second `AudioLibrary` on the same directory: same track, `fileURL(for:)` opens with `AVAudioFile` and plays through `InAppPlaybackGraph` offline with non-silent output; a leftover file in `incoming/` and an unreferenced file in `assets/` are deleted by `load()`; an entry whose asset is missing is dropped and the index rewritten; a truncated `index.json` is moved to `index.damaged.json` and the list is rebuilt from the assets with titles "Recovered track 1…"; an index with `schemaVersion` 2 gives `unavailable(newerFormat)`, leaves every file byte-identical, and makes import and removal return `libraryUnavailable`. — Verified 2026-11-12: the relaunch, sweep, missing-asset, damaged-record, newer-format and unusable-folder cases in `AudioLibraryTests`, and `InAppPlaybackGraphTests.testImportedLibraryTrackPlaysAfterRelaunchWithoutTheOriginal`, passed; `swift test --package-path Packages/CaptureKit` on the Mac Studio (129 tests, 0 failures); same 129 on the iOS 27.2 simulator (`xcodebuild test -scheme CaptureKit`, iPhone Air).
- [X] AUD-001-T21 [US2] Complete `load()` in `Packages/CaptureKit/Sources/CaptureKit/AudioLibrary/AudioLibrary.swift`: sweep, missing-asset pruning, damaged-index recovery (AUD-001-R14), newer-format handling (AUD-001-R15) and storage failure state. Evidence: T20 passes. — Verified 2026-11-12: the T20 cases passed.
- [X] AUD-001-T22 [US2] {app} Extend `Apps/projectM-iOS/UITests/ImportedAudioUITests.swift`: after the import, delete the source file, relaunch without the import argument, find the row and play it. Evidence: the UI test passes on a simulator. — Verified 2026-11-12: the second half of `testImportPlayRelaunchWithoutOriginalAndPlayAgain` (original deleted, relaunch without the import argument, track listed and played) passed on the iOS 27.2 simulator (scratch project as in T16).
- [ ] AUD-001-T23 [US2] {device} On D1: import from Files, delete the original, Airplane Mode, relaunch, play (quickstart D 1-4). Evidence: tester note in `docs/test-reports/` in the final device phase. — Open: device phase.

## Phase 5: User Story 3 - Refused files (P2)

**Goal**: every refusal has its message and leaves nothing behind.

**Independent test**: `AudioLibraryTests` rejection cases; quickstart D steps 5-6.

- [X] AUD-001-T24 [US3] Write rejection cases in `Packages/CaptureKit/Tests/CaptureKitTests/AudioLibraryTests.swift` (fail until T25 where behavior is missing), each asserting the outcome and that the directory tree and `index.json` bytes are unchanged: a `.txt` file → `.notAudio`; garbage bytes named `.wav` → `.unreadable`; a fixture larger than an injected small `maxFileBytes` → `.tooLarge(limitBytes:)` with the copy stopped at the limit; a 4-channel fixture → `.unsupportedChannelCount(4)`; a fake inspector reporting protection → `.protectedContent`; a missing source → `.sourceUnavailable`; an injected index-write failure → `.libraryUnavailable` with the new asset removed and `tracks` unchanged; the same content under another name → `.duplicate` of the first track, one asset on disk; two concurrent imports of the same content → one `.imported`, one `.duplicate`. — Verified 2026-11-12: the refusal, rollback, duplicate and concurrent-import cases in `AudioLibraryTests` passed (written with T25; no separate red run). Protected content through the inspector seam only.
- [X] AUD-001-T25 [US3] Complete the failure paths in `Packages/CaptureKit/Sources/CaptureKit/AudioLibrary/AudioLibrary.swift`: error mapping (out of space → `.insufficientStorage`), cleanup on every exit, rollback of a failed index write, duplicate detection before inspection. Evidence: T24 passes. — Verified 2026-11-12: the T24 cases passed; out-of-space is covered by an injected `fileWriteOutOfSpace` error on the record write, not by a full disk.
- [ ] AUD-001-T26 [US3] {device} With a real DRM-protected purchase in Files on D1: the import is refused with the copy-protected message and nothing is stored (AUD-001-R7). Evidence: tester note in the final device phase. — Open: device phase; needs a real protected file.

## Phase 6: User Story 4 - Remove a track (P3)

- [X] AUD-001-T27 [US4] Write removal cases in `Packages/CaptureKit/Tests/CaptureKitTests/AudioLibraryTests.swift` (fail until T28): removing a track deletes its asset and its index entry and survives a reopen; removing an unknown id is a no-op; a failed index write leaves the track and its asset in place. — Verified 2026-11-12: the three removal cases in `AudioLibraryTests` passed.
- [X] AUD-001-T28 [US4] Implement `remove(_:)` in `Packages/CaptureKit/Sources/CaptureKit/AudioLibrary/AudioLibrary.swift` (index first, then the asset) and connect the section's remove action through `AudioLibraryCoordinator.remove(_:)`. Evidence: T27 passes; {app} quickstart D step 7. — Verified 2026-11-12: T27 passed; `AudioLibraryCoordinatorTests.testRemoveDeletesTheTrack` and `ImportedAudioUITests.testSwipeToRemoveDeletesTheTrack` (swipe, Remove, relaunch) passed on the iOS 27.2 simulator (scratch project as in T16).

## Phase 7: Polish and cross-cutting

- [X] AUD-001-T29 [P] Update `scripts/run_device_tests.py` `privacy_problems` per research AUD-001-D12 and add cases to `scripts/test_scripts.py`: an audio file in `Library/Application Support/AudioLibrary/assets/` is allowed; the same file in `Documents/`, `tmp/` or elsewhere under `Library/` is still reported. Evidence: script tests pass. — Verified 2026-11-12: `python3 scripts/test_scripts.py`: 90 tests OK, including `test_privacy_allows_only_the_imported_audio_library`.
- [X] AUD-001-T30 [P] Update `docs/privacy-policy.md`: imported audio files and the library record are stored on the device, only when the user imports them, removable in the app, never transmitted; captured audio is still never stored (AUD-001-R22). Evidence: `python3 scripts/validate_docs.py` passes; text review. — Verified 2026-11-12: `python3 scripts/validate_docs.py` OK (69 files); text reviewed against AUD-001-R22.
- [X] AUD-001-T31 Run the full local gate: `swift test` for CaptureKit and CaptureUI, iOS Simulator builds of CaptureKit and CaptureUI with no warnings from new code, `python3 scripts/test_scripts.py`, `check_compliance.py`, `validate_docs.py`; and confirm AUD-001-R23 by search: no source under `Packages/Diagnostics/` or the app's export path refers to the audio library, track titles or file names, and no networking API was added. Evidence: command output recorded in this file. — Verified 2026-11-12: host: AudioCore 77, CaptureKit 129, CaptureUI 19, Diagnostics 8 tests, 0 failures, no warnings in the logs; iOS 27.2 simulator: CaptureKit 129, CaptureUI 19; iOS Simulator builds of CaptureKit and CaptureUI succeeded with no warnings; `test_scripts.py` 90 OK; `check_compliance.py` OK; `validate_docs.py` OK; search: no reference to the audio library in `Packages/Diagnostics/Sources` or `Apps/CaptureLab`, and no networking API in the added lines.
- [ ] AUD-001-T32 {app} Build `projectM-iOS` and CaptureLab after the merge, run the app unit and UI tests of this feature and the existing suites, and run `python3 scripts/check_privacy_manifest.py` on the built app (no new required-reason API, research AUD-001-D11). Evidence: build and test logs. — Open: partly done 2026-11-12 on a scratch project without the preset build phase: `projectM-iOS` and CaptureLab build for the simulator; this feature's tests pass (9 unit, 4 UI); of the existing suites run there, `StatusUITests` 7 of 7 and `VisualizerUITests` 6 of 7 passed and the app unit bundle ran 39 tests; the two failures (`PresetTests.testBundledIncludedScopeMatchesRelease1_0`, `VisualizerUITests.testPresetBrowser`) need the preset index that the scratch build lacks, and `LibraryStoreTests.testFailureUnlocksNothing` hit the 3-minute limit (StoreKit test, code untouched by this feature; not diagnosed). `check_privacy_manifest.py` passed on the Debug simulator app, which is not the Release device build. The main session must repeat this on the full build.
- [ ] AUD-001-T33 {device} Final device phase: routes and interruptions with an imported track (FR-051); AUD-001-S1 (10 MB file listed within 2 s on D1); AUD-001-S7 (memory with a 60-minute track); a file from iCloud Drive; the privacy review with a non-empty library. Evidence: `docs/test-reports/`. — Open: device phase.

## Dependencies and order

- T01 → Phase 2 (T02-T06) → US1 (T07-T19). US2 (T20-T23), US3 (T24-T26) and US4 (T27-T28) each
  need T08; they are independent of one another. Polish last.
- Within a story: the test task precedes its implementation task.
- Parallel: T02, T03 and T05 (different files); T09 and T13 alongside T07; T29 and T30.

## Implementation strategy

MVP = Phases 1-3 at package level (library + playback seam + strings + section), then the app
wiring. US2 and US3 complete the acceptance criterion and the untrusted-input rules and ship with
it; US4 is small and ships with it too. `{app}` and `{device}` tasks stay open with their reason.

## Requirement coverage

| Requirement | Tasks |
|---|---|
| AUD-001-R1, R9 | T15, T17, T18 |
| AUD-001-R2, R3, R11, R12 | T03, T04, T07, T08, T20 |
| AUD-001-R4, R5, R6, R7, R8 | T05, T06, T13, T14, T24, T25, T26 |
| AUD-001-R10, R24 | T13, T14, T15, T17 |
| AUD-001-R13 | T27, T28 |
| AUD-001-R14, R15, R16 | T20, T21 |
| AUD-001-R17, R18, R19, R20, R21 | T09, T10, T11, T12, T17, T19, T33 |
| AUD-001-R22, R23 | T29, T30, T31, T32 |
| AUD-001-S1, S7 | T33 |
| AUD-001-S2 | T20, T22, T23 |
| AUD-001-S3, S4 | T24 |
| AUD-001-S5 | T20 |
| AUD-001-S6 | T19 |

## Analysis (speckit-analyze, 2026-11-12)

Findings and the fixes applied; no CRITICAL finding.

| ID | Severity | Finding | Fix |
|---|---|---|---|
| C1 | MEDIUM | AUD-001-R23 (diagnostics export carries no track data) had no verifying task | Added the search to AUD-001-T31 |
| C2 | LOW | Tasks did not state their macOS or device needs (Constitution, Workflow) | Added the note above Phase 1 |
| I1 | LOW | Short task references ("T07") differed from the IDs | Defined the short form |
| I2 | LOW | AUD-001-T16 had a stray ellipsis | Reworded |
| P1 | MEDIUM (privacy) | AUD-001-R22 amends FR-065 and the constitution's "audio is not recorded to disk by default" wording could be read as covering imports | Plan Constitution Check and Complexity Tracking record it; `docs/privacy-policy.md` (AUD-001-T30) and the device privacy check (AUD-001-T29) are updated; flagged for the owner in the feature report |
| L1 | none (licensing) | No media is bundled or committed; fixtures are generated tones; no new dependency; the Licenses screen needs no entry | No change |
| X1 | LOW (cross-feature) | `InAppPlaybackBackend.start` gains a `track` parameter; implementers are `AVInAppPlaybackBackend` and the test fake only, and CaptureLab constructs the backend with its default initializer | AUD-001-T12 keeps the default initializer; CaptureLab is rebuilt in AUD-001-T32 |
| X2 | none (cross-feature) | AUD-002 to AUD-006 extend this library: format guarantees, queue order, repeat and shuffle state, transport | data-model.md "Versioning" reserves the extension path; nothing of theirs is implemented here |

Coverage: 24 of 24 requirements and 7 of 7 success criteria have at least one task (table above).
