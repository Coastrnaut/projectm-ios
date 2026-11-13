# Research: MED-001 Import Photo Layer

No NEEDS CLARIFICATION remained after the spec's Clarifications. Each decision below records the
choice, the reason and what was rejected (IDs `MED-001-D1…`).

## MED-001-D1 Photos picker without library permission

- **Decision**: SwiftUI `PhotosPicker(selection:matching: .images)` without a `photoLibrary:`
  argument; the item is loaded with `loadTransferable(type: PickedImageFile.self)`, a
  `Transferable` with a `FileRepresentation(importedContentType: .image)` that copies the received
  file into the app's temporary folder. No `NSPhotoLibraryUsageDescription`.
- **Rationale**: the picker runs out of process and hands the app only the chosen asset, so no
  permission is involved and limited/full access does not matter. A file representation avoids
  holding a 40 MB `Data` and lets the importer check the size before reading.
- **Alternatives**: `PHPickerViewController` (same mechanism, more UIKit glue); `PhotosPicker` with
  `photoLibrary: .shared()` (returns library identifiers — not needed, and a step toward library
  access); `loadTransferable(type: Data.self)` (whole file in memory before the size check).

## MED-001-D2 Files picker

- **Decision**: `.fileImporter(allowedContentTypes: [.image], allowsMultipleSelection: false)` on
  Settings; the URL is read once under its security scope and with `NSFileCoordinator`
  (`.withoutChanges`), as AUD-001 does; the URL is not kept.
- **Alternatives**: open in place / bookmarks (keeps a reference to the original; refused by
  MED-001-R3).

## MED-001-D3 Stripping metadata

- **Decision**: decode with `CGImageSourceCreateThumbnailAtIndex` (`…FromImageAlways`,
  `…WithTransform` = upright, `ThumbnailMaxPixelSize` = 4096, `ShouldCacheImmediately`), then write
  the `CGImage` with `CGImageDestinationAddImage(destination, image, properties)` where
  `properties` holds only `kCGImageDestinationLossyCompressionQuality` (JPEG). No source
  properties are copied. PNG when the image's alpha info is not `none`/`noneSkip*`, else JPEG 0.9.
- **Rationale**: a new file built from pixels only cannot carry EXIF/GPS/TIFF/IPTC/XMP; applying
  the orientation while decoding removes the need for an orientation tag.
- **Check**: tests read the stored copy's `CGImageSourceCopyPropertiesAtIndex` and assert there is
  no `{GPS}`, `{Exif}`, `{TIFF}`, `{IPTC}` dictionary and no XMP (`CGImageSourceCopyMetadataAtIndex`
  has no GPS/EXIF tags).
- **Alternatives**: `CGImageDestinationCopyImageSource` with `kCGImageMetadataShouldExcludeGPS`
  (keeps the rest of EXIF); storing the original (rejected in Clarifications).

## MED-001-D4 Limits and checks order

- **Decision**: (1) file size ≤ 40 MB from `URLResourceValues.fileSize` (not a required-reason API)
  and a bounded read (`FileHandle.read(upToCount: limit + 1)`); (2) `CGImageSourceCreateWithData`
  and `CGImageSourceGetType` conform to `UTType.image`, `CGImageSourceGetCount` ≥ 1; (3) pixel size
  from `CGImageSourceCopyPropertiesAtIndex` width × height ≤ 100 000 000 (only the two numbers are
  read); (4) thumbnail creation non-nil, else `.damaged`. Each failure is an `ImageImportError`.
- **Finding (2026-11-13)**: ImageIO reports a PNG cut short as complete and decodes it with the
  missing rows empty (`CGImageSourceGetStatus` and the incremental source both say complete), so
  MED-001 detects only what ImageIO detects (a truncated JPEG, an impossible header). Detecting a
  short PNG (checking for its IEND chunk, a decode-time error count) is left to MED-014.
- **Finding (2026-11-13)**: ImageIO's JPEG writer always writes three technical EXIF fields of the
  new pixels (pixel width, height, color space). They describe the copy, not the original; the
  tests allow exactly those and check that no original value is anywhere in the stored bytes.
- **Rationale**: cheap checks first; no full decode of an oversized picture.

## MED-001-D5 Decoder boundary for MED-014

