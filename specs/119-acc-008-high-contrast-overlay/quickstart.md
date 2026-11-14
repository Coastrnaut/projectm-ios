# Quickstart: ACC-008 High Contrast Overlay

## Prerequisites

`xcodegen generate`; preset submodules initialised; an iOS 27.2 simulator of your own.

## A. Fixture table (unit tests, simulator)

```zsh
args=(-project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination "id=<udid>"
      -derivedDataPath .autonomous/derived-data-acc-008 CODE_SIGNING_ALLOWED=NO
      -test-timeouts-enabled YES -default-test-execution-time-allowance 180)
xcodebuild test "${args[@]}" -only-testing:projectM-iOSTests/OverlayContrastTests
```

Expected: every element × style × frame row printed as `ACC-008 contrast <element> <style> <frame>: p5 …`
and at least its target; the negative control and the old 45% backing print below 4.5 and are asserted
to fail; the scrim sweep prints the lightest passing level, equal to `OverlayContrast.scrimOpacity`.

## B. Probe (UI test)

`-only-testing:projectM-iOSUITests/OverlayContrastUITests`: `scrim:<level>` normally, `scrim:1.00` with
Increase Contrast. Under 30 s.

## C. Regressions

`projectM-iOSTests`, `ColorBlindControlsUITests`, `StatusUITests`.

## D. Device (`{device}`, last stage)

D1, standard text size: run the brightest presets (white flashes, saturated fills), show the controls and
each badge; every word must be readable. Repeat with Increase Contrast (opaque backings).
