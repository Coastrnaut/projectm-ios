# Implementation Plan: MED-010 Logo Overlay

**Branch**: `feature/med-010` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/131-med-010-logo-overlay/spec.md`

## Summary

A logo is one more FILE-008 reference in the Photos folder, named by `settings.logo.id`, always a
PNG of at most 1024 px. A new logo layer (`LogoLayerSource`) is added as the top entry of the four
compositor visuals' stacks. Unlike the photo layer it uploads **premultiplied linear** half-float
texels (sRGB → linear, × alpha on the CPU) into a mipmapped `rgba16Float` texture, so filtering and
mip generation never pull the black of transparent texels into soft edges (research MED-010-D2). It
draws a quad at a placement computed by plain-Swift `LogoPlacement` (corner or custom anchor, size
of the shorter side, margin, opacity) and declares itself still (CMP-013).

In `Packages/Compositor` (target `ImageLayer`; plain-Swift parts build on Linux):

- `LogoPlacement.swift` (new): corners, clamping, the pixel rectangle, JSON form (contract C1).
- `PremultipliedLinear.swift` (new): sRGB 8-bit straight → linear premultiplied half floats, and a
  float → half conversion (C2).
- `LogoLayerSource.swift` (new, Metal): load, upload, draw, caching (C3).
- `ImageSanitizer.sanitize(… format:)`: `.png` forces PNG (C4). `ImageLayerKind.swift`: `LayerKind.logo`.

In `Packages/SceneFormat`: asset type `logo` (`SceneAssetKind.logo(storeID:)`) with an optional
`placement` object; validation (store ID, missing picture, never "unused"); repair title "Logo"
(C5). In `Packages/SceneArchive`: archive asset type `logo` (`png` only, one per archive, up to 4
files) (C6). In `Packages/LibraryBackup`: the two keys included and erased with "Photos and videos".

In the app:

- `LogoStore` (new): stage, adopt, make current, remove, placement; `protectedIDs` kept by
  `PhotoStore` and `SlideshowStore` (C7).
- `LogoCoordinator` (new, `@Observable`): imports (Photos, Files), Remove, placement setters,
  notices, announcements, and the live logo layers it attaches to compositors (C8).
- `AppCoordinator`: creates the coordinator, attaches the logo layer in the four prepare functions,
  scene inputs and restores (launch, Reopen, cues), archive import result.
- `SceneAutosaveCapture`, `ShowSceneSnapshot`, `SceneArchiveService`: the logo asset.
- `LogoSection` (new view) after the slideshow in Settings' media sections.
- DEBUG: `-uitestSeedLogo` (`UITestLogoFixture`), `logoProbe` in the visualizer.

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/logo-overlay.md](contracts/logo-overlay.md); checks: [quickstart.md](quickstart.md). No
ADR: no default is overridden; the scene asset type follows SCN-001's unknown-asset rule (older apps
keep it), and the archive's extra file type is additive (archives without a logo are byte-identical).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: Compositor (`ImageLayer`, `MediaSniffing`), SceneFormat, SceneArchive,
LibraryBackup, LocalPortability (`ContentAddressedMediaFolder`), SwiftUI, PhotosUI, ImageIO, Metal.
No new dependency, no networking, no photo library permission.

**Storage**: UserDefaults `settings.logo.id` (UUID string) and `settings.logo.placement` (JSON
Data); the copy in Application Support/Photos as a FILE-008 reference.

**Testing**: Compositor: `LogoPlacementTests`, `PremultipliedLinearTests` (Linux shape),
`LogoLayerTests` (Metal: S2 acceptance, opacity, caching, quarter-size no-fringe), `ImageImportTests`
gains the PNG-forced case. SceneFormat: `SceneLogoTests`. SceneArchive: logo record tests.
LibraryBackup: policy assertions. App: `LogoStoreTests` (S1 import alpha, limits, dedup, protection,
backup and erase keys), `LogoArchiveTests` (S3 export → fresh sandbox import), scene capture/restore.
UI: `LogoOverlayUITests` with `-uitestSeedLogo`.

**Target Platform**: iOS/iPadOS 26.0+, macOS host tests, Linux (CPU parts).

**Performance Goals**: the logo layer renders only on change (CMP-013); upload of a 1024 px logo off
the main thread; GPU copy ≤ about 11 MB with mips.

**Constraints**: public APIs only; explicit closure types; typed steps; no C stdio globals; no
main-actor mutation in setUp/tearDown; no wall-clock assertions; unit tests about 1-2 s, UI test
under 30 s (owner rule 7). Parallel work: FX-009 (compositor output chain), MOD-004, a cleanup agent
on UI-test scroll helpers and `AppCoordinator.init`: `Compositor.swift` is not touched; the
`AppCoordinator.swift` edit is a few lines (property, init, attach calls, inputs, restores).

**Scale/Scope**: 3 new package sources, 1 new SceneFormat source, 4 new app sources (store,
coordinator, section, seed), about 20 files touched, 7 new test files.

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | SwiftUI, PhotosUI `PhotosPicker` (out of process), `fileImporter`, ImageIO, Metal | Pass |
| VI Modular boundaries | Placement and premultiplication plain Swift in `ImageLayer`; the layer knows no app types; scene and archive formats own their types; the app wires stores and hosts | Pass |
| VII Real-time safety | No audio code touched; decode and upload on the layer's background queue | Pass |
| X Evidence | Fixture PNG with a known alpha gradient through the real import, GPU compositor and archive paths; the real picker is `{device}` | Pass |
| Privacy | Pixels-only PNG copy, no photo library permission, nothing sent; backups like MED-001 | Pass |
| Photosensitivity | Static layer inside the composite flash guard and the output blackout | Pass |
| No networking | None; `check_compliance.py` | Pass |
| Accessibility | Labels, ACC-005 sliders, announcer, no animation, accessibility text sizes | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

### Documentation (this feature)

```text
specs/131-med-010-logo-overlay/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/logo-overlay.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/ImageLayer/
├── LogoPlacement.swift, PremultipliedLinear.swift, LogoLayerSource.swift   # new
├── ImageSanitizer.swift (format), ImageLayerKind.swift (.logo)
Packages/Compositor/Tests/CompositorTests/
├── LogoPlacementTests.swift, PremultipliedLinearTests.swift, LogoLayerTests.swift   # new
Packages/SceneFormat/Sources/SceneFormat/SceneLogo.swift   # new; Document, Decoding, Encoding,
                                                            # Validation, Repair edits
