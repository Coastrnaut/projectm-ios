# Contract: Guided first scene UI and test hooks

## G1 Accessibility identifiers (stable; used by UI tests)

| Element | Identifier |
|---|---|
| The tutorial container (modal; XCUITest lists it as an alert) | `guidedFirstScene` |
| Each step's title (a heading) | `guide.step.<step>`: `welcome`, `sound`, `visual`, `look`, `play` |
| Primary button (Next / Play) | `guide.next` (label "Next", or "Play" on the last step) |
| Back | `guide.back` (steps 2-5) |
| Skip | `guide.skip` (every step) |
| Visual choices | `guide.visual.circularSpectrum`, `guide.visual.linearSpectrum`, `guide.visual.text` (selected trait on the chosen one) |
| Glow toggle (spectra) | `guide.glow` |
| Message field (Text) | `guide.message` |
| Settings row | `guidedFirstSceneButton` |

## G2 Launch arguments (DEBUG)

- `-uitestGuidedFirstScene`: lets a harness launch offer the tutorial by the normal rule (UIX-001-R13).
- `-uitestResetNotice` (existing): also removes `guide.firstScene`.

## G3 Coordinator surface (app target)

- `GuidedFirstSceneCoordinator.isPresented`, `.flow` (step and draft), `.state`.
- `noticeAcknowledged()` → writes `pending` when absent; presents when the launch rule allows.
- `presentAtLaunchIfDue(recoveryPending:)`; `open()` (Settings, never gated); `skip()`;
  `finish() -> GuidedScene` (writes `finished`, closes).
- `AppCoordinator.finishGuidedFirstScene()`: applies the scene, commits it, starts the reference
  track only from the chooser. `AppCoordinator.openGuidedFirstScene()`: closes Settings, opens.

## G4 Effects (what may and may not happen)

- May: change `settings.visual`, `settings.glowEnabled`, the Text message; commit the scene; start
  In-App Playback with the reference track from the chooser.
- Must not: request any permission, open a picker, start Microphone or System/App Capture, start the
  camera, change `settings.osc.*`, add show cues, make a network request.
