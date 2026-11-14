# Implementation Plan: SCN-014 Scene Dependency Pack

**Branch**: `feature/scn-014` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

The pack is FILE-001's `.pmscene` archive. `Packages/SceneArchive` gains (1) optional `slides` records so a
photo asset's MED-006 slideshow pictures travel with the scene, and (2) a path audit the writer runs on
`manifest.json` and `scene.json` before anything is written. The app's `SceneArchiveService` packs and
unpacks slides, and gains a library import (`ScenePackImporter`): preview (FILE-003 dry run plus FILE-004
plan against the show), then stage → adopt with identifiers derived from the pack's media bytes → FILE-004
install with Keep both → one cue. Nothing becomes current and nothing is applied. `ScenePackCoordinator`
drives Scene Folders' new "Export Scene…" (context menu, swipe, VoiceOver action; system share sheet) and
"Import Scene…" (file picker for the exported type `org.projectmios.scene-archive`, preview sheet).

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 host; CI also Xcode 26)
**Primary Dependencies**: SceneArchive, LocalPortability (PortableArchive, ArchivePath, ContentAddressedMediaFolder), SceneFormat, ShowControl/ShowStorage (FILE-004 install); app SceneArchiveService, PhotoStore, VideoStore, LogoStore, ShowCoordinator, SceneFoldersView
**Storage**: the pack is a temporary file (`tmp/SceneArchiveExport`); imports write into `Application Support/Photos`, `Videos` and `Show`
**Testing**: XCTest: SceneArchive package (host; Linux-compatible); app unit tests (acceptance) on simulator "SCN14 iPhone 17" (iOS 27.2); one UI test under 30 s
**Target Platform**: iOS 26+
**Constraints**: no networking; no new UserDefaults keys; scene format unchanged; pack format version unchanged (optional field); owner rule 7 budgets; Xcode 26 type-check budget; Linux build of SceneArchive

## Constitution Check

- I (public APIs only): `fileImporter`, `UIActivityViewController`, `UTType(exportedAs:)`, Foundation file APIs. Pass.
- Privacy and local-first (Platform, Security & Privacy): no network API; packs carry only media copied into the app (no Photos/Music library references, no metadata: MED-001 copies are pixels-only); the picked URL is read once under its security scope. Pass.
- VI (modular boundaries): format and audit in the SceneArchive package; files and stores in the app service; UI in views. Pass.
- IX (licence review): no third-party content is added; packs carry the user's own media, and the preview's licence list is empty by design. Pass.
- X (evidence): acceptance proven by host and simulator tests; no device claim.

Post-design re-check: unchanged, pass.

## Project Structure

```text
Packages/SceneArchive/Sources/SceneArchive/SceneArchiveSlides.swift        # new: slide records, paths, scene slide IDs, remap
Packages/SceneArchive/Sources/SceneArchive/SceneArchivePathAudit.swift     # new: absolute-path audit
Packages/SceneArchive/Sources/SceneArchive/SceneArchiveWriter.swift        # slides, audit
Packages/SceneArchive/Sources/SceneArchive/SceneArchiveReader.swift        # slides
Packages/SceneArchive/Sources/SceneArchive/SceneArchiveManifest.swift      # optional `slides`
Packages/SceneArchive/Sources/SceneArchive/SceneArchiveFormat.swift        # file limit 24
Packages/SceneArchive/Sources/SceneArchive/SceneArchiveError.swift         # absolutePath, slide errors
Packages/SceneArchive/Tests/SceneArchiveTests/SceneArchiveSlideTests.swift # new
Apps/projectM-iOS/Coordinators/SceneArchiveService.swift                  # slides in export and FILE-001 import; helpers internal
Apps/projectM-iOS/Coordinators/ScenePackImporter.swift                    # new: preview + library import
Apps/projectM-iOS/Coordinators/ScenePackCoordinator.swift                 # new: UI state, export/import actions
Apps/projectM-iOS/Coordinators/ShowCoordinator.swift                      # installImportedScene, scenePacks hook
Apps/projectM-iOS/Coordinators/PhotoStore.swift, VideoStore.swift, LogoStore.swift   # stage(id:)
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                       # create and wire ScenePackCoordinator (small)
Apps/projectM-iOS/Views/SceneFoldersView.swift                            # Export/Import entry points
Apps/projectM-iOS/Views/ScenePackViews.swift                              # new: preview sheet, share sheet, import row
Apps/projectM-iOS/Debug/UITestScenePackFixture.swift                      # new: DEBUG seed and picked-file stand-in
Apps/projectM-iOS/Tests/ScenePackAcceptanceTests.swift                    # new
Apps/projectM-iOS/UITests/ScenePackUITests.swift                          # new
project.yml                                                               # UTExportedTypeDeclarations for .pmscene
```

## Complexity Tracking

None.
