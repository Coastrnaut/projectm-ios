# Research: ACC-001 Reduce Motion Mode

## D1 — Source of truth for the Reduce Motion state

- **Decision**: `UIAccessibility.isReduceMotionEnabled`, mirrored into the existing
  `AppSettings.systemReduceMotion` (FR-072 already keeps it), updated by
  `UIAccessibility.reduceMotionStatusDidChangeNotification` observed at the app root, and re-read
  when the scene becomes active.
- **Rationale**: one value already drives Reduce flashing's default; reading it from the
  observable settings makes every SwiftUI view that uses it re-render at once (R3). The observer was
  attached to `VisualizerView` only, so a change on the chooser was missed until the next
  activation; moving it to the root fixes that for Reduce flashing too.
- **Alternatives**: SwiftUI `@Environment(\.accessibilityReduceMotion)` in each view (updates live,
  but cannot be overridden by a UI test launch argument, and would be a second source of truth beside
  `systemReduceMotion`); polling (wasteful, not immediate).

## D2 — Instant, not cross-fade

- **Decision**: decorative animations become nil (instant) while Reduce Motion is on.
- **Rationale**: Apple's Human Interface Guidelines (Accessibility → Motion) ask apps to reduce or
  replace motion, and suggest cross-fades in place of sliding or zooming. Every decorative transition
  here is already a 0.2 s opacity fade, so the only meaningful reduction is removing it (Clarifications
  Q2).
- **Alternatives**: keep fades; shorten them.

## D3 — Inventory classification

See spec Baseline A1-A10. Decorative: A1-A3 (one animation on the overlay stack drives all three).
Safety: A4 (PERF-014 placeholder, SwiftUI), A5 (blackout restore, renderer-side; not a SwiftUI
animation, governed by Reduce flashing). Already instant: A6, A7. System-owned: A8. Content: A9.

## D4 — Visual content stays controllable

- **Decision**: Reduce Motion changes no visual parameter and never pauses the visualization;
  Reduce flashing's default keeps following it (FR-072). ACC-012 will add motion-intensity limits.
- **Rationale**: the row says "keeping visual content controllable"; content motion is the product.

## D5 — Testing "immediately" on the simulator

- **Decision**: DEBUG launch argument `-uitestReduceMotion YES|NO` sets the starting state; a hidden
  DEBUG button `simulateReduceMotionToggle` flips it through `AppCoordinator.systemReduceMotionChanged`,
  the handler the system notification calls; DEBUG probe `motionProbe` reports the last controls
  transition's configured duration.
- **Rationale**: XCUITest cannot change system accessibility settings. The probe reports the
  duration the view was given (the same `MotionPolicy` value), not a measured time, so no wall-clock
  assertion is needed.
- **Real path tried**: whether `xcrun simctl spawn <udid> defaults write com.apple.Accessibility
  ReduceMotionEnabled -bool YES` reaches a running app on the iOS 27.2 simulator is tried during
  implementation (ACC-001-T07) and the result is recorded here.

## D6 — Static check

- **Decision**: `scripts/check_motion_policy.py`, tested from `scripts/test_scripts.py` (runs in CI).
  Flags `withAnimation(`, `.animation(` and `UIView.animate` in app sources outside `MotionPolicy.swift`
  (contract C1); a line passes when it contains `reduceMotionAware(` or `MotionPolicy.`. Comments and strings are
  ignored.
- **Rationale**: cheap, no new tool, catches the two ways SwiftUI code introduces animation.
  `.transition(` needs an animated transaction, so it is covered indirectly. UIKit
  `UIView.animate` is also flagged (no current use) so a future UIKit animation must go through the
  policy (`MotionPolicy.seconds`).
- **Alternatives**: SwiftLint custom rule (new dependency); no check.
