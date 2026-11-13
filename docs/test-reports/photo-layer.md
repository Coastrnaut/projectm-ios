# MED-001 Import Photo Layer — test report

Spec: `specs/044-med-001-import-photo-layer` (ADR-0020). Mac Studio, Xcode 27.2, 2026-11-13, worktree
`feature/med-001`. Simulator results are never device evidence (Constitution X).

## Package (`Packages/Compositor`)

| Run | Result | Time |
|---|---|---|
| Baseline before the change (`fff486c`) | CompositorTests 79/79, ProceduralMaterialsTests 31/31 | 14.7 s wall (build included) |
| `swift test --package-path Packages/Compositor` (host, Metal) | CompositorTests 102/102 (79 + 23 new), ProceduralMaterialsTests 31/31 | 4.7 s wall; new suites 0.17 s |
| Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`) | CompositorTests 53/53, ProceduralMaterialsTests 19/19 | 9.3 s wall (build included) |

New suites: ImageGeometryTests 6 (CPU, every host), ImageImportTests 10 (ImageIO; skipped on real
Linux), ImageLayerTests 7 (Metal, 64 × 64).

Findings recorded in research MED-001-D4: ImageIO decodes a PNG cut short without error (status
"complete"), so that case is MED-014's; ImageIO's JPEG writer always adds three technical EXIF fields
of the copy (pixel width, height, color space), which the strip test allows while checking that no
original value is anywhere in the stored bytes.

## App (simulator "MED iPhone 17", iOS 27.2)

`xcodebuild test … -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/PhotoLayerUITests
-only-testing:projectM-iOSUITests/CameraUITests -only-testing:projectM-iOSUITests/SettingsUITests`
(`-test-timeouts-enabled YES -default-test-execution-time-allowance 180`, `CODE_SIGNING_ALLOWED=NO`):

| Suite | Result | Time |
|---|---|---|
| projectM-iOSTests | 192/193; the one failure is the known worktree case `PresetTests.testBundledIncludedScopeMatchesRelease1_0` (preset submodules empty) | 5.3 s |
| PhotoStoreTests (new) | 7/7 | 0.08 s |
| PhotoLayerUITests (new) | 1/1: seed → "Photo 64 × 48" with frames → terminate → relaunch without seed → "Photo 64 × 48" with frames → Remove Photo → "No photo" | 24.9 s |
| CameraUITests | 2/2 | 25.2 s |
| SettingsUITests | 4/4 | 65.2 s |

PosterBoard crash reports: 32 before the simulator runs, 32 after (none new).

## Checks

- `python3 scripts/check_compliance.py`: OK. `python3 scripts/validate_docs.py`: OK.
- `python3 scripts/check_privacy_manifest.py` on the Debug simulator app: OK (no new required-reason
  API); Release build to be checked before the next upload.
- The built app's Info.plist has no `NSPhotoLibraryUsageDescription` (`plutil -p … | grep -c` → 0).
- The seed flag and fixture code are inside `#if DEBUG` (`Debug/UITestPhotoFixture.swift`,
  `PhotoCoordinator.importNow`, the call in `AppCoordinator.init`).

## Open (device, owner)

MED-001-T22 to T24: the real Photos picker with full and limited access, Files and iCloud Drive,
HEIC with location, a large panorama and a file over 40 MB on D1 and D3.
