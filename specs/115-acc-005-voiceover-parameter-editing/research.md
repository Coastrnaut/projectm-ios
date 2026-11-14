# Research: ACC-005 VoiceOver Parameter Editing

Decisions are labelled D1… (not R-numbers, which belong to feature 001's research index).

## D1 Adjustable action on a SwiftUI Slider (revised at implementation, 2026-11-14)

- **Planned**: keep the `Slider`'s own element and attach `.accessibilityAdjustableAction` to it.
- **Finding**: on iOS a SwiftUI `Slider` is backed by a `UISlider`, and that `UISlider` is the
  accessibility element (it carries the identifier, label and value). Calling its
  `accessibilityIncrement()` in the running app (simulator, iOS 27.2) changed nothing: SwiftUI does not
  route the platform slider's increment to `.accessibilityAdjustableAction`, so VoiceOver would get the
  system's own slider step (10 % of the range) at best, never the parameter's step.
- **Decision**: `.accessibilityElement(children: .ignore)` on the slider, then label, spoken value,
  identifier and the adjustable action on that element. SwiftUI's own element implements increment
  and decrement by calling the action; the same call that did nothing on the `UISlider` now moves the
  glow intensity from 50 % to exactly 55 % (UI test). Touch dragging is unchanged (the `UISlider` still
  takes touches); identifiers and labels are unchanged (R9).
- **Cost**: XCTest now reports the element as "other", not "slider", so `app.sliders[id]` and
  `adjust(toNormalizedSliderPosition:)` no longer apply. The existing slider UI tests find it with
  `app.slider(id)` and drag its thumb by coordinates (`UITestSliders.swift`).

## D2 How a UI test invokes increment (revised at implementation, 2026-11-14)

- **Planned**: `XCUIElement.increment()`/`decrement()`. **Finding**: those exist only in the macOS
  XCTest SDK; on iOS `adjust(toNormalizedSliderPosition:)` drags by touch and never reaches the action,
  and `swipeUp()` without VoiceOver scrolls the list.
- **Decision**: a DEBUG-only probe (`Debug/UITestAccessibilityActionProbe.swift`, launch argument
  `-uitestAccessibilityActions`): two small buttons beside each accessible slider. A tap searches the
  app's accessibility tree (window subviews and accessibility children) for the on-screen element with
  the slider's identifier and calls `accessibilityIncrement()` / `accessibilityDecrement()` on it, the
  UIAccessibility entry points VoiceOver's swipes use. The probe never calls the app's closure, so the
  test covers SwiftUI's bridge and the app's action. Release builds contain none of it.

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
