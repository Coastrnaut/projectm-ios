# Research: SHOW-014 Emergency Blackout

No `NEEDS CLARIFICATION` remained after the spec's Clarifications. These decisions record how.

## SHOW-014-D1: A visible corner button, not a gesture

- **Decision**: A SwiftUI `Button` with an SF Symbol (`eye.slash`) in a 44 × 44 pt frame,
  `.regularMaterial` circle, placed in the visualizer's bottom `VStack` in an `HStack { Spacer();
  button }` directly above the controls (or the source indicator). It sits above the full-screen
  tap area in z-order, so its tap never toggles the controls.
- **Rationale**: Visible and labeled for VoiceOver, Switch Control and Full Keyboard Access; one
  tap whatever the controls do; the trailing corner keeps it away from the screen's middle, where
  taps toggle the controls (FR-042). 44 pt is Apple's minimum comfortable target; larger would
  invite accidental taps and cover more of the picture.
- **Alternatives**: two-finger double tap on the visualization (undiscoverable, collides with
  VoiceOver's two-finger gestures); a top-corner button (the top trailing corner holds the opt-in
  performance overlay and the top stack holds badges); always-visible controls (cover the picture).

## SHOW-014-D2: Restore resumes the previous scene by construction

- **Decision**: Reuse OUT-010 unchanged. The blackout only sets each slot's cover opacity
  (`VisualSlotView.coverOpacity`); it never calls `place()` with a new visual, never touches the
  renderer, preset list, settings or audio source. Proof is a unit test with a real visual and the
  coordinator's `placements` counter, plus a UI test on the preset name and `sourceStarts`.
- **Rationale**: The acceptance is about identity (same scene), which the coordinator can state
  directly: the same `UIView` instance in the same slot and `placements` unchanged.
- **Alternatives**: a per-visual frame counter probe (touches six visuals for evidence that
  `visualRunning` already gives).

## SHOW-014-D3: The B key, toggling, attached to the shown button

- **Decision**: `.keyboardShortcut("b", modifiers: [])` on the emergency button (black out) and on
  the badge's Restore (restore). Exactly one of them exists in each phase where B should act
  (`offersEmergencyBlackout` and `offersRestore` are disjoint), so there is never a duplicate key
  command. During "restore waiting" neither exists, so B does nothing.
- **Rationale**: Presentation-app convention (B for black). SwiftUI routes key commands through the
  responder chain, so a focused text field keeps B, and a presented sheet takes the keyboard.
- **Alternatives**: Escape (cancel semantics, dismisses sheets); ⌘B (two keys); a `UIKeyCommand` on
  the window (app-wide, steals B from text fields).
- **Testability**: XCUITest `typeKey("b", modifierFlags: [])` on the simulator sends a hardware
  key event; the UI test uses it on the iPhone simulator.

## SHOW-014-D4: Recording and Save Frame

- **Decision**: No change. Both gates read `blackoutPhase == .live` (AppCoordinator's contexts
  for `FrameCaptureCoordinator` and `VideoRecordingCoordinator`), so the emergency path, which
  calls the same `setBlackout(true)`, refuses Save Frame and stops a recording exactly as OUT-010's
  Black out (REC-001, REC-003 tests cover the gates).