- **Decision**: `protocol ImageDecoding: Sendable { func decode(_ data: Data, limits: ImageImportLimits)
  throws(ImageImportError) -> DecodedImage }` with `ImageIODecoder` the default. `DecodedImage` is
  plain Swift (width, height, straight-alpha RGBA8 sRGB bytes, `hasAlpha`), so it builds on Linux.
  The sanitizer and the layer both go through a decoder value given at init.
- **Rationale**: MED-014 can wrap or replace the decoder (stricter checks, memory budget) without
  touching the layer or the app.

## MED-001-D6 Texture, color and alpha

- **Decision**: the decoder draws the upright `CGImage` into an 8-bit RGBA sRGB
  `premultipliedLast` `CGContext` (converting any source color space, e.g. Display P3, to sRGB),
  then un-premultiplies on the CPU (straight alpha). The layer uploads it to a mipmapped
  `.rgba8Unorm_srgb` texture (the sampler returns linear light) and generates mipmaps with a blit
  on its own command queue on the background queue. The shader multiplies color by alpha, so the
  layer picture is linear premultiplied (CMP-001-R2).
- **Rationale**: premultiplying in sRGB-encoded space and then linearizing would darken edges of
  transparent images; straight alpha avoids it. Mipmaps avoid shimmering when a 4096 px copy is
  shown on a 1179 px wide drawable. 8 bits per channel keep a 4096² copy at 64 MB.
- **Alternatives**: a half-float linear context (twice the memory); no mipmaps (aliasing).

## MED-001-D7 Loading without stalling the frame loop

- **Decision**: `ImageLayerSource` takes an `ImageLayerContent` (`.none` or `.file(URL)`); setting
  it starts one background decode (a serial `DispatchQueue`) tagged with a generation number. The
  result (texture or error) is handed over through an `OSAllocatedUnfairLock` slot (the layer is
  Metal-only, so Apple-only; the camera's newest-frame slot does the same); `render` takes it with
  the non-blocking `withLockIfAvailableUnchecked` and keeps the texture it already holds when the
  lock is busy. A stale generation's result is dropped. State changes are
  reported on the main queue (`onStateChange`).
- **Rationale**: CMP-001's contract forbids I/O and unbounded waits in `render`; `prepare` (called
  on size change) does not re-decode, it only builds the pipeline once.

## MED-001-D8 Geometry

- **Decision**: `ImagePictureGeometry(pictureWidth:pictureHeight:outputWidth:outputHeight:mode:)`
  with `mode` `.fill` (default; visible fraction ≤ 1, centered crop) or `.fit` (scale ≥ 1 in output
  space, letterbox outside 0…1 drawn transparent). No rotation: the copy is already upright.
- **Rationale**: same arithmetic as `CameraPictureGeometry` without rotation; fit is ready for
  MED-007/MED-010.

## MED-001-D9 Storage and identifier

- **Decision**: `Application Support/Photos/<UUID>.<png|jpg>`; the UUID string in
  `settings.photo.id`. Resolution accepts only a canonical UUID string and one of the two
  extensions, looks up `<dir>/<uuid>.png` then `.jpg` with `FileManager.fileExists` (no
  timestamps), and never follows another path. Writes are atomic (`Data.write(options: .atomic)`).
  Included in backups (Clarifications). A new import writes the new file, stores its ID, then
  deletes the old file.
- **Alternatives**: a JSON index (unneeded for one photo; MED-006 can add one);
  `isExcludedFromBackup` (rejected in Clarifications).

## MED-001-D10 Privacy manifest

- **Decision**: avoid required-reason APIs: no `attributesOfItem`, no creation/modification dates,
  no volume capacity checks (a full disk surfaces as a write error → `.saveFailed`). Run
  `scripts/check_privacy_manifest.py` on the simulator build of the app.

## MED-001-D11 Test seeding

- **Decision**: DEBUG-only `-uitestSeedPhoto <solid|alpha>` generates a 64 × 48 PNG with
  CoreGraphics in the temporary folder and imports it through `PhotoStore.importImage(at:)` before
  the visualizer starts; `-uitestResetNotice` also removes the photo folder. `-uitestPhotoVisual`
  is not needed: the UI test chooses "Photo" in Settings.

## MED-001-D12 Persisted visual choice

- **Decision**: `VisualChoice.photo` is stored in `settings.visual` like the spectra. The host is
  created when Photo is chosen; with no stored photo it shows the spectrum over black.
