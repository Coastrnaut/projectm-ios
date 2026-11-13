# Tasks: MED-014 Safe Media Decoder

**Input**: Design documents from `specs/056-med-014-safe-media-decoder/` (spec, plan, research,
data-model, contracts/safe-decoder.md, quickstart)

**Tests**: requested by the spec (S1-S6, R14) and owner rule 7 budgets (unit ≈ 1-2 s, suite < 1 min, UI
test < 30 s). Tick a task `[X]` only when verified, with " — Verified <date>: <how>".

Format: `- [ ] MED-014-Tnn [P?] [Story?] Description with file path`

## Phase 1: Setup

- [ ] MED-014-T01 Add target `MediaSniffing` (no dependencies) to the library product, make `ImageLayer` and `VideoLayer` depend on it, add test target `MediaSniffingTests` (dependency `MediaSniffing`) and add `MediaSniffing` to `CompositorTests`' dependencies, with a header comment line for MED-014, in `Packages/Compositor/Package.swift`

## Phase 2: Foundational (plain Swift, every host; blocks all stories)

- [ ] MED-014-T02 [P] `MediaSniffError` (`empty unrecognized truncated corrupt unreadable`), `ByteSource`, `DataByteSource`, `FileByteSource` (FileHandle, `seek` + `read(upToCount:)`, reads clamped to the file length) in `Packages/Compositor/Sources/MediaSniffing/ByteSource.swift` (R13)
- [ ] MED-014-T03 [P] CRC-32 (PNG polynomial, table) in `Packages/Compositor/Sources/MediaSniffing/CRC32.swift`
- [ ] MED-014-T04 Fixture builders in `Packages/Compositor/Tests/MediaSniffingTests/MediaFixtures.swift`: PNG from chunks with computed CRCs and a stored (uncompressed) zlib stream; minimal ISO boxes (`ftyp`, `moov/trak/mdia/hdlr/minf/stbl/stsd`); SplitMix64 (research D6, D7)

## Phase 3: User Story 1 — A damaged or hostile image is refused (P1, MVP)

**Goal**: PNG/JPEG/HEIF structure and header size checked before ImageIO. **Independent test**: the image rows of the fixture table.

- [ ] MED-014-T05 [US1] `ImageHeaderSniffer.sniff(_:)` and `ImageHeaderFacts`/`ImageContainer` in `Packages/Compositor/Sources/MediaSniffing/ImageHeaderSniffer.swift`: PNG, JPEG, HEIF rules exactly as research D2 (R1-R4); `.other` for anything else; `.empty` for no bytes
- [ ] MED-014-T06 [US1] `ImageIODecoder` in `Packages/Compositor/Sources/ImageLayer/ImageDecoding.swift`: sniff after the size check (`.empty` → `.notAnImage`, `.truncated`/`.corrupt`/`.unreadable` → `.damaged`), header pixel count > `maxPixelCount` → `.tooManyPixels` before ImageIO (R5, R6, R11); header comment updated
- [ ] MED-014-T07 [P] [US1] Image sniffer tests in `Packages/Compositor/Tests/MediaSniffingTests/ImageHeaderSnifferTests.swift`: F1-F4, F8-F11 and a valid HEIF header with two `ispe` (largest wins), PNG with junk after IEND, JPEG with bytes after EOI, APNG-style ancillary chunk (Linux shape)
- [ ] MED-014-T08 [US1] Decoder table in `Packages/Compositor/Tests/CompositorTests/SafeDecoderTests.swift`: F1-F9 through `ImageSanitizer.sanitize` with exact `ImageImportError`s (F5-F7 encoded by ImageIO), and MED-001's `testDamagedImagesAreRefused` comment updated to cite MED-014 with a truncated-PNG assertion in `Packages/Compositor/Tests/CompositorTests/ImageImportTests.swift` (S1)

## Phase 4: User Story 2 — A damaged or hostile video is refused (P1)

**Goal**: container checked before AVFoundation; non-blocking first-picture check. **Independent test**: the movie rows of the fixture table.

- [ ] MED-014-T09 [US2] `MovieContainerSniffer.sniff(_:limits:)`, `MovieContainerFacts`, `MovieSniffLimits` (`maxBoxes` 4,096, `maxDepth` 8, `maxTracks` 64, `maxEntryBytes` 4,096) in `Packages/Compositor/Sources/MediaSniffing/MovieContainerSniffer.swift` (R7, R8)
- [ ] MED-014-T10 [US2] `VideoProbe.check` in `Packages/Compositor/Sources/VideoLayer/AVVideoProbe.swift`: sniff with `FileByteSource` after the size check (mapping per contract), then AVFoundation; first picture with `AVAssetImageGenerator.image(at: .zero)`, `maximumSize` 256 × 256, tolerances `.positiveInfinity`, `appliesPreferredTrackTransform` false (R8, R9); `AVVideoFrameReader.open` sniffs before each open in `Packages/Compositor/Sources/VideoLayer/AVVideoFrameReader.swift` (R12)
- [ ] MED-014-T11 [P] [US2] Movie sniffer tests in `Packages/Compositor/Tests/MediaSniffingTests/MovieContainerSnifferTests.swift`: F12, F13, F15, F16, 64-bit size, size 0 last box, `moov` after `mdat`, two `moov`, depth > 8, box count > 4,096, `FileByteSource` on a temporary file (Linux shape)
- [ ] MED-014-T12 [US2] Movie rows in `Packages/Compositor/Tests/CompositorTests/SafeDecoderTests.swift`: F12-F16 through `VideoProbe.check` with exact `VideoImportError`s; F14 sniffed facts `avc1` 64 × 48 (S1)

