# Contract: Status cues and the interface palette (ACC-003)

## C1. Cues (always shown)

| Group | State | Symbol | Words (unchanged) |
|---|---|---|---|
| source | each `AudioState` | research D1 | `UIStrings.sourceStatus` |
| source | switching | `arrow.triangle.2.circlepath` | "Switching source…" |
| recording | recording / finishing | `record.circle.fill` / `hourglass` | "REC m:ss" / "Finishing…" |
| camera | starting / live | `video.badge.ellipsis` / `video.fill` | "Camera on" (or "Front camera on"); with Differentiate Without Colour + " · Starting" / " · Live" |
| blackout | blacked out / restoring | `eye.slash` / `eye` | "Output blacked out" / "Restoring output" |
| osc | listening | `dot.radiowaves.left.and.right` | "OSC listening on port N" |
| tempo | stable / uncertain / searching | none (ANL-006 words) | "Stable" / "Uncertain" / "Searching" |

- Symbols are `accessibilityHidden`; every existing accessibility label, value and identifier is
  unchanged. The status banner's state words use the primary text colour.

## C2. Palette

- `AccentColor` asset and `InterfacePalette` roles as research D2; standard ≥ 4.5:1, increased ≥ 7:1
  (page) and ≥ 6:1 (grouped).
- With Increase Contrast the badges in spec R9 draw an opaque `systemBackground` with a 1 pt primary
  border.

## C3. DEBUG launch arguments

| Argument | Effect |
|---|---|
| `-uitestIncreaseContrast YES` | `traitOverrides.accessibilityContrast = .high` on every window scene |
| `-uitestDifferentiateWithoutColor YES` | forces `statusAppearance.differentiateWithoutColor` |
| with `-uitestDiagnostics` | probe `statusAppearanceProbe`, value `contrast:<standard|increased> dwc:<on|off>` |

## C4. Grayscale test

`ColorBlindControlsTests.testCriticalStatusesStayDistinguishableInGrayscale`: for each group in
`StatusCueCatalog.groups`, in light and dark, every pair of states differs in ≥ 1% of pixels by ≥ 51/255
after grayscale conversion; the equal-luminance control measures < 1%.

## C5. Spectrum palette

`settings.visual.colorBlindSafePalette` (Bool) → `VisualPalette.colorBlindSafe` for all native spectra;
toggle `colorBlindSafePaletteToggle` in Settings (shown for native visuals).
