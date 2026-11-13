# Data Model: MED-001 Import Photo Layer

## ImageImportLimits (package, CPU)

| Field | Type | Default | Rule |
|---|---|---|---|
| `maxFileBytes` | Int64 | 40 × 1024 × 1024 | picked file larger → `.tooLarge` (R5) |
| `maxPixelCount` | Int | 100 000 000 | width × height larger → `.tooManyPixels` (R5) |
| `maxStoredLongestSide` | Int | 4096 | decoded/stored picture scaled down to fit (R5) |

`ImageImportLimits.standard` holds the defaults; tests pass smaller limits.

## ImageImportError (package, CPU; `Error, Sendable, Equatable`)

`notAnImage`, `tooLarge`, `tooManyPixels`, `damaged`, `unreadable` (source could not be read),
`saveFailed` (the copy could not be written). Each has a plain-language `message` used by the
app's notice (R11).

## DecodedImage (package, CPU)

| Field | Type | Rule |
|---|---|---|
| `width`, `height` | Int | ≥ 1, longest side ≤ `maxStoredLongestSide` |
| `pixels` | [UInt8] | RGBA8, sRGB-encoded, straight (non-premultiplied) alpha, row 0 top, `width × 4` bytes per row |
| `hasAlpha` | Bool | false when every alpha is 255 or the source has no alpha channel |

## SanitizedImage (package, ImageIO)

`data` (PNG or JPEG bytes, no metadata), `fileExtension` (`png` / `jpg`), `width`, `height`,
`hasAlpha`. Made by `ImageSanitizer.sanitize(data:limits:)`.

## ImageLayerContent / ImageLayerState (package)

- Content: `.none` | `.file(URL)`.
- State: `.empty` (no content) → `.loading` → `.ready(width:height:)` | `.failed(ImageImportError)`.
  Setting new content restarts at `.loading` (or `.empty`); a stale load's result is dropped.
  The layer renders only in `.ready`; every other state throws `.notReady` (transparent fallback).

## ImagePictureGeometry (package, CPU)

`visibleWidth`, `visibleHeight`, `offsetX`, `offsetY` (Float): the part of the picture shown, as
fractions of the picture, mapping output (0…1, top-left) → texture (0…1). Fill: visible ≤ 1 per
axis. Fit: visible ≥ 1 on the letterboxed axis; texture coordinates outside 0…1 are transparent.

## LayerKind.photo (package, CPU)

`LayerKind("photo", maximumInstances: 1)` — one per stack in this row (MED-006 lifts it).

## StoredPhoto (app)

| Field | Type | Rule |
|---|---|---|
| `id` | UUID | stored as `settings.photo.id` (uuidString) |
| `url` | URL | `<Application Support>/Photos/<id>.<png|jpg>`; nothing else is ever resolved (R14) |
| `width`, `height` | Int | from the sanitizer at import; re-read from the layer state after relaunch |

PhotoStore operations: `current()` (resolve; clears an invalid/missing ID), `importImage(at:)`
(read once, sanitize, write atomically, store ID, delete the previous file), `remove()` (delete the
file and the ID). Transitions: none → stored (import), stored → stored' (import replaces),
stored → none (remove, or missing file at resolve).

## Settings keys (app)

- `settings.visual` may be `photo` (persisted, R8).
- `settings.photo.id` (String UUID; absent = no photo). Added to `AppSettings.allKeys`.