## Phase 5: User Story 3 — Typed result for every malformed file (P1)

- [ ] MED-014-T13 [P] [US3] Fuzz in `Packages/Compositor/Tests/MediaSniffingTests/SnifferFuzzTests.swift`: seed fixed, ≥ 2,000 mutations (bit flip, overwrite, truncate, duplicate range, insert, length field 0xFFFFFFFF) over the PNG, HEIF-header and movie-header fixtures; every result facts or `MediaSniffError` (S2)
- [ ] MED-014-T14 [US3] Decoder fuzz in `Packages/Compositor/Tests/CompositorTests/SafeDecoderTests.swift`: ≈ 300 mutations of F1 and F5 through `ImageIODecoder`; every result a picture or an `ImageImportError` (S2)

## Phase 6: User Story 4 — A stored file that breaks later does not stop the show (P1)

**Goal**: the row's acceptance. **Independent test**: running compositor with broken layers.

- [ ] MED-014-T15 [US4] Isolation acceptance in `Packages/Compositor/Tests/CompositorTests/SafeDecoderTests.swift`: `Compositor` with `ImageLayerSource` (index 0), `VideoLayerSource` (1) and a half-coverage `SolidLayer` (2) at 64 × 64; both media start valid and render; the stored files are overwritten with F2 and F12 and the contents reset to them; for 30 frames `composite` returns true each frame, layers 0 and 1 report `.failed(.damaged)` and `.fallback`, the output equals the solid layer alone (S3, R12)
- [ ] MED-014-T16 [US4] App DEBUG seeds in `Apps/projectM-iOS/Debug/UITestPhotoFixture.swift` (`corrupt`: a valid PNG cut before IEND) and `Apps/projectM-iOS/Debug/UITestVideoFixture.swift` (`corrupt`: `ftyp` + a `moov` claiming 1 MB in a 64-byte file) (R14)
- [ ] MED-014-T17 [US4] UI test `Apps/projectM-iOS/UITests/SafeMediaUITests.swift`: launch with both corrupt seeds; the photo and video notices appear (visualizer) within 10 s; Settings opens and closes; the Photo row shows no stored photo (S4)

## Phase 7: User Story 5 — No priority inversion from the import (P2)

- [ ] MED-014-T18 [US5] Asynchronous coordinated reads in `Apps/projectM-iOS/Coordinators/PhotoStore.swift` (`importImage` async; `NSFileCoordinator.coordinate(with:queue:byAccessor:)`) and `Apps/projectM-iOS/Coordinators/VideoStore.swift`; callers in `PhotoCoordinator.swift` and the app tests updated (R10)
- [ ] MED-014-T19 [US5] Record the before/after checker output (grep "priority inversion" in the app test logs) in `docs/test-reports/safe-media-decoder.md` (S6)

## Phase 8: Polish

- [ ] MED-014-T20 ADR: amend ADR-0020 and ADR-0022 with a MED-014 section (or a new ADR at the next free number) in `docs/adr/`
- [ ] MED-014-T21 Test report `docs/test-reports/safe-media-decoder.md`: commands, counts, durations, fixture outcomes; roadmap row MED-014 status in `docs/FEATURE_ROADMAP_AUTONOMOUS.md` if rows carry a status
- [ ] MED-014-T22 Runs: `swift test --package-path Packages/Compositor`, Linux shape, `xcodebuild test -scheme Compositor` on the simulator, app unit tests + SafeMediaUITests + PhotoLayerUITests + VideoLayerUITests; `check_compliance.py`, `validate_docs.py`, `test_scripts.py`; PosterBoard reports counted
- [ ] MED-014-T23 {device} Import a real HEIC, a ProRAW DNG, a panorama and an HDR video on D1 and D3: each imports and renders as before (no false refusal); quickstart step 5

## Dependencies

T01 → T02-T04 → US1 (T05-T08) and US2 (T09-T12) in either order → US3 (T13-T14) → US4 (T15-T17) → US5 (T18-T19) → Polish. US5 is independent of US1-US4 apart from the shared test run.

## Parallel examples

- T02 and T03 (different files); T07 and T11 once their sniffers exist; T13 alongside T15.

## Implementation strategy

MVP = US1 (the truncated-PNG gap). Then US2, the fuzz, the acceptance (US4), then the QoS fix.
