# Research: ACC-004 VoiceOver Scene Browser

## D1 — System accessibility audit in UI tests

- **Decision**: `XCUIApplication.performAccessibilityAudit(for:_:)` (XCUIAutomation, iOS 17+) with
  `.sufficientElementDescription`, `.hitRegion`, `.contrast`, `.dynamicType`, `.trait`. The issue
  handler returns `true` (ignore) only for an issue matching a documented filter entry (type plus
  element identifier or label); everything else fails the test with the issue's
  `compactDescription` and element.
- **Rationale**: it is Apple's own automated check of what VoiceOver and Dynamic Type need, runs in
  the existing XCUITest target and needs no device.
- **Alternatives**: `.all` (adds text-clipped, element-detection, action and parent/child checks;
  text clipping at large sizes is QA-009's, the others produce many system-owned findings in
  sheets); hand-written tree walks only (misses contrast and hit regions).

## D2 — Declared primary controls

- **Decision**: a list per screen in the suite (contract C2) of identifier plus expected element
  type (`buttons`, `cells`, `staticTexts`, `searchFields`, …); the check asserts existence, a
  non-empty `label`, and that it is hittable after `app.reveal`.
- **Rationale**: identifiers are stable and already used everywhere; the element type is how
  XCUITest exposes the button trait.

## D3 — Announcement rate rule

- **Decision**: per kind, leading plus trailing over 1.0 s; identical text within 2.0 s dropped
  (spec Clarification 1). The rule is a pure value with times as input; the announcer schedules the
  trailing post with a main-actor `Task.sleep` and uses `ProcessInfo.systemUptime` (monotonic).
- **Rationale**: immediate feedback for single actions, the final state after a burst, no queue of
  stale names; testable without wall-clock assertions.
- **Alternatives**: `UIAccessibility` announcement queueing attributes (`accessibilitySpeechQueueAnnouncement`)
  only order speech, they do not coalesce; a global window would let a preset burst hide a blackout.

## D4 — Which existing swipe actions VoiceOver already exposes

- **Decision**: SwiftUI `List` swipe actions and `onDelete` are exposed by iOS as VoiceOver custom
  actions; they are not duplicated (Clarification 3). The app adds the actions with no touch-free
  path: cue Move Up / Move Down, preset favorite.
- **Verification**: the device pass (ACC-004-T12) confirms the rotor contents on D1; XCUITest cannot
  list custom actions.

## D5 — Contrast over the live visualization

- **Decision**: the controls sit on `.ultraThinMaterial`; findings whose element is text drawn over
  the live visualization (outside any app surface) may be filtered per element with that reason;
  findings on the app's own sheets and lists may not.
- **Rationale**: the audit samples pixels behind text; a moving preset makes the result
  nondeterministic. Triage decides per issue at implementation (contract C3 lists the outcome).
