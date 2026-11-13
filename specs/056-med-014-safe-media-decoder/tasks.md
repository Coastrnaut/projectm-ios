# Tasks: MED-014 Safe Media Decoder

**Input**: Design documents from `specs/056-med-014-safe-media-decoder/` (spec, plan, research,
data-model, contracts/safe-decoder.md, quickstart)

**Tests**: requested by the spec (S1-S6, R14) and owner rule 7 budgets (unit ≈ 1-2 s, suite < 1 min, UI
test < 30 s). Tick a task `[X]` only when verified, with " — Verified <date>: <how>".

Format: `- [ ] MED-014-Tnn [P?] [Story?] Description with file path`

## Phase 1: Setup

- [X] MED-014-T01 Add target `MediaSniffing` (no dependencies) to the library product, make `ImageLayer` and `VideoLayer` depend on it, add test target `MediaSniffingTests` (dependency `MediaSniffing`) and add `MediaSniffing` to `CompositorTests`' dependencies, with a header comment line for MED-014, in `Packages/Compositor/Package.swift` — Verified 2026-11-13: `swift build`/`swift test --package-path Packages/Compositor --filter MediaSniffingTests` (target and test target build and run)

## Phase 2: Foundational (plain Swift, every host; blocks all stories)

- [X] MED-014-T02 [P] `MediaSniffError` (`empty unrecognized truncated corrupt unreadable`), `ByteSource`, `DataByteSource`, `FileByteSource` (FileHandle, `seek` + `read(upToCount:)`, reads clamped to the file length) in `Packages/Compositor/Sources/MediaSniffing/ByteSource.swift` (R13) — Verified 2026-11-13: MovieContainerSnifferTests.testFileByteSourceReadsOnlyWhatItIsAskedFor (clamped reads, missing file → unreadable), host and Linux shape
- [X] MED-014-T03 [P] CRC-32 (PNG polynomial, table) in `Packages/Compositor/Sources/MediaSniffing/CRC32.swift` — Verified 2026-11-13: PNG fixtures with computed CRCs pass and a flipped byte fails (ImageHeaderSnifferTests), host and Linux shape
- [X] MED-014-T04 Fixture builders `MediaFixtureBytes` in `Packages/Compositor/Sources/MediaSniffing/MediaFixtureBytes.swift` (in the library, not a test target, so CompositorTests and the app's DEBUG seeds share them; nothing on the decode path uses them): PNG from chunks with computed CRCs and a stored (uncompressed) zlib stream; minimal ISO boxes (`ftyp`, `moov/trak/mdia/hdlr/minf/stbl/stsd`); SplitMix64 (research D6, D7) — Verified 2026-11-13: used by all 20 MediaSniffingTests, host and Linux shape

## Phase 3: User Story 1 — A damaged or hostile image is refused (P1, MVP)

**Goal**: PNG/JPEG/HEIF structure and header size checked before ImageIO. **Independent test**: the image rows of the fixture table.

- [X] MED-014-T05 [US1] `ImageHeaderSniffer.sniff(_:)` and `ImageHeaderFacts`/`ImageContainer` in `Packages/Compositor/Sources/MediaSniffing/ImageHeaderSniffer.swift`: PNG, JPEG, HEIF rules exactly as research D2 (R1-R4); `.other` for anything else; `.empty` for no bytes — Verified 2026-11-13: ImageHeaderSnifferTests 10/10 on the host and in the Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`)
- [X] MED-014-T06 [US1] `ImageIODecoder` in `Packages/Compositor/Sources/ImageLayer/ImageDecoding.swift`: sniff after the size check (`.empty` → `.notAnImage`, `.truncated`/`.corrupt`/`.unreadable` → `.damaged`), header pixel count > `maxPixelCount` → `.tooManyPixels` before ImageIO (R5, R6, R11); header comment updated — Verified 2026-11-13: SafeDecoderTests.testImageFixtureTable and ImageImportTests 10/10 (truncated PNG now `.damaged`); full CompositorTests 179/179 on the host, 100 in the Linux shape
- [X] MED-014-T07 [P] [US1] Image sniffer tests in `Packages/Compositor/Tests/MediaSniffingTests/ImageHeaderSnifferTests.swift`: F1-F4, F8-F11 and a valid HEIF header with two `ispe` (largest wins), PNG with junk after IEND, JPEG with bytes after EOI, APNG-style ancillary chunk (Linux shape) — Verified 2026-11-13: ImageHeaderSnifferTests 10/10, host and Linux shape
- [X] MED-014-T08 [US1] Decoder table in `Packages/Compositor/Tests/CompositorTests/SafeDecoderTests.swift`: F1-F9 through `ImageSanitizer.sanitize` with exact `ImageImportError`s (F5-F7 encoded by ImageIO; R6's thumbnail bound stays covered by MED-001's scale-down test, analyze C3), and MED-001's `testDamagedImagesAreRefused` comment updated to cite MED-014 with a truncated-PNG assertion in `Packages/Compositor/Tests/CompositorTests/ImageImportTests.swift` (S1) — Verified 2026-11-13: SafeDecoderTests.testImageFixtureTable (F1-F11 exact outcomes) and ImageImportTests.testDamagedImagesAreRefused, host

## Phase 4: User Story 2 — A damaged or hostile video is refused (P1)

**Goal**: container checked before AVFoundation; non-blocking first-picture check. **Independent test**: the movie rows of the fixture table.

- [X] MED-014-T09 [US2] `MovieContainerSniffer.sniff(_:limits:)`, `MovieContainerFacts`, `MovieSniffLimits` (`maxBoxes` 4,096, `maxDepth` 8, `maxTracks` 64, `maxEntryBytes` 4,096) in `Packages/Compositor/Sources/MediaSniffing/MovieContainerSniffer.swift` (R7, R8) — Verified 2026-11-13: MovieContainerSnifferTests 8/8, host and Linux shape
- [X] MED-014-T10 [US2] `VideoProbe.check` in `Packages/Compositor/Sources/VideoLayer/AVVideoProbe.swift`: sniff with `FileByteSource` after the size check (mapping per contract), then AVFoundation; first picture with `AVAssetImageGenerator.image(at: .zero)`, `maximumSize` 256 × 256, tolerances `.positiveInfinity`, `appliesPreferredTrackTransform` false (R8, R9); `AVVideoFrameReader.open` sniffs before each open in `Packages/Compositor/Sources/VideoLayer/AVVideoFrameReader.swift` (R12) — Verified 2026-11-13: SafeDecoderTests.testMovieFixtureTable and VideoImportTests 4/4 (the MED-002 cut-movie case now `.damaged`, expectation updated with a MED-014 note); SafeDecoderIsolationTests (reader reopen), host
- [X] MED-014-T11 [P] [US2] Movie sniffer tests in `Packages/Compositor/Tests/MediaSniffingTests/MovieContainerSnifferTests.swift`: F12, F13, F15, F16, 64-bit size, size 0 last box, `moov` after `mdat`, two `moov`, depth > 8, box count > 4,096, `FileByteSource` on a temporary file (Linux shape) — Verified 2026-11-13: MovieContainerSnifferTests 8/8, host and Linux shape
- [X] MED-014-T12 [US2] Movie rows in `Packages/Compositor/Tests/CompositorTests/SafeDecoderTests.swift`: F12-F16 through `VideoProbe.check` with exact `VideoImportError`s; F14 sniffed facts `avc1` 64 × 48 (S1) — Verified 2026-11-13: SafeDecoderTests.testMovieFixtureTable (F12-F16 + zero bytes exact outcomes, F14 facts avc1 64 × 48), host

## Phase 5: User Story 3 — Typed result for every malformed file (P1)

- [X] MED-014-T13 [P] [US3] Fuzz in `Packages/Compositor/Tests/MediaSniffingTests/SnifferFuzzTests.swift`: seed fixed, ≥ 2,000 mutations (bit flip, overwrite, truncate, duplicate range, insert, length field 0xFFFFFFFF) over the PNG, HEIF-header and movie-header fixtures; every result facts or `MediaSniffError` (S2) — Verified 2026-11-13: SnifferFuzzTests 2/2 (2,700 mutations, 0.02 s), host and Linux shape
- [X] MED-014-T14 [US3] Decoder fuzz in `Packages/Compositor/Tests/CompositorTests/SafeDecoderTests.swift`: ≈ 300 mutations of F1 and F5 through `ImageIODecoder`; every result a picture or an `ImageImportError` (S2) — Verified 2026-11-13: SafeDecoderTests.testDecoderFuzzAlwaysGivesAPictureOrATypedError (300 mutations, 0.01 s), host

## Phase 6: User Story 4 — A stored file that breaks later does not stop the show (P1)

**Goal**: the row's acceptance. **Independent test**: running compositor with broken layers.

- [X] MED-014-T15 [US4] Isolation acceptance in `Packages/Compositor/Tests/CompositorTests/SafeDecoderTests.swift`: `Compositor` at 64 × 64 with an opaque `SolidLayer` (index 0, bottom), `ImageLayerSource` (1) and `VideoLayerSource` (2); both media start valid and render. (a) Load time: the photo's stored file is overwritten with F2 and the content set again → `.failed(.damaged)`. (b) Mid-playback: the playing video's file is overwritten with F12 and playback advanced past the 2 s loop in 0.5 s steps → the reader's reopen fails → `.failed(.damaged)` with no content change. For every frame `composite` returns true, the broken layers report `.fallback`, and the output equals the solid color (S3, R12; analyze C1, C2) — Verified 2026-11-13: SafeDecoderIsolationTests.testCorruptStoredMediaFailGracefullyAndTheCompositorKeepsRunning (18/18 frames produced, photo and video `.failed(.damaged)`, output = solid layer within 1/255; 0.25 s), host Metal
- [X] MED-014-T16 [US4] App DEBUG seeds in `Apps/projectM-iOS/Debug/UITestPhotoFixture.swift` (`corrupt`: the valid seed is imported, then its stored copy is cut to half in place) and `Apps/projectM-iOS/Debug/UITestVideoFixture.swift` (`corrupt`: the valid seed is imported, then its stored copy is replaced by `MediaFixtureBytes.movieWithOverrunningMoov()`), so the seeds exercise the load-time path (R12, R14) — Verified 2026-11-13: SafeMediaUITests passes with both seeds; PhotoLayerUITests and VideoLayerUITests (`solid`/`counter`) still pass, iOS 27.2 simulator
- [X] MED-014-T17 [US4] UI test `Apps/projectM-iOS/UITests/SafeMediaUITests.swift`: launch with both corrupt seeds; choosing Photo shows "The photo couldn't be loaded." and draws no photo frame, choosing Video shows "The video couldn't be played." (visualizer, within 10 s); Settings opens and closes afterwards; the audio source never restarted (S4) — Verified 2026-11-13: `xcodebuild test … -only-testing:projectM-iOSUITests/SafeMediaUITests` passed (15.9 s), iOS 27.2 simulator "MED14 iPhone 17"

## Phase 7: User Story 5 — No priority inversion from the import (P2)

- [X] MED-014-T18 [US5] Investigate the coordinated picked-file reads in `Apps/projectM-iOS/Coordinators/PhotoStore.swift` and `Apps/projectM-iOS/Coordinators/VideoStore.swift` as an inversion source and change them only if they are one (R10; the plan first assumed an async rewrite) — Verified 2026-11-13: the store tests (whole import incl. the coordinated read) show 0 checker inversion warnings with the new probe vs 2 with the old one (`.xcresult` runtime warnings, iOS 27.2 simulator), so the reads are not a source and the stores are unchanged
- [X] MED-014-T19 [US5] Record the before/after checker output (the runtime warnings of each run's `.xcresult`; the checker does not print to the xcodebuild log) in `docs/test-reports/safe-media-decoder.md` and ADR-0022's amendment (S6) — Verified 2026-11-13: report and ADR written from runs: store tests 2 → 0; VideoLayerUITests alone 1 (playback decode thread, recorded), PhotoLayerUITests alone 0, SafeMediaUITests 0

## Phase 8: Polish

- [X] MED-014-T20 ADR: amend ADR-0020 and ADR-0022 with a MED-014 section (or a new ADR at the next free number) in `docs/adr/` — Verified 2026-11-13: amendments appended to ADR-0020 and ADR-0022 and their README rows; no new number used; `validate_docs.py` OK
- [X] MED-014-T21 Test report `docs/test-reports/safe-media-decoder.md`: commands, counts, durations, fixture outcomes; roadmap row MED-014 status in `docs/FEATURE_ROADMAP_AUTONOMOUS.md` if rows carry a status — Verified 2026-11-13: report written; roadmap rows carry no implementation status (MED-001/002/009 rows still read "Gap candidate"), so the roadmap is unchanged; `validate_docs.py` OK
- [X] MED-014-T22 Runs: `swift test --package-path Packages/Compositor`, Linux shape, `xcodebuild test -scheme Compositor` on the simulator, app unit tests + SafeMediaUITests + PhotoLayerUITests + VideoLayerUITests; `check_compliance.py`, `validate_docs.py`, `test_scripts.py`; PosterBoard reports counted — Verified 2026-11-13: host Compositor package all pass (CompositorTests 179, MediaSniffingTests 20; 9.4 s), Linux shape all pass (CompositorTests 100, MediaSniffingTests 20), `xcodebuild test -scheme Compositor` on iOS 27.2 all pass, app 223/223 unit + SafeMedia/Photo/Video UI tests pass; `check_compliance.py` OK, `validate_docs.py` OK, `test_scripts.py` 111 OK (1 skipped); PosterBoard reports 32 → 32
- [ ] MED-014-T23 {device} Import a real HEIC, a ProRAW DNG, a panorama and an HDR video on D1 and D3: each imports and renders as before (no false refusal); quickstart step 5

## Dependencies

T01 → T02-T04 → US1 (T05-T08) and US2 (T09-T12) in either order → US3 (T13-T14) → US4 (T15-T17) → US5 (T18-T19) → Polish. US5 is independent of US1-US4 apart from the shared test run.

## Parallel examples

- T02 and T03 (different files); T07 and T11 once their sniffers exist; T13 alongside T15.

## Implementation strategy

MVP = US1 (the truncated-PNG gap). Then US2, the fuzz, the acceptance (US4), then the QoS fix.
