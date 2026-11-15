# Research: ACC-010 Left-Handed Layout

## ACC-010-D1: Explicit placement, not a layout-direction flip

- **Decision**: compute each target's slot explicitly (`PadPlacement`) and build the stacks in that order; place the corner button with an explicit leading or trailing spacer.
- **Rationale**: `.environment(\.layoutDirection, .rightToLeft)` would also flip text alignment, symbols that auto-mirror (`chevron.backward` / `chevron.forward`), and any nested text fields; it would also invert reading order for VoiceOver unpredictably. Explicit slots keep text and symbols untouched (ACC-010-R4) and are testable as pure values.
- **Alternatives**: `scaleEffect(x: -1)` on the layer (mirrors glyphs; rejected); RTL environment on the pad (flips chevrons and text; rejected).

## ACC-010-D2: One handedness object; one-handed wins while active

- **Decision**: store the Boolean on ACC-009's `OneHandedSetting` and derive `controlsSide`: the one-handed hand while one-handed is active (iPhone, a hand chosen), else left when the switch is on, else right.
- **Rationale**: avoids two independent "which hand" answers that could disagree; one-handed is iPhone-only while left-handed applies to iPad too, so the switch cannot simply be ACC-009's "Left hand". The pad already follows the one-handed hand in one-handed mode; the corner button now follows the same side.
- **Alternatives**: fold into ACC-009's choice (no iPad, and it relocates far more than performance controls; rejected); fully independent switch (two settings could contradict; rejected).

## ACC-010-D3: Mirror slots, keep the cue pair's reading order

- **Decision**: left-handed rows are the right-handed rows reversed; then, within any row holding both cue targets, Previous cue takes the left of the two slots. Side columns swap whole (vertical order kept).
- **Rationale**: Black out and Tap tempo land exactly at their mirrored positions (the dominant thumb's edge); the cue arrows point backward and forward, so swapping them would contradict their symbols and the arrow keys.
- **Results**: bar `Black out, Tap tempo, Previous cue, Next cue`; grid `[Previous cue, Next cue] / [Black out, Tap tempo]`; columns leading `Tap tempo, Black out` (tempo readout), trailing `Previous cue, Next cue` (cue readout).

## ACC-010-D4: Scope of mirrored controls

- **Decision**: the pad and SHOW-014's corner button only. The controls card (full width, FR-087's order), the HUD and badges (top, full width), the performance overlay (diagnostic) are unchanged.
- **Rationale**: the roadmap says "performance controls"; only those two are anchored to one side.

## ACC-010-D5: Test strategy

- **Decision**: pure geometry `PerformanceLayout.targetFrames(width:height:side:readoutHeight:)` mirrors the pad view's stack math (bar centred at the bottom; grid rows centred; columns inset by the margin and vertically centred) and is tested for exact mirroring at three sizes per arrangement. A UI test switches the setting in Settings and compares the real frames (within 1 pt); a second UI test checks the side columns. Output isolation reuses UIX-013's pattern: an `ExternalDisplayViewController` window with an asymmetric stand-in visual, snapshot byte-identical with the real `PerformancePadLayer` drawn right-handed and left-handed in a device window.
- **VoiceOver order**: follows the visual order (SwiftUI sorts a container's children by position), so a left-handed bar is read Black out, Tap tempo, Previous cue, Next cue. Accepted: VoiceOver users hear what they touch.
