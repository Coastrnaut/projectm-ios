# Research: UIX-001 Guided First Scene

## UIX-001-D1 Presentation: an overlay in the root view, not a sheet or full-screen cover

- **Decision**: RootView puts the tutorial in a `ZStack` above the current screen (opaque background,
  `.accessibilityAddTraits(.isModal)`, no `.transition` and no `withAnimation`).
- **Rationale**: a `fullScreenCover` slides in (Reduce Motion only shortens it) and cannot be
  presented while the Settings sheet is still dismissing; the overlay has no animation at all and
  works over the chooser and the visualizer alike. The modal trait keeps VoiceOver inside it.
- **Alternatives**: `fullScreenCover` with `transaction.disablesAnimations` (presentation conflicts
  with the Settings sheet, still animated on some OS versions); a new `Screen` case (would stop the
  running visualizer when opened from Settings).

## UIX-001-D2 Stored state: one string key, set to pending when the notice is acknowledged

- **Decision**: `guide.firstScene` = `pending` | `finished` | `skipped`; absent = never offered. The
  notice's acknowledgement writes `pending` (only if absent); Play writes `finished`, Skip `skipped`.
  A launch offers the tutorial when the value is `pending`.
- **Rationale**: an install that acknowledged the notice before this version has no value and is
  never offered it (Clarifications); a kill mid-tutorial leaves `pending`, so it is offered again
  (User Story 2 scenario 3). It stores no choices.
- **Alternatives**: a Bool "done" flag (would offer it to every existing user after the update).

## UIX-001-D3 Harness rule: same shape as PERF-010-R12

- **Decision**: in DEBUG (or automation) builds, a launch with `XCTestConfigurationFilePath`,
  `PROJECTM_AUTORUN`, any `-uitest…` argument or `-autostart` never offers the tutorial by itself
  unless `-uitestGuidedFirstScene` is passed. `-uitestResetNotice` removes the key.
- **Rationale**: the 48 existing UI suites launch with `-uitestResetNotice` and tap the notice; they
  must not meet the tutorial (UIX-001-S5). The Settings row is never gated.

## UIX-001-D4 Play reuses existing paths

- **Decision**: Play sets `settings.visual`, `settings.glowEnabled` (spectra) or
  `texts.setMessage` (Text), calls `sceneAutosave.commitNow()` (which catches up with the change at
  once), then `select(.inAppPlayback)` only when `screen == .chooser`. On the visualizer the existing
  `onChange` hooks run `visualSettingsChanged()` / `glowSettingsChanged()`; the source is untouched.
- **Rationale**: one code path for settings, scene commit and the reference track; nothing new can
  start a sensor or listener.

## UIX-001-D5 Coexistence with PERF-010

- **Decision**: the launch rule returns false while `recovery.offer == .pending`; the state stays
  `pending` for a later launch. After the notice on a fresh install there is never a pending offer.
- **Rationale**: the recovery card must stay visible and unanswered questions must not stack.

## UIX-001-D6 Dynamic Type and touch targets

- **Decision**: each step is a `ScrollView` with the title, text and choices, and the buttons in a
  bottom `VStack` that is also inside the scroll content at accessibility sizes (`dynamicTypeSize
  .isAccessibilitySize`), so nothing is pushed off-screen; choices are full-width buttons with
  `.isSelected`; buttons use `.controlSize(.large)` (≥ 44 pt).
- **Rationale**: the notice view's pattern (FR-070) extended so buttons stay reachable at AX5.
