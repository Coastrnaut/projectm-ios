# MED-010 Logo overlay — test report (2026-11-14)

Spec: `specs/131-med-010-logo-overlay/`. Branch `feature/med-010`. Host: the Mac Studio (Xcode 27.2,
iOS 27.2 simulator "MED10 iPhone 17", created for this run and deleted afterwards). Simulator results
are never device evidence (Constitution X).

## Audit (baseline `3c373722`)

- **Import**: MED-014's `ImageIODecoder` draws into 8-bit premultiplied sRGB and un-premultiplies, so alpha
  bytes are carried exactly. MED-001's `ImageSanitizer` writes PNG (straight alpha) when any pixel is not
  opaque and **JPEG 0.9 otherwise**: alpha survived, but an opaque logo would have become lossy.
- **Upload**: `ImageLayerSource` uploads straight-alpha texels into `rgba8Unorm_srgb`, builds mipmaps from
  them and premultiplies after sampling. Filtering straight alpha mixes the black of transparent texels into
  soft edges. Measured with this feature's fixture drawn at a quarter size by the photo layer (throwaway
  probe, not committed): the red channel came out **0.126 below both the logo's and the backdrop's colour**
  (a dark fringe). Left unchanged for MED-001 (out of scope; follow-up candidate).
- **Folder**: FILE-008 references in the Photos folder; MED-006's slides were already protected from photo
  operations; nothing protected a logo.
- **Compositor visuals**: Photo, Video, Camera and Text own a CMP-001 compositor; projectM (ANGLE) and the
  native spectra/oscilloscope draw without one.
- **Scenes/archives**: asset types photo, video, text, generatorGraph; archives hold at most one photo and
  one video (3 files).

## Design as built

- **Model**: the logo is a FILE-008 reference in the Photos folder named by `settings.logo.id`; its placement
  is `settings.logo.placement` (JSON). Import: MED-001's bounded read and MED-014 decoder with logo limits
  (10 MB, 16,777,216 pixels, stored ≤ 1024 px) and the new `ImageOutputFormat.png` (always PNG).
  `PhotoStore` (new photo, trim, Remove Photo) and `SlideshowStore` keep `LogoStore.protectedIDs`; a new
  logo and Remove Logo keep the photo and the slides.
- **Layer** (`LogoLayerSource`): sRGB → linear × alpha on the CPU (`PremultipliedLinear`, half-float bits
  built in plain Swift), a mipmapped `rgba16Float` texture whose mip chain is built from premultiplied texels,
  a quad at the placement rectangle sampled trilinearly × opacity; `.notReady` (transparent fallback)
  without a logo; CMP-013 still (image and placement generations). Its shader is a module constant in the
  reviewed `ImageLayerSource.swift` (SHD-011 allow list unchanged).
- **Scope**: the top layer of the Photo, Video, Camera and Text compositors (`Compositor.attachLogo` after
  each host is made), so it is in captures, recordings and the external display and inside the flash guard.
  Not on projectM or the native spectra (no compositor); Settings says so. Not an inspector layer (its
  composite is the default; solo of another layer hides it).
- **Placement**: corners or a custom anchor; size = fraction of the shorter side along the logo's longer
  side (0.05…0.5, default 0.15); margin (0…0.2, default 0.04); opacity; CMP-006's anchor rule inside the
  margins.
- **Scenes**: asset type `logo` (`storeID` + lenient `placement`), never "unused", a missing picture is a
  `missingAsset` repair entry titled "Logo"; older apps keep it as an unknown asset. Captured for every
  visual; launch restore, Reopen and cues apply it when the picture resolves; undo does not.
- **Archives**: type `logo`, `assets/logo.png`, PNG only, one per archive, up to 4 files; import stages
  through the logo path, adopts (dedup), makes it current with the scene's placement (before the photo,
  keeping the adopted photo); FILE-003's plan lists it. Archives without a logo are unchanged.
- **Backup/erase**: both keys in FILE-005's included keys; erased with "Photos and videos".
- **UI**: Settings → Logo (all visuals): summary, Choose from Photos (`preferredItemEncoding: .current`, so a
  HEIC/PNG with alpha is not transcoded), Choose from Files (`.png`, `.heic`, `.image`), Remove Logo,
  Position picker, Size/Margin/Opacity sliders (ACC-005), help, notice; announcements via the shared
  announcer (`check_status_events.py` now guards both files).

## Results

| Check | Result |
|---|---|
| S1 import acceptance (`LogoStoreTests.testImportKeepsAlphaWithinOneStep`) | pass: stored PNG, every alpha within 1/255, transparent rows 0 |
| S2 compositing acceptance (`LogoLayerTests`, real Metal compositor on the Mac host) | pass: 1:1 within 2/255 of premultiplied over in linear light; transparent region within 1/255 of the backdrop; quarter size: no channel below both colours |
| S3 export acceptance (`LogoArchiveTests.testAnExportedLogoKeepsItsAlphaAndPlacementInAFreshSandbox`) | pass: archive → fresh sandbox, alpha within 1/255, placement equal, dry run lists `assets/logo.png` |
| S4 placement (`LogoPlacementTests`) | pass: every corner at 390 × 844 and 844 × 390 within 1 px |
| S5 dedup/protection (`LogoStoreTests`, `LogoArchiveTests`) | pass |
| S6 backup/erase (LibraryBackup package, `LogoArchiveTests`) | pass |
| S7 UI (`LogoOverlayUITests`, own iOS 27.2 simulator) | pass, 18.7 s |
| S8 device picker | `{device}` open (T25) |

Package suites (Mac host): Compositor 459 CompositorTests (6 skipped, 0 failures; 1:46 for all targets),
SceneFormat 121, SceneArchive 29, LibraryBackup 44. Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL
-DANALYSIS_NO_ACCELERATE`): LogoPlacement/PremultipliedLinear 7, SceneLogo + source safety 6. App results:
see "App tests" below.

## App tests (own iOS 27.2 simulator "MED10 iPhone 17", deleted afterwards)

- `projectM-iOSTests`: 618 tests, 0 failures (34.5 s of test time; the run with build 3:28).
  New: `LogoStoreTests` 6, `LogoArchiveTests` 3 (each under 0.11 s).
- `PhotoLayerUITests` 1/1 (22.3 s), `LogoOverlayUITests` 1/1 (9.6-19.3 s over three runs),
  `SlideshowUITests` 1/1 after the DEBUG probes moved into `MediaProbes`.
- PosterBoard crash reports: 25 before, 25 after.
- Long-body flags (`-warn-long-function-bodies=300 -warn-long-expression-type-checking=150`): the shared Mac
  ran at a load average of about 716 (parallel agents), so timings were not meaningful (a one-line getter was
  flagged at 188 ms). `VisualizerView.layers` (339-358 ms) is pre-existing; this feature made it smaller.
- Checks: `check_compliance` (the logo shader lives in the reviewed `ImageLayerSource.swift`),
  `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`, `test_scripts`
  (153), `check_privacy_manifest` on the Debug simulator app: all OK.

## Open

- MED-010-T25 `{device}`: on D1, a transparent PNG from the real Photos picker and one from Files over the
  Photo visual in each corner (S8).
- The Settings → Logo section has no UI test (pickers cannot be automated); its controls are covered through
  the coordinator in app tests.
- No app screen consumes a scene archive import yet (SCN-014); the import makes the logo current in the
  store and saves its placement, which the app reads at the next launch.
- Follow-up candidate: the MED-001 photo layer's dark fringe (straight-alpha filtering, measured above).
