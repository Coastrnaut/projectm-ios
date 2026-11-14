# Research: ACC-008 High Contrast Overlay

## ACC-008-D1: Target and measurement method

- **Decision**: WCAG 2.x contrast ratio: normal text ≥ 4.5:1, large text (≥ 18 pt, or ≥ 14 pt bold) and
  symbols ≥ 3:1. Measured by fixture:
  1. Each audited element is represented by its backing (the production `OverlaySurface` modifier, with
     the material left out) and each of its text styles (font, foreground style, sample words), rendered
     with `ImageRenderer` at scale 2 over a fixture frame: pure white, pure black, a saturated gradient
     (yellow → cyan → magenta → white), and a noisy pattern (2 px cells, deterministic generator, black,
     white and saturated colours).
  2. The same view is rendered again with the text hidden (`opacity(0)`, same layout).
  3. Every pixel is reduced to WCAG relative luminance (sRGB decoded, Rec. 709 weights), as ACC-003's
     grayscale method does.
  4. Glyph pixels: the luminance difference between the two renderings. The style's "strong difference" is
     the 95th percentile of the non-zero differences; core pixels are those with at least 75% of it, so
     anti-aliased edges are left out.
  5. For each core pixel, the ratio `(max(Lt, Lb) + 0.05) / (min(Lt, Lb) + 0.05)` between the pixel with
     text (Lt) and the same pixel without (Lb): the local background exactly, also over the noisy frame.
  6. The style's measured contrast is the 5th percentile of those ratios; it must reach the style's target.
- **Rationale**: the app already uses WCAG 2.x (ACC-003-R6); the twin rendering gives each glyph pixel its
  own background, which a busy frame needs; a low percentile ignores a few edge pixels without letting a
  weak style pass. APCA is a draft without iOS tooling.
- **Material**: `ImageRenderer` has no backdrop, so it cannot draw a blur material faithfully, and on
  device a material's tint depends on the system. The fixture therefore leaves the material out (the
  surface's `includesMaterial: false`): a lower bound on the real contrast.
- **Negative control**: a mid-grey label (0x777777) on the backing, and white text on the previous ACC-004
  backing (45% black) over white, must measure below 4.5:1.
- **Alternatives**: one solid colour pair computed analytically (misses translucent text and button fills);
  stored reference images (brittle, no number); XCUITest's `performAccessibilityAudit` (no ratio, and it
  depends on the live visual).

## ACC-008-D2: The backing level

- **Decision**: a black scrim over the element's material, at the lightest opacity (0.01 steps) where the
  weakest text style meets 4.5:1 over white with the material counted as transparent. Estimate before
  measuring: SwiftUI's dark `.secondary` (about 0.6 alpha) and the overlay accent need a background of
  sRGB ≤ about 0.2, so about 0.8 black. The fixture test sweeps the opacity and the chosen constant is the
  measured minimum rounded up to the next 0.01 (recorded in tasks and the quickstart). Opaque (1.0) with
  Increase Contrast.
- **Rationale**: over dark visuals the dark material already looks nearly black, so the change is visible
  only where it is needed (bright visuals). One level for all elements keeps one guarantee.
- **Alternatives**: fully opaque cards (loses the overlay look for no measured gain); per-element levels
  (more constants, same result); lighter text colours only (secondary and accent styles are spread across
  views and a package).

## ACC-008-D3: Adaptive "increase backing" mode

- **Decision**: not built.
- **Rationale**: the static backing passes over pure white, the worst frame, so an adaptive mode could only
  make the backing lighter over dark frames, where it is already hard to see. Measuring the visual under the
  controls needs a GPU read-back of the compositor's output (ANGLE/Metal) or a per-frame luminance
  reduction: extra GPU work and synchronisation next to the render path's real-time budget (Constitution
  VII, PERF features), plus a new failure mode (flicker as the backing follows the music).
- **Alternatives**: a reduction pass on the compositor at 2 Hz (cheap but still render-path code and a new
  state machine); dimming the visual behind the controls (changes the art, Constitution VIII spirit).

## ACC-008-D4: Overlay tints

- **Decision**: inside an overlay surface, `.tint` is ACC-003's increased dark accent 0x409CFF (accent text,
  bordered buttons); prominent buttons (white text on a fill) use 0x0062CC (ACC-003's light accent: white on
  it is about 5.8:1); the camera badge's red bordered Stop uses `InterfacePalette.critical` (dynamic: dark
  0xFF6961) instead of system red.
- **Rationale**: white on the default dark accent 0x0A84FF is about 3.6:1 and 0x0A84FF on a near-black
  scrim is about 3.5-5:1, so no single blue serves both button kinds.
- **Alternatives**: white button titles everywhere (loses the accent cue), borderless buttons only (layout
  changes).

## ACC-008-D5: One dark appearance

- **Decision**: every overlay surface forces the dark colour scheme, like the controls since ACC-004.
- **Rationale**: one backing and one text palette to guarantee; a light card would need a white scrim and a
  separate guarantee over black frames, and a black visual is as common as a white one.
- **Alternatives**: follow the system appearance with a `systemBackground` scrim (two guarantees, two
  fixture sets, same result).
