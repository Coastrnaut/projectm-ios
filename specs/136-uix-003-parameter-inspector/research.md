# Research: UIX-003 Context Parameter Inspector

## UIX-003-D1 Reset write path

- Decision: Reset writes `descriptor.defaultValue` through the same `AppSettings` property the Settings
  control writes (`glowIntensity`, `glowEnabled`, `circularSpectrumBars`, …), mapped per ID exactly as
  `AppCoordinator.set(_:settings:texts:)` maps scene values. The property saves to UserDefaults; the
  visualizer observes it; SCN-010's history records it (Reset calls `endCoalescing()` before and after so
  it is one step).
- Rationale: one write path means persistence, scene autosave and undo behave exactly as for a slider.
- Alternatives: a `ParameterStore` per app (none exists; settings are the app's store); writing
  UserDefaults directly (would bypass observation and clamping).
- Exactness: every registry default is inside its setting's clamp range and is an offered choice
  (bars 64, spacing 0.2), and Float-widened glow defaults are stored as the same Double, so the stored
  value equals the declared default bit for bit (unit-tested).

## UIX-003-D2 Formatting

- Decision: `normalized` and `fractionOfOutput` → percent; decimals = max(0, digits of step × 100)
  (0.01 → 0, 0.001 → 1); `seconds` → "0.25 s" (two decimals); `perSecond` → "1.20/s"; `count` → whole;
  `degrees` → "30°"; `none` → plain number; enum → case display names; boolean → On/Off. Spoken text
  reuses ACC-005's `SpokenValueFormatter` (percent) and spells units ("seconds", "per second").
- Alternatives: raw numbers (unclear), per-parameter formatters (duplicate the registry).

## UIX-003-D3 Live modulation

- Decision: the reading is computed on demand from the host: bindings with that target, the MIDI
  live value, the modulator's value for the manual (or MIDI) value and, for the glow fields, the
  rendered `effectiveGlow` (after ACC-012's clamp). The inspector polls it in a `TimelineView` at
  0.1 s only when a reading exists at open time or later (the first poll decides); otherwise it shows
  "Not modulated" statically. With Reduce Motion on, no Gauge is drawn: text only.
- Rationale: no new observation of per-frame state, so the rest of the UI never re-renders per frame.
- Alternatives: publishing the effective glow as observable state (per-frame SwiftUI churn).

## UIX-003-D4 Entry point

- Decision: `.contextMenu` with "Inspect" plus `.accessibilityAction(named: "Inspect")` on the seven
  registry rows; a DEBUG `-uitestInspectParameter <id>` launch argument opens the sheet when Settings
  appears. Rejected: an info button per row (changes every row's layout and Dynamic Type behaviour);
  long-press gesture recognizers (conflict with slider drags).
