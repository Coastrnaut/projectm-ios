# Tasks: AUD-002 Support common audio containers

**Input**: Design documents in `specs/006-aud-002-support-common-audio-containers/` (spec.md,
plan.md, research.md, data-model.md, contracts/, quickstart.md)

**Tests**: test-first. Each test task comes before the code it covers; the red run (compile
failure or failing assertions) is recorded in AUD-002-T09 before any production change.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. `[P]` = can run in parallel
(different files). Tags: `{device}` = needs a physical device, done only in the roadmap's final
device phase; `{app}` = needs the full `projectM-iOS` build, verified by the main session on the
integration checkout after the merge.

A task is ticked only when its acceptance evidence was produced, with
" — Verified <date>: <how>" appended.

Inside task descriptions, "T07" is short for `AUD-002-T07`. Phase (Constitution, Workflow): all
tasks belong to the roadmap's AUD area, after AUD-001. Every task needs macOS with Xcode except
AUD-002-T04 and AUD-002-T21 (any OS); only `{device}` tasks need a physical device.

## Phase 1: Setup

- [ ] AUD-002-T01 Confirm the baseline before any change: `swift test --package-path Packages/CaptureKit`, `swift test --package-path Packages/CaptureUI`, `python3 scripts/test_scripts.py`, `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py` all pass; record the counts. Evidence: command output.

## Phase 2: Foundational (fixtures and recognition; blocks every story)

- [ ] AUD-002-T02 [P] Extend `Packages/CaptureKit/Tests/CaptureKitTests/AudioFixtures.swift`: `Container` cases for AIFF (16-bit big-endian), M4A/AAC, raw ADTS `.aac`, M4A/Apple Lossless, WAV 8-bit, 24-bit and float; a per-channel frequency parameter (left and right differ); `writeHandAIFF` (classic `FORM/AIFF`, `COMM` with the 80-bit rate, `SSND`) written byte by byte; `writeWAVHeaderOnly`; `writeWAVWithFormatTag(_:)` (tag `0x7A21`); corruption helpers `truncated(_:fraction:)`, `overwritten(_:range:seed:)` with a fixed linear-congruential generator; `copy(_:as:)` for misnaming. No committed media. Evidence: used by T05 to T08.
- [ ] AUD-002-T03 [P] Write `Packages/CaptureKit/Tests/CaptureKitTests/MP3Fixture.swift`: an MPEG-1 Layer III stream writer per research AUD-002-D7 (parameters: sample rate 32,000, 44,100 or 48,000; channels 1 or 2; frame count; one frequency line per channel; optional ID3v2 tag prefix of a given size), with a header comment stating that the content is original, synthesized by this code, and how. Evidence: T06's MP3 rows decode.
- [ ] AUD-002-T04 [P] Write `Packages/CaptureKit/Tests/CaptureKitTests/AudioContainerTests.swift` (fails to compile until T10; pure bytes, also valid on Linux): each signature of data-model.md's `AudioContainer` table is recognized (`RIFF…WAVE`, `FORM…AIFF`, `FORM…AIFC`, `ftyp` at offset 4, MPEG Layer III header, ADTS header); ID3v2 tag then MP3 and then ADTS, including a tag longer than `maxHeaderBytes` through `detect(at:)`; Layer III stream starting after leading zero bytes needs two consistent headers; not recognized: empty data, text, `RIFF` without `WAVE`, MPEG Layer I and II headers, a lone `0xFF 0xFB` followed by garbage away from offset 0, invalid bit-rate or sample-rate index, 3 bytes; `fileExtension` values "mp3", "aac", "m4a", "wav", "aiff"; `detect(at:)` on a missing file returns nil.

## Phase 3: User Story 1 - My MP3, AAC, M4A, WAV and AIFF files all play (P1)

**Goal**: the five formats import and play, mono and stereo, at common rates, at the right pitch.

**Independent test**: `AudioFormatMatrixTests` passes on the host and the simulator.

