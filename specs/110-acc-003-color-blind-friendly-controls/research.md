# Research: ACC-003 Color-blind Friendly Controls

## ACC-003-D1 — Symbol shapes per state

- Decision: one SF Symbol per state, chosen so that every pair in a group differs in outline, not only
  in fill:
  - Audio state (CaptureUI `UIStrings.stateSymbol`): not started `circle.dashed`, waiting `hourglass`,
    no audio received `waveform.slash`, silent `speaker.slash`, active `waveform`, paused
    `pause.circle`, interrupted `exclamationmark.triangle`, stopped `stop.circle`, ended by system
    `xmark.octagon`; switching source `arrow.triangle.2.circlepath`.
  - Recording: recording `record.circle.fill`, finishing `hourglass`.
  - Camera: starting `video.badge.ellipsis`, live `video.fill`.
  - Blackout: blacked out `eye.slash`, restoring `eye`.
  - OSC: listening `dot.radiowaves.left.and.right` (absent otherwise).
- Rationale: shapes are the strongest grayscale cue and scale with Dynamic Type; the words stay the
  primary cue. Unit tests check that each name exists (`UIImage(systemName:)`) and is unique per group.
- Alternatives: patterns or outlines on the dot (weak at 10 pt); text-only (already present but no
  glanceable shape).

## ACC-003-D2 — Interface palette values

sRGB hex, light / dark / light increased / dark increased; ratios computed with WCAG 2.x relative
luminance (white `FFFFFF` and grouped `F2F2F7` in light, black `000000` and grouped `1C1C1E` in dark):

| Role | Light | Dark | Light, increased | Dark, increased |
|---|---|---|---|---|
| accent | `0062CC` (5.8, 5.2) | `0A84FF` (5.8, 4.7) | `0040DD` (7.6, 6.8) | `409CFF` (7.4, 6.0) |
| positive | `1E7B34` (5.3, 4.8) | `32D74B` (11.0, 8.9) | `145A24` (8.3, 7.5) | `7CE38B` (13.2, 10.7) |
| caution | `A04D00` (5.9, 5.3) | `FF9F0A` (10.2, 8.3) | `7A3A00` (8.6, 7.7) | `FFC266` (13.2, 10.7) |
| critical | `C4161C` (6.0, 5.4) | `FF6961` (7.5, 6.0) | `9B0F14` (8.5, 7.6) | `FF9A94` (10.3, 8.4) |

- Decision: standard ≥ 4.5:1 against both backgrounds; increased ≥ 7:1 against the page background and
  ≥ 6:1 against the grouped background. The dark standard and both increased accents are Apple's own
  system blues (unchanged behaviour there); only the light standard accent changes (`007AFF`, 4.0:1, →
  `0062CC`).
- Rationale: fixes ACC-004's "nearly passed" Add Current Scene; keeps white-on-accent prominent buttons
  at the system's dark-mode values rather than making them lighter (a lighter dark accent would lower
  white text on `.borderedProminent`).
- Mechanism: an `AccentColor` colour set in the asset catalog (Any/Dark × normal/high contrast),
  selected by `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`, so lists, alerts, sheets and UIKit
  tint follow it. Status colours are code (`InterfacePalette`) with dynamic `UIColor` providers; a unit
  test resolves both under the four trait combinations and checks the ratios and that the asset
  matches the table.

## ACC-003-D3 — Reading Increase Contrast and Differentiate Without Colour

- Decision: views read a custom environment value `statusAppearance` set once at the root from
  SwiftUI's `colorSchemeContrast` and `accessibilityDifferentiateWithoutColor`. In DEBUG,
  `-uitestIncreaseContrast YES` sets `UIWindowScene.traitOverrides.accessibilityContrast = .high` on the
  app's scenes (so the asset accent and dynamic colours resolve their high-contrast variants exactly as
  with the real setting), and `-uitestDifferentiateWithoutColor YES` forces the custom value.
- Rationale: one place to override for tests (as ACC-001's `-uitestReduceMotion`); the trait override
  is public API and exercises the same resolution path as the system setting.
- Alternatives: setting SwiftUI's environment values directly (not settable for all of them);
  per-view overrides (scattered).

## ACC-003-D4 — Grayscale snapshot method

- Decision: in `projectM-iOSTests` (hosted on the simulator), render each state's cue view with
  `ImageRenderer` at scale 2 in a fixed frame on a solid background (white for light, black for dark),
  draw the `CGImage` into an 8-bit `CGColorSpaceCreateDeviceGray()` context (Core Graphics converts
  colour to luminance), then compare two states: the share of pixels whose gray values differ by at
  least 51 (20% of 255). Distinguishable means ≥ 1%. A negative control renders one symbol in two
  colours of equal relative luminance (computed, e.g. a red and a green matched to Y = 0.2) and must
  measure < 1%.
- Rationale: grayscale removes hue, the thing colour-blind users and iOS's grayscale filter lose; the
  pixel share catches both shape and word differences; the control proves the measure is not fooled by
  hue. No reference images are stored (no golden-file churn).
- Alternatives: stored golden snapshots (brittle across OS builds); XCUITest screenshots (slow, and
  the status must be driven into each state).

## ACC-003-D5 — Smart Invert

- Decision: `.accessibilityIgnoresInvertColors()` on the visualizer's `visual` slot (projectM, native
  spectra, camera, photo, video, text). Controls and badges are left to iOS.

## ACC-003-D6 — Colour-blind-safe spectrum palette

- Decision: `VisualPalette.colorBlindSafe`, five sRGB stops derived from the cividis map (designed to be
  near-identical for deuteranopia and protanopia, luminance rising monotonically), lightened at the start
  so the first bar has at least 3:1 on black: `4D5C7B` (3.1:1), `6B6F7A`, `8F8A78`, `BBAE6E`, `FDE738`, interpolated in linear light like the `ice` palette. A Settings toggle "Color-blind-safe
  colors" (section shown for native visuals), key `settings.visual.colorBlindSafePalette`.
- Rationale: minimal (one enum case, one key); content colours never carry status, so this is comfort,
  not compliance.
- Alternatives: viridis (green-heavy start, darker first stop); a full palette editor (UIX-011).

## ACC-003-D7 — High-contrast badge background

- Decision: a view modifier `statusBadgeBackground(_:)`: standard → the badge's existing material;
  increased → opaque `systemBackground` with a 1 pt `Color.primary` border, same shape.
- Rationale: materials let the moving visualization show through, which lowers contrast unpredictably.
