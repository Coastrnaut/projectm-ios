# Research: ACC-005 VoiceOver Parameter Editing

Decisions are labelled D1… (not R-numbers, which belong to feature 001's research index).

## D1 Adjustable action on a SwiftUI Slider

- **Decision**: keep the `Slider` and attach `.accessibilityAdjustableAction` to it, plus
  `.accessibilityValue`. The custom action replaces the slider's built-in increment, so the step is
  ours; the element stays a slider for XCUITest (`app.sliders[id]`).
- **Rationale**: no new element tree, touch dragging unchanged, identifiers unchanged (R9).
- **Verification**: the UI test increments the glow intensity from 50 %; the system default step would
  give 60 %, ours gives 55 %, so the test proves which action ran.
- **Alternatives**: `.accessibilityElement(children: .ignore)` wrapper with a representation (changes
  the element type, breaks existing tests); `accessibilityRepresentation` (same).

## D2 How a UI test invokes increment

- **Decision**: `XCUIElement.increment()` and `decrement()`. XCTest documents them as "Increments/
  Decrements a slider or picker"; for an adjustable element they call the accessibility increment and
  decrement actions, the same entry points VoiceOver's swipe up and down use.
- **Rejected**: `adjust(toNormalizedSliderPosition:)` (sets a position by touch, never calls the
  action); `swipeUp()` with VoiceOver off (scrolls the list).

## D3 Step grid

- **Decision**: steps are counted from the range's minimum. Increment goes to the smallest grid value
  above the current value (by more than a 1e-9 relative tolerance), decrement to the largest below; the
  result is clamped. A value on the grid moves by exactly one step; a value off the grid moves to the
  next grid value in that direction. The maximum is always reachable even if it is not on the grid.
- **Rationale**: "exactly one step" from any stored value, no drift from floating-point accumulation
  (the grid value is computed as `minimum + n × step`, never `value + step`).

## D4 Spoken units

- **Decision**: spelled units, one formatter each, built in typed steps: "50 percent" / "2.5 percent";
  "plus 6 decibels" / "0 decibels" / "minus 1 decibel"; "minus 50 decibels full scale";
  "180 milliseconds" / "1 millisecond"; "1.5 seconds". Decimals use the user's locale
  (`formatted(.number.precision…)`), as MED-003 already does.
- **Rationale**: VoiceOver reads "dB", "dBFS" and sometimes "ms" letter by letter.

## D5 End announcements

- **Decision**: a new `AnnouncementKind.parameter` lane in the shared announcer. Texts:
  "Maximum, <spoken value>" and "Minimum, <spoken value>". The gate's 1 s window and 2 s repeat rule
  give at most one announcement per burst.
- **Reachability**: SettingsView receives the coordinator's announcer and puts it in the environment
  (`\.parameterAnnouncer`); sections read it there, so their initialisers do not change. Without an
  announcer (previews) nothing is announced.

## D6 Registry as source of truth

- **Decision**: the glow's range, unit (normalized → percent) and step hint come from
  `VisualParameterCatalog.descriptors`; the catalog stores only a multiplier of the hint (×5). Text,
  audio and loop controls are not in the registry (MOD-001 covers visual parameters), so their spec
  reads the owning setting's `range`/`step` constants.
