# Research: MED-010 Logo Overlay

## MED-010-D1: Alpha through import (audit)

- **Finding**: `ImageIODecoder.pixels(of:)` draws into an 8-bit premultiplied sRGB context and
  un-premultiplies; alpha bytes are carried exactly (only colour loses precision at very low
  alpha, which premultiplication hides again). `ImageSanitizer` writes PNG (`.last`, straight
  alpha) when any pixel is not opaque, else JPEG 0.9. The thumbnail path (`kCGImageSourceThumbnail…`)
  is only a resample when the picture is larger than the stored size.
- **Decision**: reuse the decoder and sanitizer, add `format: .png` so a logo is always PNG, and
  pass logo limits (10 MB, 16,777,216 pixels, 1024 px stored). The acceptance compares alpha at the
  same size (a fixture smaller than 1024 px).
- **Alternatives**: copying the picked PNG byte for byte (keeps metadata and unchecked chunks; the
  constitution's privacy rule and MED-014 forbid it).

## MED-010-D2: Premultiplication on upload (audit and decision)

- **Finding**: `ImageLayerSource` uploads straight-alpha sRGB texels and premultiplies after the
  sampler. Bilinear and mip filtering of straight alpha averages the RGB of transparent texels
  (stored as 0, black) with the edge colour, so a scaled soft edge is darkened: at a texel half
  way between (c, a = 1) and (0, a = 0) the filtered value is (c/2, 1/2), premultiplied to
  (c/4, 1/2) instead of (c/2, 1/2): a dark fringe. The sRGB texture format converts each texel to
  linear before filtering (correct), but the alpha weighting is missing.
- **Decision**: the logo layer converts on the CPU: linear = sRGB⁻¹(c/255), stored = linear × a, as
  IEEE half floats in an `rgba16Float` texture; mipmaps are generated from those premultiplied
  values (box filter, correct for premultiplied data); the shader samples and multiplies by opacity
  only. A 1024 px logo is 8 MB (+⅓ for mips). Half floats keep 11 bits of mantissa, so linear values
  near 0 keep their precision (better than 8-bit premultiplied sRGB).
- **Alternatives**: premultiplying 8-bit sRGB on the CPU (premultiplying non-linear values is wrong
  for blending in linear light); fixing `ImageLayerSource` (out of scope: changes MED-001's output;
  recorded as a follow-up finding for the photo layer).

## MED-010-D3: Storage

- **Decision**: a reference in the Photos folder named by `settings.logo.id` (spec Clarifications).
  `LogoStore.protectedIDs(defaults)` (the logo id) is added to `PhotoStore.makeCurrent`'s and
  `remove`'s keep sets, exactly like MED-006's slides; `SlideshowStore.release` skips it.
  `LogoStore.makeCurrent` releases the previous logo's payload keeping the photo, the slides and
  the new logo; `remove` likewise.
- **Alternatives**: a new `Logos` folder (backup, erase, storage usage, cache cleanup and archive
  dedup would each need a new path).

## MED-010-D4: Visual scope and attachment

- **Decision**: an app extension `Compositor.attachLogo(_:)` appends a `.logo` entry at the top of
  the applied stack and applies it with a factory that returns the given layer (the CMP-002 path;
  kept IDs keep their pictures). `LogoCoordinator.attach(to:)` creates one `LogoLayerSource` per
  compositor, keeps it weakly, and pushes content and placement changes to every live one. The
  layer inspector's `applyLayerComposites` gives the `logo` kind the default composite (identity,
  opacity 1), so the logo's own placement and opacity are never overridden.
- **No logo**: the layer throws `.notReady` (transparent fallback; not a fault, nothing drawn).
- **Alternatives**: a SwiftUI overlay above every visual (blends in display space, misses
  recordings and captures); adding `.logo` in each host's `make` (four host files touched).

## MED-010-D5: Placement maths

- **Rule**: with output W × H, s = min(W, H), logo w × h, size f (0.05…0.5), margin m (0…0.2),
  anchor (ax, ay): the longer logo side L = f·s; drawn size dw = L·w/max(w,h), dh = L·h/max(w,h);
  margin px = m·s; x = px + ax·(W − 2·px − dw), y = px + ay·(H − 2·px − dh) (top-left origin).
  Corners: top left (0,0), top right (1,0), bottom left (0,1), bottom right (1,1), centre (0.5,0.5).
  This is CMP-006's `offset = anchor·(1 − visible)` rule applied inside the margins. When the logo
  does not fit inside the margins the same formula centres the overflow around the anchor (it is
  never clamped into a different place).
- The shader maps output points to texture coordinates through the rectangle (transparent
  outside), like `ImagePictureGeometry`.

## MED-010-D6: Scenes and archives

- **Scene**: asset `"logo": {"type": "logo", "storeID": "<UUID>", "placement": {…}}`. The type is
  new, so older apps keep it as an unknown asset (SCN-001-R10) — no version change. `placement` is
  a known field of the logo type, read leniently (missing or malformed fields → defaults, values
  clamped). Validation: non-canonical store ID → error; picture missing → `missingAsset` (the
  availability's photos, since logos live in the Photos folder); a logo asset is never `unusedAsset`.
- **Archive**: `SceneArchiveAssetType.logo` (`png` only), at most one per archive, `maximumFiles` 4,
  size limit the photo limit (the logo store's own 10 MB limit applies when staging). Import stages
  it with a staging `LogoStore`, adopts it into the Photos folder (deduplicated), and makes it
  current with the scene's placement after the photo and video. FILE-003's plan lists it.
- **Restore**: launch restore, Reopen and cues apply the scene's logo when its picture resolves;
  undo does not (spec Clarifications).

## MED-010-D7: Settings UI and announcements

- `LogoSection` (own view file, small bodies): preview row, Choose from Photos (`PhotosPicker`),
  Choose from Files (`fileImporter`, `.png`, `.heic`, `.image`), Remove Logo, corner picker, size,
  margin and opacity sliders through `.accessibleParameter` (ACC-005), help text. Announcements use
  the coordinator's injected closure wired to the shared announcer (kind `library`).
