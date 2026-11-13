# Test report: MED-014 Safe media decoder

Feature: `specs/056-med-014-safe-media-decoder` (branch `feature/med-014`), ADR-0020 and ADR-0022
amendments. Roadmap acceptance: "Corrupt fixture fails gracefully and leaves compositor running."
All runs on the Mac Studio, 2026-11-13. Simulator results are never device evidence (Constitution X).

## What was built

- Target `MediaSniffing` (plain Swift, no dependencies): `ImageHeaderSniffer` (PNG, JPEG, HEIF/AVIF),
  `MovieContainerSniffer` (ISO/QuickTime boxes; ≤ 4,096 boxes, depth 8, 64 tracks), `ByteSource`
  (`DataByteSource`, `FileByteSource`, clamped reads), CRC-32, `MediaFixtureBytes` (fixture builders
  shared by the tests and the app's DEBUG seeds).
- `ImageIODecoder` runs `ImageStructureCheck` after the size limit; `VideoProbe.check` and every
  `AVVideoFrameReader.open` run `VideoContainerCheck`; the probe's first picture comes from
  `AVAssetImageGenerator.image(at:)` (async, ≤ 256 px) instead of a blocking `AVAssetReader` read.
- DEBUG seeds `-uitestSeedPhoto corrupt` / `-uitestSeedVideo corrupt` damage the stored copies after a
  valid import; `SafeMediaUITests` checks the app.

## Fixture table (MED-014-S1): every row gives exactly its outcome

| # | Fixture | Sniffer | Import |
|---|---|---|---|
| F1 | valid 8 × 6 PNG | png 8 × 6 | decodes |
| F2 | F1 cut after the signature, in IHDR, in IDAT, before IEND (and every later cut point) | truncated | `.damaged` |
| F3 | F1, one IDAT byte flipped | corrupt (CRC) | `.damaged` |
| F4 | PNG, IHDR 100,000 × 100,000 | png 100000 × 100000 | `.tooManyPixels` |
| F5 | valid 16 × 16 JPEG (ImageIO) | jpeg 16 × 16 | decodes |
| F6 | F5 without EOI | truncated | `.damaged` |
| F7 | F5 with SOF 65,535 × 65,535 | jpeg 65535 × 65535 | `.tooManyPixels` |
| F8 | zero bytes | empty | `.notAnImage` |
| F9 | PNG signature + 4 KB random | corrupt/truncated | `.damaged` |
| F10 | HEIF, `ftyp` size past the end | truncated | `.damaged` |
| F11 | HEIF, illegible `ftyp` brands | corrupt | `.damaged` |
| F12 | movie, `moov` size 1 MB past the end | truncated | `.damaged` |
| F13 | movie, sound track only | no video track | `.notAVideo` |
| F14 | valid H.264 movie (AVAssetWriter, 64 × 48) | avc1 64 × 48 | imports |
| F15 | text as a movie | unrecognized | `.notAVideo` |
| F16 | movie, sample entry 8192 × 8 | coded 8192 × 8 | `.pictureTooLarge` |

Behaviour changes against MED-001/002: a PNG cut short is now refused (ImageIO alone accepted it as
"complete"); a movie cut short is `.damaged` (MED-002 reported `.notAVideo`; its test was updated).

## Isolation (MED-014-S3, the acceptance)

`SafeDecoderIsolationTests.testCorruptStoredMediaFailGracefullyAndTheCompositorKeepsRunning`
(Metal compositor, 64 × 64): solid layer at the bottom, photo and video above it, both valid and
rendering at first. The photo's stored file is cut to 60 bytes and reloaded → `.failed(.damaged)`;
the playing video's file is atomically replaced by F12 and playback advanced past its 2 s loop → the
reader's reopen fails → `.failed(.damaged)` with no content change. All 18 frames were produced, the
broken layers report `.fallbackTransparent(.notReady)`, the solid layer `.rendered`, and the output
equals the solid color within 1/255. 0.25 s.

In the app (`SafeMediaUITests`, 15.9 s): choosing Photo shows "The photo couldn't be loaded." and no
photo frame is drawn; choosing Video shows "The video couldn't be played."; Settings opens and closes
afterwards and the audio source never restarted.

## Priority inversion (MED-014-R10, S6; MED-002's finding)

The Thread Performance Checker reports to the `.xcresult` runtime warnings, not the xcodebuild log.

| Run (iOS 27.2 simulator) | Inversion warnings |
|---|---|
| PhotoStoreTests + VideoStoreTests, old probe (`AVAssetReader.copyNextSampleBuffer`) | 2 (one in `VideoStoreTests.swift`) |
| same, new probe (`AVAssetImageGenerator.image(at:)`) | 0 |
| PhotoLayerUITests alone | 0 |
| SafeMediaUITests alone (seed writer, import, failing reader open) | 0 |
| VideoLayerUITests alone (playback) | 1 |

Cause: the user-initiated import thread blocked in the probe's synchronous sample read while
AVFoundation decoded at utility QoS. Fixed by the async first-picture check. The coordinated
picked-file reads are part of the store tests' imports and produced no warning, so they are unchanged.
The remaining warning is the playback decode thread (MED-002 decision 1: a user-initiated pull thread
calling the blocking `copyNextSampleBuffer`). It is kept by design and recorded in ADR-0022; whether a
lower decode-thread QoS keeps frame pacing is a device question, not changed blind. Every UI run also
shows the existing "UI unresponsiveness" notice about an audio-session call on the main thread
(predates this row).

## Commands and results

| Command | Result |
|---|---|
| `swift test --package-path Packages/Compositor` | MediaSniffingTests 20/20 (0.03 s), CompositorTests 179/179 (3.7 s; SafeDecoderTests 3, SafeDecoderIsolationTests 1), TextLayer 26, ProceduralMaterials 31, GeneratorGraph 46 (1 skipped), GeneratorGraphImport 14; whole run 9.4 s |
| same with `--scratch-path .build/linuxshape -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE` | MediaSniffingTests 20/20, CompositorTests 100/100, TextLayer 22, ProceduralMaterials 19, GeneratorGraph 32, GeneratorGraphImport 14 |
| `xcodebuild test -scheme Compositor` on "MED14 iPhone 17" (iOS 27.2) | MediaSniffingTests 20, CompositorTests 179, TextLayer 26, ProceduralMaterials 31, GeneratorGraph 46 (1 skipped), GeneratorGraphImport 14; all pass (53 s with build) |
| `xcodebuild test -scheme projectM-iOS -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/{SafeMediaUITests,PhotoLayerUITests,VideoLayerUITests}` | 223/223 unit tests; UI: SafeMedia 15.9 s, Photo 22.3 s, Video 21.7 s; all pass (1 min 54 s with build) |
| Fuzz | 2,700 sniffer mutations (0.02 s) and 300 ImageIO-decoder mutations (0.01 s), fixed seeds, every result typed |
| PosterBoard reports | 32 before, 32 after (none new) |

The fuzz runs on the real Linux runner in CI (no ImageIO there: the decoder fuzz and fixture table
compile out, the sniffer tests run). Not run on a real Linux host here (the Linux shape on the Mac).

## Device (owner; open)

MED-014-T23 `{device}`: import a real HEIC, a ProRAW DNG, a panorama and an HDR video on D1 and D3;
each must import and render as before (no false refusal by the new structure checks). Not run.
