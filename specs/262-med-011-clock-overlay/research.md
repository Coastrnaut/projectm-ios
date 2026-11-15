# Research: MED-011 Clock Overlay

## MED-011-D1 Renderer
- **Decision**: reuse MED-009's `TextLayerSource`; the clock only sets its `spec` (style + time string).
- **Rationale**: `TextLayerSource` already rasterizes off the frame loop only when the spec changes, is still for
  CMP-013 and needs no shader; `TextLayerKind` anticipated this use.
- **Alternatives**: a dedicated glyph-atlas clock layer (faster per change, but a second text renderer and new
  shader source; rejected for a once-per-second change).

## MED-011-D2 Where the tick runs
- **Decision**: a main-actor task in `ClockOverlayCoordinator` sleeps until the next whole second
  (`ClockSchedule.delay(after:)`), formats once and pushes a new spec only when the string changed.
- **Rationale**: the compositor visuals run their frame loop on the main run loop, so setting `spec` there is on the
  compositor's thread. `renderDependencies` must not allocate, so formatting in the frame path was rejected.
- **Alternatives**: formatting per frame in a wrapper layer (allocates on the frame path), a `Timer` (no alignment
  benefit, harder to stop).

## MED-011-D3 Formatting
- **Decision**: `DateFormatter` with fixed patterns `HH:mm`, `HH:mm:ss`, `h:mm a`, `h:mm:ss a`, an injected `Locale`
  and `TimeZone`. Fixed patterns keep the plain ASCII space before AM/PM (template-based formats can insert a narrow
  no-break space depending on the ICU version), so strings are byte-stable on Apple platforms and Linux.
- **Alternatives**: `Date.FormatStyle` (output varies with ICU data versions; harder to pin exact strings).

## MED-011-D4 Layer placement in the stack
- **Decision**: `LayerKind.clock` (one per stack) added on top of the stack by `Compositor.attachClock`, like
  MED-010's `attachLogo`; attached after the logo, so the clock is the top layer.

## MED-011-D5 Time zone and DST
- **Decision**: the system source returns `TimeZone.current` at each tick (so a time zone change shows within a
  second); `DateFormatter` applies the zone's rules, so spring-forward and fall-back follow the system database.
  Tests use `America/New_York` 2026 transitions and skip if the zone database is missing (Linux containers).
