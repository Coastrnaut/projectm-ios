# Implementation Plan: FILE-001 Portable Scene Archive

**Branch**: `feature/file-001` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/062-file-001-portable-scene-archive/spec.md`

## Summary

A new plain-Swift package `Packages/SceneArchive` defines the scene archive (format
`projectm-ios.scene-archive`, version 1) on top of PRE-014's `PortableArchive` (stored ZIP,
`manifest.json` with every file's length and SHA-256) and SCN-001's `SceneDocument`: a writer that
packs a document and its photo/video bytes, a reader that refuses every hostile case with one typed
`SceneArchiveError`, first-bytes checks (SHD-011 executable/archive signatures, MED-014 container
sniffers) and the store-ID remapping. The PRE-014 ZIP reader is tightened to refuse symbolic-link
and other non-regular entries, and SHD-011's `ExecutableSignature` becomes public so importers
share one list. In the app, `PhotoStore` and `VideoStore` split their import into
stage → adopt → make current, and a new `SceneArchiveService` exports from the stores to a
temporary `.pmscene` file and imports into a staging folder, commits all media at once, and returns
a remapped, validated scene. No screen changes (research FILE-001-D7).

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the Mac, Xcode 26 in CI: explicit closure types)

**Primary Dependencies**: LocalPortability (PRE-014), SceneFormat (SCN-001), Compositor (MediaSniffing,
GeneratorGraphImport); the app's ImageLayer/VideoLayer sanitizers through `PhotoStore`/`VideoStore`

**Storage**: Application Support `Photos`/`Videos` (existing stores); temporary directory for the
export file and import staging

**Testing**: XCTest: `swift test` for SceneArchive and LocalPortability on the Mac host and the Linux
shape; app unit tests (`projectM-iOSTests`) on the iOS 27.2 simulator for stores and service

**Target Platform**: iOS 26+ app; package also macOS 15 and Linux

**Project Type**: Swift package + iOS app service

**Performance Goals**: a fixture archive (a few KB of media) packs and reads in milliseconds; each
app test ≤ 10 s

**Constraints**: archive ≤ 600 MB checked before reading; ≤ 3 files besides the manifest; manifest
≤ 64 KiB; scene ≤ 1 MiB; photo ≤ 40 MB; video ≤ 500 MB; no networking; nothing executed

**Scale/Scope**: one scene, at most one photo and one video per archive

## Constitution Check

| Principle / rule | Status |
|---|---|
| I. Public Apple APIs only | Pass: Foundation, ImageIO/AVFoundation through existing sanitizers; no private API, no dlopen. |
| VI. Modular boundaries | Pass: format logic in a package with no app dependency; the app adapts its stores. |
| VII. Real-time audio safety | Not touched. |
| IX. Pinned dependencies | Pass: no third-party code; ZIP code is the app's own (PRE-014). |
| X. Evidence-based quality | Pass: package tests on host and Linux shape; simulator app tests for decoding; cross-device transfer is a `{device}` task left open. |
| Security: imported files untrusted | Pass: size before read, bounded reader, first-bytes checks, re-sanitized media, all-or-nothing commit. |
| Privacy: no network, local only | Pass: archives leave the device only by the user's action; privacy policy updated. |
| Signing | Not touched. |

Post-design re-check: unchanged (Pass).

## Project Structure

### Documentation (this feature)

```text
specs/062-file-001-portable-scene-archive/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/scene-archive.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Packages/SceneArchive/                     # new package (FILE-001)
├── Package.swift
├── Sources/SceneArchive/
│   ├── SceneArchiveFormat.swift           # names, limits, extension and type identifier
│   ├── SceneArchiveManifest.swift         # manifest model (asset records)
│   ├── SceneArchiveError.swift            # typed refusals and messages
│   ├── SceneArchiveContentCheck.swift     # SHD-011 signatures + MED-014 sniffers per asset type
│   ├── SceneArchiveWriter.swift           # document + media → archive bytes
│   ├── SceneArchiveReader.swift           # archive bytes → document + media, every check
│   └── SceneStoreRemapping.swift          # replace photo/video store IDs
└── Tests/SceneArchiveTests/               # round trip, hostile table, remapping, source safety
Packages/LocalPortability/Sources/LocalPortability/StoredZip.swift      # refuse non-regular entries
Packages/Compositor/Sources/GeneratorGraphImport/ExecutableSignature.swift  # public
Apps/projectM-iOS/Coordinators/PhotoStore.swift, VideoStore.swift       # stage / adopt / makeCurrent
Apps/projectM-iOS/Coordinators/SceneArchiveService.swift                # export and import
Apps/projectM-iOS/Tests/SceneArchiveServiceTests.swift                  # clean-install round trip, atomicity
project.yml, .github/workflows/ios-ci.yml                               # package wiring
```

**Structure Decision**: one new package (format, Linux-tested) plus one app service (stores,
decoding). ADR: next free number at commit time records the format and the staging commit.

## Complexity Tracking

None.