- [ ] AUD-002-T05 [P] [US1] Write `Packages/CaptureKit/Tests/CaptureKitTests/AudioFormatMatrixTests.swift`, inspector part (fails until T11): for each matrix row (WAV and AIFF at 8, 11.025, 16, 22.05, 32, 44.1, 48 and 96 kHz; M4A/AAC and ADTS at 8, 16, 22.05, 32, 44.1 and 48 kHz; MP3 at 32, 44.1 and 48 kHz; each mono and stereo) `AVAudioFileInspector` reports the sample rate and channel count exactly, the duration within 60 ms (raw AAC: within three packets, 3,072 frames, because the stream's padding is counted), and `container` equal to the row's container. Also: WAV 8-bit, 24-bit and float, classic hand-written AIFF, and Apple Lossless in M4A are accepted.
- [ ] AUD-002-T06 [US1] Same file, import-and-playback part (AUD-002-S1, S2; fails until T12 for misnamed rows only, see T14): each row is imported by a real `AudioLibrary`, the stored file name ends in the container's canonical extension, and the stored copy is rendered by `InAppPlaybackGraph` offline at 48 kHz (and one row per format at 44.1 kHz): at least 0.2 s of non-silent frames reach the sink, and the frequency of the left and of the right output channel, measured by zero crossings over the audible frames, is within 3% of the fixture's left and right frequency (mono: both channels carry the one frequency). A test named `testFiveFixtureFormatsDecode` covers exactly one fixture per format (roadmap acceptance).

## Phase 4: User Story 2 - A file that cannot be used is refused with the real reason (P1)

**Goal**: five distinct, recoverable refusals.

**Independent test**: `AudioCorruptionTests` passes.

- [ ] AUD-002-T07 [P] [US2] Write `Packages/CaptureKit/Tests/CaptureKitTests/AudioCorruptionTests.swift`, reasons part (fails until T10 to T12; AUD-002-S4): through a real `AudioLibrary`, text named `.wav`, `.mp3` and `.m4a` and garbage named `.aiff` → `.unsupportedFormat`; WAV with format tag `0x7A21` → `.unsupportedEncoding`; M4A/AAC cut at 50%, AIFF cut at 50% and at 90%, Apple Lossless cut at 90%, M4A cut at 2% → `.unreadable`; header-only WAV and a zero-byte `.wav` → `.noAudio`; a missing picked file → `.sourceUnavailable`; a 4-channel WAV → `.unsupportedChannelCount(4)` (unchanged). Every refusal leaves the library tree and `index.json` byte-identical and `tracks` unchanged (AUD-002-R9). A WAV, an MP3 and an ADTS file cut at 50% import with the shorter duration and play (AUD-002-R10). A mixed `importFiles` call returns each outcome in order (story 2, scenario 6).
- [ ] AUD-002-T08 [US2] Same file, sweep and recovery part (AUD-002-S3): for each of the five formats, cut at 1%, 10%, 35%, 60%, 85% and 99%, overwrite 64 bytes at 5 seeded offsets, and overwrite the first 16 bytes; every case returns an outcome inside the test time allowance; a refusal leaves the tree identical; an import renders 0.1 s through the graph without throwing. After the sweep the same library imports a valid file and plays it. A graph that is rendering track A keeps delivering non-silent frames while a corrupt file is refused. A header claiming 2 GiB of data is handled without a large allocation (the probe sizes are asserted through `AVAudioFileInspector.probeFrames` and `tailFrames`); a header claiming a 4 GHz, 100 Hz or 0 Hz sample rate is refused as `.unsupportedEncoding` (AUD-002-R16; fails until T11).
- [ ] AUD-002-T09 [US2] Record the red run: `swift test --package-path Packages/CaptureKit > .build/scratch/red-capturekit.log 2>&1` with the tests of T04 to T08, T13, T15 written and no production change; note the compile errors or failing tests in this task's evidence.
- [ ] AUD-002-T10 [US2] Implement `Packages/CaptureKit/Sources/CaptureKit/AudioLibrary/AudioContainer.swift` per contracts/audio-containers.md and research AUD-002-D3 (`maxHeaderBytes = 8192`, `detect(header:)`, `detect(at:)`, `fileExtension`), Foundation only; add `unsupportedFormat`, `unsupportedEncoding`, `noAudio` to `AudioImportError`, `container` to `AudioFileInfo`, and the stored-name rule "`<ext>` is the recognized container's canonical extension, else the picked file's extension" to `ImportedTrack` in `AudioLibraryModel.swift`. Evidence: T04 passes.
- [ ] AUD-002-T11 [US2] Rework `Packages/CaptureKit/Sources/CaptureKit/AudioLibrary/AudioFileInspector.swift` per research AUD-002-D4 and D5: classify open failures, `noAudio` for zero frames, start probe of 4,096 frames, end probe of the last 2,048 frames, `'fmt?'` → `unsupportedEncoding`, sample rate outside `ImportedTrack.supportedSampleRates` (8 kHz…192 kHz, AUD-002-R16) → `unsupportedEncoding`, report `container`. Evidence: T05 and the inspector-level cases of T07 pass.
- [ ] AUD-002-T12 [US2] Update `Packages/CaptureKit/Sources/CaptureKit/AudioLibrary/AudioLibrary.swift`: zero bytes copied → `.noAudio`; recognize the staged file and rename it to the canonical extension inside `incoming/` before inspection; store the asset under the canonical name; failure cleanup removes the staged file under its current name. Amend the two AUD-001 expectations that AUD-002-R8 changes in `AudioLibraryTests.swift` (text or garbage with an audio extension → `.unsupportedFormat`; empty file → `.noAudio`), each with a comment citing AUD-002-R8. Evidence: T06, T07, T08 pass; all AUD-001 library tests pass.

## Phase 5: User Story 3 - The file's content decides, not its name (P2)

**Independent test**: misnamed fixtures import and play, also from a reopened library.

- [ ] AUD-002-T13 [US3] Add to `AudioFormatMatrixTests.swift` (AUD-002-S5; fails until T12): WAV as `.mp3`, WAV as `.m4a`, AIFF as `.wav`, AIFF as `.mp3`, M4A as `.wav`, ADTS as `.mp3`, ADTS as `.m4a`, MP3 as `.aac`, MP3 as `.wav`, and MP3 with an ID3v2 tag: each imports with the true sample rate and channel count, is stored under the canonical extension, plays at its frequency, and plays again from a second `AudioLibrary` opened on the same folder. CAF (not one of the five) still imports under its own extension. AUD-002-R13: after these imports `index.json` still has `schemaVersion` 1 and only AUD-001's fields, and a library folder laid out as AUD-001 wrote it (an asset named with the picked extension, listed in a version 1 record) loads and plays unchanged.
- [ ] AUD-002-T14 [US3] Verify T13 passes with T10 to T12 in place; no further production code is expected. If a row fails, fix the recognition or naming rule and note it here.

## Phase 6: User Story 4 - A track that goes bad later fails cleanly (P3)

- [ ] AUD-002-T15 [P] [US4] Add to `AudioCorruptionTests.swift` (AUD-002-S6; fails until T16): import an M4A and a WAV; overwrite the M4A's stored copy with its first 50%; `InAppPlaybackGraph.load(.file(url))` throws; the library still lists both tracks; the WAV then loads and renders non-silent audio; a stored copy replaced by text also throws; after a successful `load` the first rendered frames are the start of the track (read position back at 0: a 0.05 s fixture still delivers its full length in the first pass).
- [ ] AUD-002-T16 [US4] Implement the decode check in `InAppPlaybackGraph.load` (`Packages/CaptureKit/Sources/CaptureKit/InAppPlayback/InAppPlaybackGraph.swift`) per research AUD-002-D8, plus the sample-rate guard of AUD-002-R16. Evidence: T15 passes; `InAppPlaybackGraphTests` pass unchanged.

## Phase 7: Strings

- [ ] AUD-002-T17 [P] Add tests to `Packages/CaptureUI/Tests/CaptureUITests/ImportStringsTests.swift` (fail until T18): the three messages of contracts/ui-strings.md verbatim; every `AudioImportError` case has a distinct, non-empty message; `importSummary` words a mixed result with the new reasons. Add `UIStringsContainerContractTests` to `scripts/test_scripts.py`: every row of `specs/006-aud-002-support-common-audio-containers/contracts/ui-strings.md` is in `UIStrings.swift` (3 rows).
- [ ] AUD-002-T18 Add the three cases to `UIStrings.message(_: AudioImportError)` in `Packages/CaptureUI/Sources/CaptureUI/UIStrings.swift`. Evidence: T17 passes; `swift build` of CaptureUI has no non-exhaustive switch.

## Phase 8: Verification and polish

- [ ] AUD-002-T19 Run `swift test` for `Packages/CaptureKit` and `Packages/CaptureUI` on the macOS host twice; record counts. Search `Apps/` and `Packages/` for other exhaustive switches over `AudioImportError` and fix any.
- [ ] AUD-002-T20 Run the `CaptureKit` and `CaptureUI` suites on the iOS 27.2 simulator (quickstart B), twice; record counts and any format that behaves differently from the host. Shut the simulator down afterwards.
- [ ] AUD-002-T21 Run `python3 scripts/test_scripts.py`, `python3 scripts/validate_docs.py`, `python3 scripts/check_compliance.py`; record results. Confirm with `git diff --stat` against the branch point that no binary or media file was added (AUD-002-R15) and that no `Package.swift`, `project.yml`, entitlement or workflow file changed (AUD-002-R4).
- [ ] AUD-002-T22 Build the app for the simulator in this worktree (`xcodegen generate`, `xcodebuild build -scheme projectM-iOS`, unsigned) to prove the app compiles against the changed packages; run the app unit tests and `ImportedAudioUITests`. Amend the expectations that AUD-002-R8 changes in `Apps/projectM-iOS/Tests/AudioLibraryCoordinatorTests.swift` and `Apps/projectM-iOS/UITests/ImportedAudioUITests.swift` (bytes that are no audio → unsupported format), and add a damaged-file and an empty-file case there. The generated project is not committed.
- [ ] AUD-002-T23 Update the format matrix with what was verified where in `specs/006-aud-002-support-common-audio-containers/quickstart.md` ("Verified matrix"), and note in `specs/003-aud-001-import-drm-free-audio-files/spec.md`'s edge cases that AUD-002-R8 amends the two refusals.
- [ ] AUD-002-T24 {app} After the merge, on the integration checkout with the full preset library: app unit tests and `ImportedAudioUITests` pass (main session).
- [ ] AUD-002-T25 {device} On D1, D2 and D3 with the owner's own DRM-free files from real encoders: one MP3 (constant bit rate), one MP3 (variable bit rate, ID3 tag with artwork), one `.aac`, one M4A (AAC), one M4A (Apple Lossless), one WAV and one AIFF each import and reach "Active audio" (quickstart D).
- [ ] AUD-002-T26 {device} On D1: a route change (headphones unplugged) and an interruption (alarm) during playback of an MP3 and of an M4A track behave as for the reference track (FR-051).
- [ ] AUD-002-T27 {device} On D1: a damaged file and a non-audio file picked in the Files app show the messages of contracts/ui-strings.md, and VoiceOver announces them.

## Dependencies

- T02, T03 → T05 to T08, T13, T15. T04 → T10. T09 after all test tasks, before T10.
- T10 → T11 → T12 → T14. T16 is independent of T10 to T12. T17 → T18 needs T10 (new cases).
- Stories: US1 needs only the fixtures (the five formats already decode; its tests pin that down);
  US2 carries the production change; US3 is satisfied by US2's code; US4 is independent.
- T19 to T23 after all code. T24 after the merge. T25 to T27 in the final device phase only.

## Parallel examples

T02, T03 and T04 touch different files. T05, T07 and T15 are different test files or sections and
can be drafted together; T17 is in another package.

## Implementation strategy

MVP = US1 + US2 (the roadmap acceptance: "Five fixture formats decode; corrupt files produce
recoverable errors"). US3 falls out of the same naming rule; US4 is a small independent check.
