# Contract: Overlay Surface (ACC-008)

## C1: Every audited element uses the surface

The elements of the spec's audit table that relied on a material use `overlaySurface(_:material:)`: the
controls (thick material), the source indicator (ultra-thin), the badges through `statusBadgeBackground`
(standard contrast), the status caption, route explanation, show notice, background and permission
notices, photo, video, frame and recording notices, capture result panels, recovery offer, status banner,
native-visual and preset failure banners, scene switcher card, emergency blackout button. The performance
overlay, the paused label and the external display note keep their own backings (they pass).

## C2: Appearance

- Dark colour scheme inside the surface.
- Black scrim at `OverlayContrast.scrimOpacity` over the material; 1.0 with Increase Contrast.
- `.tint` = 0x409CFF; prominent buttons inside use `overlayProminentTint()` (0x0062CC).
- With Increase Contrast, badges keep ACC-003's opaque bordered background (C1 of ACC-003's contract).

## C3: Measured guarantee

`OverlayContrastTests` renders each element's text styles over white, black, gradient and noise frames
(material left out) and asserts 4.5:1 (normal) or 3:1 (large, symbols) at the 5th percentile of glyph core
pixels (research D1). A grey label and the previous 45% backing must fail.

## C4: DEBUG probe (UI tests)

With `-uitestDiagnostics`, an invisible static text `overlaySurfaceProbe` has the value
`scrim:<opacity, 2 decimals>`, e.g. `scrim:0.82` normally and `scrim:1.00` with
`-uitestIncreaseContrast YES`. Not compiled into Release.

## C5: Unchanged

Accessibility identifiers, labels, values, hints, announcements and layouts; the visualization.
