# Data Model: MED-009 Text Overlay

## TextOverlaySpec (package `TextLayer`, plain Swift, `Codable`, `Equatable`, `Sendable`)

| Field | Type | Range / values | Default |
|---|---|---|---|
| `version` (JSON only) | Int | 1 (`TextOverlaySpec.currentVersion`) | 1 |
| `message` | String | cleaned by `TextSanitizer` (R3, R4): ≤ 280 grapheme clusters, ≤ 8 lines | "" |
| `font` | `TextFontFamily` | `system`, `avenirNext`, `georgia`, `menlo` | `system` |
| `weight` | `TextFontWeight` | `regular`, `medium`, `bold`, `heavy` | `bold` |
| `size` | Double | 0.03…0.25 (share of the picture height; NaN → default) | 0.08 |
| `color` | `TextColor` | red, green, blue, alpha each 0…1 (sRGB, straight alpha) | white, 1 |
| `alignment` | `TextAlignmentChoice` | `leading`, `center`, `trailing` | `center` |
| `verticalPosition` | `TextVerticalPosition` | `top`, `middle`, `bottom` | `middle` |
| `outlineWidth` | Double | 0…0.15 (share of the font size; 0 = no outline) | 0.06 |
| `outlineColor` | `TextColor` | as `color` | black, 1 |
| `showsBox` | Bool | | false |
| `boxColor` | `TextColor` | as `color` | black, 0.5 |

Rules: the initializer and the decoder clamp every number and clean the message, so a spec value
always satisfies the table. Unknown enum raw values in JSON → the field's default (never a failure).
`isEmpty` is true when the message has no non-whitespace character.

## TextOverlayDecodeResult

`.spec(TextOverlaySpec)` | `.unsupportedVersion(Int)` | `.damaged` — from
`TextOverlaySpec.decodeStored(_ data: Data)`.

## TextDirection

`.leftToRight` | `.rightToLeft`; `TextDirection.of(_ message:)` (D5). `TextAlignmentChoice.side(for:)`
→ `TextHorizontalSide` `.left` / `.center` / `.right`.

## TextLayout (plain Swift)

From a spec and a picture size: `fontPixels`, `outlinePixels`, `boxPadding`, `areaX`, `areaWidth`,
`padding`; `canvas(frameHeight:)` → `TextCanvas` (x, y, width, height in picture pixels, and the text
frame's rectangle inside the canvas), clamped to the picture.

## TextRendering (plain Swift)

| Field | Meaning |
|---|---|
| `x`, `y`, `width`, `height` | the canvas rectangle in picture pixels (top-left origin) |
| `pictureWidth`, `pictureHeight` | the picture size it was drawn for |
| `pixels` | `[UInt8]`, width × height × 4, RGBA, premultiplied, sRGB-encoded, row 0 at the top |
| `inkBounds` | the smallest rectangle (canvas pixels) with alpha > 0, or nil |
| `checksum` | FNV-1a 64 over the picture size, canvas rectangle and pixels |

`linearHalfPixels()` → `[UInt16]` (half-float bit patterns, RGBA, linear premultiplied) for upload.

## TextLayerState

`.empty` (no text) | `.drawing` | `.ready(width:height:checksum:)` (the rendering) | `.failed(String)`.

## App

- `TextOverlayStore` (key `settings.text.overlay`): `load() -> TextOverlaySpec` (default for
  missing, damaged — key removed — or newer — key kept), `save(_:)`, `reset()`.
- `TextOverlayCoordinator` (`@Observable`, main actor): `spec` (each change saved and reported via
  `onSpecChange`), `messageWasCut` (the editor's note), `setMessage(_:)`, `reset()`.
- `VisualChoice.text` ("Text", persisted like Photo).
