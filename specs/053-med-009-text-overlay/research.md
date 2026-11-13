# Research: MED-009 Text Overlay

Decisions D1-D9, each with its rationale and the alternatives considered.

## MED-009-D1: Text engine — CoreText into a CPU bitmap

- **Decision**: `CTFramesetter` lays out an attributed string in a rectangle (word wrapping, font
  fallback for emoji, CJK and Arabic, bidirectional ordering and shaping are CoreText's); `CTFrameDraw`
  draws it into a `CGContext` (8 bits per component, RGBA, premultiplied last, sRGB).
- **Rationale**: CoreText is the system text engine: it handles every script and emoji the system
  has fonts for, with no bundled fonts or shaping code. Drawing on the CPU once per change keeps the
  frame loop free of text work (MED-009-R8, R9).
- **Alternatives**: a glyph atlas drawn by a shader (per-frame layout, a new shader, a complex
  fallback story); SwiftUI/UIKit text in a view over the visual (not part of the composited picture,
  not on an external display, no deterministic bytes); `NSAttributedString.draw` (UIKit, not in a
  package that builds without UIKit).

## MED-009-D2: Determinism

- **Decision**: one rasterization at a time on a serial queue; a fresh zero-filled bitmap; integer
  canvas sizes from the placement arithmetic (rounded once); no font smoothing differences (iOS has
  none; `setShouldSmoothFonts(false)` on macOS hosts too); antialiasing on. Identity is asserted on
  the bytes and on an FNV-1a 64 checksum over the size, origin and bytes.
- **Rationale**: CoreText output depends only on the string, attributes, fonts and context; with
  those fixed, repeated draws are byte-identical (verified by the tests). "After relaunch" adds only
  the stored spec, which round-trips exactly (Codable with `Double` fields).
- **Alternatives**: comparing within a tolerance (would not prove "identically"); a cryptographic
  hash (`CryptoKit` is not on Linux; FNV-1a is enough to detect change and is plain Swift).

## MED-009-D3: GPU path without a shader

- **Decision**: convert the bitmap once to linear premultiplied half floats on the CPU (un-premultiply,
  sRGB → linear by a 256-entry table, re-premultiply, float → half by a plain-Swift conversion), upload
  into an `.rgba16Float` texture of the rendering's size, and per frame: a render pass that only
  clears the layer picture, then `MTLBlitCommandEncoder.copy(from:…to:…)` into the rendering's
  rectangle.
- **Rationale**: same pixel format, so a blit is legal; no Metal source (SHD-011 allowlist unchanged);
  the picture equals the uploaded bytes (S5 within 1/255 is then exact up to half precision).
- **Alternatives**: an `.rgba8Unorm_srgb` texture sampled by a shader (new allowlisted source); a
  full-picture-sized texture (needless memory: the text area is usually a fraction of the picture).

## MED-009-D4: Grapheme clusters and lines

- **Decision**: limits count Swift `Character`s (extended grapheme clusters, Unicode's rules in the
  standard library, the same on Apple platforms and Linux). The cleaner works on Unicode scalars
  first (CR LF, CR, U+2028, U+2029 → LF; tab → space; other `Cc` removed; `Cf` kept), then cuts to
  280 characters and turns line breaks after the 8th line into spaces.
- **Rationale**: an emoji family with skin tones, a flag or a letter with combining marks is one
  character to the viewer; cutting by scalars or UTF-16 units would split them.
- **Alternatives**: `NSString.length` (UTF-16; splits emoji); counting bytes.

## MED-009-D5: Direction and alignment

- **Decision**: the message's direction is that of its first strong letter: a scalar whose general
  category is a letter (Lu, Ll, Lt, Lm, Lo) is strong; it is right to left when it lies in the
  right-to-left blocks (Hebrew, Arabic, Syriac, Thaana, N'Ko, Samaritan, Mandaic, Arabic Extended,
  the Hebrew and Arabic presentation forms, and the supplementary right-to-left ranges
  U+10800-U+10FFF and U+1E800-U+1EFFF); U+200F (RLM) and U+061C (ALM) count as right to left, U+200E
  (LRM) as left to right; no strong letter → left to right. The paragraph style gets that base
  direction explicitly, and alignment maps leading → left (LTR) / right (RTL), trailing → the other
  side, center → center.
- **Rationale**: Swift's `Unicode.Scalar.Properties` has no bidi class; the block ranges plus the
  letter category give the UAX #9 P2 result for every script the app's users are likely to type, in
  plain Swift testable on Linux. CoreText still orders runs inside each line.
- **Alternatives**: `NSLinguisticTagger`/`NLLanguageRecognizer` (heuristic, not on Linux);
  CoreText's natural alignment (no "trailing", and the side could not be tested on Linux).

## MED-009-D6: Placement and size

- **Decision**: font size in pixels = size × picture height (3 %-25 %, default 8 %); the text area is
  the picture's width minus 5 % on each side; its height is CoreText's suggested frame height for
  that width, at most the picture's height minus 10 %; vertical position top (5 % from the top),
  middle or bottom (5 % from the bottom). The canvas (the rendering's rectangle) is the text area
  grown by a padding of ⌈max(outline px, box padding)⌉ + 2 on each side, clamped to the picture.
  Outline px = outline × font px (0-15 %, default 6 %); box padding = 0.25 × font px.
- **Rationale**: relative sizes give the same look on any screen or external display (MED-009-R5);
  the clamp keeps every blit inside the picture.

## MED-009-D7: Outline and box

- **Decision**: three passes into the same context: the box (a filled rectangle around the union of
  the line bounds, grown by the box padding, if on); the outline (CoreText stroke-only, stroke width
  2 × outline as a percentage of the font size, so the visible border outside each glyph is the
  outline width); the fill on top. Emoji (color bitmap glyphs) draw in both glyph passes; the result
  is the same picture each time.
- **Alternatives**: one pass with a negative stroke width (fills and strokes, but half the stroke
  covers the glyph's inside, thinning it).

## MED-009-D8: Fonts

- **Decision**: System = `CTFontCreateUIFontForLanguage(.system)`, the others by family name
  ("Avenir Next", "Georgia", "Menlo") through a descriptor; weight through the traits dictionary
  (`kCTFontWeightTrait`: regular 0, medium 0.23, bold 0.4, heavy 0.56) and CoreText's descriptor
  matching (nearest face). A family that does not resolve falls back to the system font.

## MED-009-D9: Storage

- **Decision**: one UserDefaults key `settings.text.overlay` holding `JSONEncoder` output (sorted
  keys) of the spec with `"version": 1`. Reading decodes the version first: 1 → the spec (every field
  clamped, the message cleaned); any other number → "newer version" (ignored, not removed); not
  decodable → "damaged" (removed). Writing happens on each editor change (a few hundred bytes).
- **Alternatives**: a JSON file in Application Support (a second store for a few hundred bytes);
  one key per field (no single version, partial writes).
