# Implementation Plan: MED-014 Safe Media Decoder

**Branch**: `feature/med-014` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/056-med-014-safe-media-decoder/spec.md`

## Summary

A new plain-Swift target `MediaSniffing` in `Packages/Compositor` checks the structure of untrusted
media bytes before any system decoder sees them: PNG (signature, IHDR fields, every chunk length
against the remaining bytes, CRC-32 of critical chunks, IDAT and IEND present), JPEG (SOI, segment
lengths, SOF size and components before the first scan, entropy-coded data scanned to EOI), HEIF/AVIF
(`ftyp` image brand, top-level boxes fit, `meta` present, largest `ispe`), and ISO base media / QuickTime
movies (bounded box walk: every size against its parent, 64-bit and to-end sizes, at most 4,096 box
headers and 8 levels, exactly one `moov`, tracks by `hdlr`, the first video sample description's codec
and coded size; sample tables never read). Movies are read through a random-access `ByteSource`
(a `FileHandle` reads only box headers and two small boxes, so a 500 MB file is never loaded).

`ImageIODecoder` runs the image sniffer first (`.damaged` on structure, `.tooManyPixels` from the header
size), then its existing ImageIO steps (type, status, properties, bounded thumbnail decode at ≤ 4096 px).
`VideoProbe.check` and `AVVideoFrameReader.open` run the container sniffer first (`.notAVideo`,
`.damaged`, `.pictureTooLarge`), then AVFoundation. The probe's first-picture check moves from a
blocking `AVAssetReader.copyNextSampleBuffer` to `AVAssetImageGenerator.image(at:)` (async, max 256 px).
The coordinated picked-file reads were investigated as the other suspect and do not trigger the
checker (research D4), so they are unchanged.

Failure isolation is already structural (CMP-001-R3: a layer that throws shows its fallback); this
row proves it with a running compositor holding a photo layer, a video layer and a solid layer whose
media files are replaced by corrupt fixtures, and in the app with a DEBUG `corrupt` seed.

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the Mac, Xcode 26 in CI: explicit closure types)

**Primary Dependencies**: Foundation only for `MediaSniffing`; ImageIO (decoder), AVFoundation
(`AVAssetImageGenerator`, `AVURLAsset`), Metal (layers, tests)

**Storage**: none new (MED-001/002 stored copies unchanged)

**Testing**: XCTest: `MediaSniffingTests` (Linux-shape; fixture bytes built in code), `CompositorTests`
(decoder table, fuzz over the ImageIO decoder, isolation acceptance on Metal), app unit tests
(`PhotoStoreTests`, `VideoStoreTests`), one XCUITest (`SafeMediaUITests`)

**Target Platform**: iOS 26+ (app), macOS 15 host and Linux for the package's plain-Swift targets

**Project Type**: mobile app + Swift packages

**Performance Goals**: sniffing a 40 MB PNG is one linear CRC pass (≈ 0.1 s on a phone, off the main
thread at import/load); a movie sniff reads at most 4,096 × 16 header bytes plus two small boxes

**Constraints**: no wall-clock decisions; allocations bounded by the input size or a constant, never
by a length field; public APIs only; no networking; no new user-visible strings

**Scale/Scope**: one target (≈ 4 source files), changes to 4 existing sources, 3 test files, 1 UI test

## Constitution Check

| Principle | Check |
|---|---|
| I Public Apple APIs | ImageIO, AVFoundation (`AVAssetImageGenerator`), Foundation `NSFileCoordinator`; no private API. PASS |
| VI Modular boundaries | `MediaSniffing` depends on nothing; `ImageLayer` and `VideoLayer` depend on it; no app or engine import. PASS |
| VII Real-time safety | Nothing on the render path changes; sniffing runs on the import task, the image load queue and the video decode thread. PASS |
| X Evidence | Simulator/host tests only; real HEIC/ProRAW/panorama/HDR on D1/D3 is a `{device}` task left open. PASS |
| Security (untrusted files) | The point of the row: structure checked before decode, bounded work, typed errors. PASS |
| Privacy | No new stored data, no logging of user content. PASS |

Post-design re-check: PASS (no new dependency, string or stored data).

## Project Structure

### Documentation (this feature)

```text
specs/056-med-014-safe-media-decoder/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/safe-decoder.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/
├── Package.swift                                   # + target MediaSniffing, test target MediaSniffingTests
├── Sources/MediaSniffing/
│   ├── ByteSource.swift                            # random-access bytes (Data, FileHandle), bounded reads
│   ├── ImageHeaderSniffer.swift                    # PNG, JPEG, HEIF structure → ImageHeaderFacts
│   ├── MovieContainerSniffer.swift                 # ISO BMFF / QuickTime box walk → MovieContainerFacts
│   ├── CRC32.swift                                 # PNG CRC-32 (table)
│   └── MediaFixtureBytes.swift                     # fixture builders shared by tests and DEBUG seeds
├── Sources/VideoLayer/VideoContainerCheck.swift    # sniff → VideoImportError
├── Sources/ImageLayer/ImageDecoding.swift          # sniff first; header pixel check
├── Sources/VideoLayer/AVVideoProbe.swift           # container sniff; async first picture
├── Sources/VideoLayer/AVVideoFrameReader.swift     # container sniff before each open
├── Tests/MediaSniffingTests/                       # fixture builders, table, fuzz (Linux shape)
└── Tests/CompositorTests/SafeDecoderTests.swift    # ImageIO/AVFoundation table + isolation acceptance
Apps/projectM-iOS/
├── Debug/UITestPhotoFixture.swift, UITestVideoFixture.swift   # `corrupt` variants
└── UITests/SafeMediaUITests.swift
```

**Structure Decision**: a separate dependency-free target so both layer targets share one sniffer and
Linux CI tests it without ImageIO/AVFoundation; the layer targets only call it.

## Fixture table (MED-014-S1; exact outcomes)

| # | Fixture (generated) | Sniffer outcome | Import outcome |
|---|---|---|---|
| F1 | valid 8 × 6 PNG | `.png 8 × 6` | decodes |
| F2 | F1 cut after the signature, inside IHDR, inside IDAT, before IEND (4 cut points) | `.truncated` | `.damaged` |
| F3 | F1 with one IDAT byte flipped (CRC mismatch) | `.corrupt` | `.damaged` |
| F4 | PNG with IHDR 100,000 × 100,000 (valid CRCs) | `.png 100000 × 100000` | `.tooManyPixels` |
| F5 | valid JPEG (ImageIO-encoded, 16 × 16) | `.jpeg 16 × 16` | decodes |
| F6 | F5 without EOI | `.truncated` | `.damaged` |
| F7 | F5 with SOF set to 65,535 × 65,535 | `.jpeg 65535 × 65535` | `.tooManyPixels` |
| F8 | zero bytes | `.empty` | `.notAnImage` |
| F9 | PNG signature + 4 KB of seeded random bytes | `.corrupt` or `.truncated` | `.damaged` |
| F10 | HEIF: `ftyp` box whose size runs past the file | `.truncated` | `.damaged` |
| F11 | HEIF: `ftyp` whose brands are not legible (zero bytes) | `.corrupt` | `.damaged` |
| F12 | minimal movie, `moov` size beyond the file | `.truncated` | `.damaged` |
| F13 | minimal movie, one sound track only | facts: no video | `.notAVideo` |
| F14 | valid H.264 movie (AVAssetWriter, 64 × 48) | facts: `avc1` 64 × 48 | imports |
| F15 | text bytes as a movie | `.unrecognized` | `.notAVideo` |
| F16 | minimal movie with video sample entry 8192 × 8 | facts: 8192 × 8 | `.pictureTooLarge` |

## Complexity Tracking

None.