Packages/SceneFormat/Tests/SceneFormatTests/SceneLogoTests.swift   # new
Packages/SceneArchive/Sources/SceneArchive/SceneArchiveFormat.swift, SceneStoreRemapping.swift
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, LibraryErasePolicy.swift
Apps/projectM-iOS/
├── Coordinators/LogoStore.swift, LogoCoordinator.swift   # new
├── Coordinators/PhotoStore.swift, SlideshowStore.swift, AppSettings.swift, AppCoordinator.swift
├── Coordinators/SceneAutosaveCapture.swift, ShowSceneSnapshot.swift, AppCoordinator+Show.swift,
│   SceneArchiveService.swift
├── Views/LogoSection.swift (new), SettingsView.swift, VisualizerView.swift
├── Debug/UITestLogoFixture.swift   # new
├── Tests/LogoStoreTests.swift, LogoArchiveTests.swift   # new
└── UITests/LogoOverlayUITests.swift   # new
scripts/run_device_tests.py (ALLOWED_KEYS)
```

**Structure Decision**: existing package targets and app folders; no new target or package.

## Complexity Tracking

| Item | Why | Simpler alternative rejected because |
|---|---|---|
| A second image layer type instead of reusing `ImageLayerSource` | The photo layer filters straight alpha (dark fringes on soft edges, research D2) and fills the picture | Changing the photo layer's upload would alter MED-001's goldens and slideshow behaviour outside this row |
| Logo layer added to the stack after host creation (app extension) instead of in each host's `make` | One attach call per prepare function; hosts unchanged | Editing four host files and their stacks multiplies merge risk with parallel work |
