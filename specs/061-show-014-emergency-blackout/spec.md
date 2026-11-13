# Feature Specification: SHOW-014 Emergency Blackout

**Feature Branch**: `feature/show-014` (spec directory `061-show-014-emergency-blackout`)

**Created**: 2026-11-13

**Status**: Implemented 2026-11-13 (SHOW-014-T01-T11, T13 verified on the Mac: host and iOS 27.2 simulator; T12 `{device}` open)

**Input**: User description: "Implement SHOW-014 (Emergency blackout) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Provide persistent one-tap black
output without stopping session." Acceptance, verbatim: "Blackout immediately renders black and
restore resumes previous scene." P0, size M. Builds on OUT-010 (integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `SHOW-014-R1…`, success criteria `SHOW-014-S1…`, tasks `SHOW-014-T01…`. Other
features' requirements are cited by their own IDs: OUT-010-R1 to R13 (output blackout), OUT-001-R1
to R12 (external display scene), REC-001 (Save Frame), REC-003 (video recording), FR-065 (what the
app may store), FR-070 (accessibility), FR-082 (controls), FR-042 (tap toggles the controls).

## Baseline: what exists today (audit of 2026-11-13, commit `9ee8394`)

The row's gap status is "Gap candidate; re-audit at implementation". OUT-010
(`specs/051-out-010-output-blackout-isolation`, ADR-0023 decision 8) already delivers most of the
row. Mapping the row's acceptance onto existing, passing tests:

| Acceptance part | Already true (OUT-010) | Evidence (test) |
|---|---|---|
| "Blackout immediately renders black" | The slot holding the visual is opaque black, without animation, before `setBlackout(true)` returns, so the next composited frame is black (OUT-010-R2, R3), on the device and on an external display. | `OutputBlackoutCoordinatorTests.testBlackOutCoversTheDeviceOutputInsideTheCall`, `testBlackOutCoversTheExternalOutputInsideTheCall`; `OutputBlackoutTests` (PresentationLifecycle); `OutputBlackoutUITests` (probe `outputBlackout` = `black`) |
| "without stopping session" | The audio source and the visual keep running hidden; `sourceStarts` stays 1 (OUT-010-R4). | `OutputBlackoutUITests` (`sourceStarts` = 1, `visualRunning` = yes after restore) |
| "persistent" | A badge "Output blacked out" with Restore stays while the controls hide (OUT-010-R9). | `OutputBlackoutUITests` (`blackoutBadge`) |
| "restore resumes previous scene" | Restore fades the same, still-running visual in (1 s, 4 s with Reduce flashing), never restarting it; the blackout follows connect, disconnect, visual change and re-entry (OUT-010-R6 to R8). | `OutputBlackoutCoordinatorTests.testRestoreFadesTheCoverOverFrameTime`, `testTheBlackoutFollowsConnectDisconnectReentryAndVisualChanges` |
| No external display | The device's visualization goes black; controls stay (OUT-010-R1). | `testBlackOutCoversTheDeviceOutputInsideTheCall` |

Gaps for an *emergency* control in a live performance:

| Gap | Today |
|---|---|
| One tap from any state | Black out lives only in the auto-hiding controls (FR-082). With the controls hidden (the normal state during a show) it takes two taps: one to show the controls, one on Black out. |
| Hardware keyboard | No keyboard shortcut; iPad performers often drive the app from a keyboard. |
| Proof that restore resumes the same scene | Not asserted end to end: no test checks that the preset or visual shown after restore is the one shown before, or that the visual's view was not replaced or re-placed. |
| Recording and Save Frame during a blackout | Implemented (REC-003 stops a recording; REC-001 refuses Save Frame) but not stated as the emergency control's contract. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: What makes the blackout one tap from any state? → A: A persistent emergency Black out button on the device screen, always shown on the visualizer while the output is live or fading in, with or without the controls, at the bottom trailing corner just above the controls (or the source indicator when the controls are hidden). It is a visible button with a VoiceOver label, never a hidden gesture: a gesture (two-finger double tap) is undiscoverable, conflicts with VoiceOver's own gestures and cannot be found by Switch Control. Rejected: a gesture on the visualization (accessibility, accidental triggers while tapping to show controls); keeping the controls always visible (covers the visualization on the device).
- Q: Does the emergency button also restore? → A: No. It only blacks out, and it is not shown while the output is blacked out or waiting to restore; the persistent OUT-010 badge at the top with its Restore button is the one-tap restore. A corner button that toggled would let a second accidental tap reveal the picture during an emergency; restoring is a deliberate act at a different place. Rejected: a toggle in the corner (an accidental reveal).
- Q: How are accidental taps made unlikely without a confirmation? → A: Placement and size, not a confirmation. The button sits in the corner, away from the middle of the screen where the user taps to show or hide the controls, it is a compact 44 × 44 pt target (the minimum comfortable touch size, not larger), and a blackout is the safe direction: an accidental one is noticed at once (the badge) and undone in one tap with a flash-safe fade. A confirmation, long press or double tap would slow the emergency use (OUT-010 Clarifications). Rejected: long press, confirmation dialog, double tap.
- Q: Is there a hardware keyboard shortcut, and which key? → A: Yes: B, with no modifier, toggles the blackout (blacks out while live or fading in; restores while blacked out), the convention of presentation apps (Keynote and PowerPoint use B for a black screen and B again to return). It is attached to the emergency button and to the badge's Restore, so it works exactly when those buttons are shown, and only on the visualizer; a text field with focus keeps its typing. Escape is rejected (it dismisses sheets and means "cancel"); a ⌘ combination is rejected (two keys in an emergency).
- Q: What does "restore resumes the previous scene" mean exactly, and how is it proved? → A: After restore, the same visual is shown (the same visual choice and, for projectM, the same preset), the visual's view was never replaced or moved (no placement change), the visual kept drawing while black, its settings (glow, spectrum options) are unchanged, and the audio source was started once. Proved by a coordinator unit test with a real visual and by a UI test that compares the preset name and the probes before and after. A frame counter is not added: the existing `visualRunning` probe (frames per second above 0 while black and after restore) shows that frames continued. Rejected: a new per-visual frame counter (touches every visual for the same evidence).
- Q: How do recording and Save Frame behave with the emergency blackout? → A: Exactly as with OUT-010's Black out, because the emergency button and the B key call the same blackout: an active recording stops and keeps what was recorded with a notice (REC-003 Clarifications: never record what the user chose to hide), and Save Frame is refused while blacked out, waiting or fading in (REC-001). Restore never restarts a recording. Rejected: pausing a recording across the blackout (REC-003 rejected it).
- Q: When the device screen itself is what the audience sees (no external display), should the emergency button hide or dim so it is not seen in the show? → A: It stays shown at full contrast, like the source-and-state indicator that is already always visible (FR-040): an emergency control that disappears is no emergency control, and a dimmed one fails contrast for low-vision users (FR-070). It is small (44 × 44 pt, an icon on the same material as the other badges). Performers who need a clean device picture use an external display, where the button never appears (R4). Rejected: auto-dim after a delay (contrast, and it hides the control exactly when it is not being looked at); hide without a display (removes the emergency path on the device).
- Q: Does the B key work while a sheet (Settings, preset browser, queue) is open? → A: No. A presented sheet takes the keyboard, and its text fields need B; the external display keeps showing the visualization meanwhile (OUT-001-R1), and the sheet's Done returns to the visualizer, where B and the button work again. This is stated, not worked around. Rejected: an app-wide key command (would steal B from text fields such as the text overlay editor and preset names).
- Q: Is the emergency blackout logged or counted separately from OUT-010's Black out? → A: No new record: OUT-010 already logs each phase change (no user data, nothing stored, FR-065), and both entry points produce the same phases. A separate entry-point log adds nothing a performer needs. Rejected: a counter in Diagnostics (stores usage; not needed for any criterion).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Black out with one tap while the controls are hidden (Priority: P1)

During a show the controls are hidden. Something must not be seen. The performer taps the small
Black out button in the corner of the device; the output (the projector, or the device's own
visualization without a display) is black at the next frame. The music keeps playing.

**Why this priority**: It is the row's behavior: persistent, one-tap black output.

**Independent Test**: With the controls hidden, one tap on the emergency button; the output probe
reads black, the badge shows, the audio source was started once; with and without a simulated
external display.

**Acceptance Scenarios**:

1. **Given** the visualizer with the controls hidden and the output live, **When** the user taps the
   emergency Black out button once, **Then** the output is black at the next frame and the controls
   stay hidden.
2. **Given** an external display shows the visualization, **When** the user taps the emergency
   button, **Then** the external display is black and the button never appears on it.
3. **Given** no external display, **When** the user taps the emergency button, **Then** the
   device's visualization is black and the device's controls and badge stay usable.
4. **Given** the controls are shown, **Then** the emergency button is still shown at the same
   trailing edge, directly above the controls, and works the same way.

---

### User Story 2 - Restore resumes the previous scene (Priority: P1)

The performer restores the output. The same visual and preset return, fading in from the
still-running visualization; nothing was restarted or replaced.

**Why this priority**: The row's acceptance: "restore resumes previous scene".

**Independent Test**: A coordinator test with a real visual: blackout then restore keeps the same
view in the same slot, running, with unchanged settings and no new placement. A UI test reads the
preset name before and after.

**Acceptance Scenarios**:

1. **Given** a preset is shown, **When** the user blacks out and restores, **Then** the same preset
   is shown and the audio source was started once.
2. **Given** a native visual is shown, **When** the user blacks out and restores, **Then** the same
   visual is shown, it drew frames while black, and its settings are unchanged.

---

### User Story 3 - Keyboard shortcut (Priority: P2)

An iPad performer with a hardware keyboard presses B to black out and B again to restore.

**Why this priority**: Cheap, and the fastest emergency path with a keyboard; not every performer
has one.

**Independent Test**: A UI test sends the B key: the output goes black; B again restores.

**Acceptance Scenarios**:

1. **Given** the visualizer with the output live, **When** the user presses B, **Then** the output
   is black at the next frame.
2. **Given** the output is blacked out, **When** the user presses B, **Then** the output restores
   with the flash-safe fade.

### Edge Cases

- Tapping the emergency button during a restore fade: black at the next frame (OUT-010-R6); the
  button is shown during the fade for exactly this.
- Tapping it twice quickly: the second tap lands nowhere (the button is hidden once blacked out), so
  it cannot restore by accident.
- Pressing B while a restore waits for the restore spacing: nothing (no button carries the key then);
  the restore already requested proceeds.
- A recording is running: it stops and keeps what was recorded (REC-003); Save Frame is refused
  until the output is live (REC-001).
- Paused visual: blackout and restore work; restore shows the paused frame.
- VoiceOver: the button is reachable without showing the controls and reads "Emergency black out";
  its hint says the output goes black at once and Restore is at the top.
- Large accessibility text sizes: the button keeps its size and place (an icon), so it never
  pushes the controls off screen.
- Sheets (Settings, preset browser) cover the visualizer: the emergency button is under the sheet
  and the B key goes to the sheet; the sheet's own content is not the show output (OUT-001-R1 keeps
  the external display showing the visualization), and closing the sheet returns to the button.
- No external display (the device screen is the output): the button stays shown at full contrast.

## Requirements *(mandatory)*

### Functional Requirements

- **SHOW-014-R1**: The visualizer MUST show a persistent emergency Black out button on the device
  screen while the output is live or fading in, whether the controls are shown or hidden, at the
  bottom trailing edge of the screen above the controls or the source indicator.
- **SHOW-014-R2**: One tap on the emergency button MUST black out the current output with the same
  behavior as OUT-010's Black out (OUT-010-R2 to R5, R8): black at the next frame, nothing restarted,
  controls and audio untouched, on an external display or on the device without one. It MUST NOT
  show the controls or require a confirmation.
- **SHOW-014-R3**: The emergency button MUST only black out. While the output is blacked out or
  waiting to restore it is not shown, and restore is offered by OUT-010's persistent badge (OUT-010-R9).
- **SHOW-014-R4**: The emergency button MUST appear only on the device (never on the external
  display, OUT-001-R1) and only on the visualizer.
- **SHOW-014-R5**: The emergency button MUST be a 44 × 44 pt touch target in the corner, away from
  the screen's middle, with an accessibility label "Emergency black out", a hint, and an identifier
  (FR-070).
- **SHOW-014-R6**: The B key on a hardware keyboard, with no modifier, MUST black out while the
  emergency button is shown and restore while the badge's Restore is shown; it does nothing while a
  sheet is presented over the visualizer.
- **SHOW-014-R7**: Restore MUST resume the previous scene: the same visual choice, the same preset,
  the same visual view in the same slot with no new placement, the visual's settings unchanged, frames
  drawn throughout, and the audio source started once.
- **SHOW-014-R8**: During an emergency blackout, a recording MUST stop and keep its file (REC-003),
  and Save Frame MUST be refused (REC-001); restore MUST NOT restart a recording.
  Satisfied by construction (SHOW-014-T13): the emergency button and the B key call the same
  `ExternalDisplayCoordinator.setBlackout(true)`, and both gates read `blackoutPhase == .live` in
  AppCoordinator's `frameCapture` and `videoRecording` contexts. Covered by
  `FrameCaptureAppTests.testRefusalsCaptureNothing`, `testAVisualChangeOrBlackoutCancelsThePendingCapture`,
  `VideoRecordingAppTests.testBlackoutStops`, `FrameColorConversionTests.testGateRefusalsInPriorityOrder`
  and `RecordingRulesTests.testRefusalOrder`.
- **SHOW-014-R9**: The emergency control MUST store nothing and add no log or counter beyond
  OUT-010's phase log (FR-065); a launch starts live.
- **SHOW-014-R10**: Only public, documented platform APIs (Constitution I); builds for iOS 26 and 27.

### Key Entities

- **Emergency control visibility**: shown when the screen is the visualizer and the output blackout
  phase is live or fading in; a pure function of those two values.
- **Output blackout state**: OUT-010's (live, blacked out, restore waiting, fading in).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SHOW-014-S1**: With the controls hidden, one tap blacks out the output (100% of runs; simulator
  UI test with and without a simulated external display; the output slot is black before the tap's
  handling returns, OUT-010-S1).
- **SHOW-014-S2**: After blackout and restore, the preset or visual shown equals the one before, the
  visual's view is the same and was not re-placed, and the audio source was started once (100%).
- **SHOW-014-S3**: The B key blacks out and restores (simulator UI test with a hardware keyboard
  event; device check on D2 with a keyboard).
- **SHOW-014-S4**: On D1/D2 with an external display, the emergency button blacks out the external
  output at the next frame (device stage, owner's hands).

## Assumptions

- OUT-010's blackout model, covers, badge and fade are reused unchanged; this feature adds an entry
  point, a shortcut and proof.
- The roadmap's dependency CMP-001 (compositor) is integrated; the blackout covers the composited
  output slot, so every visual (projectM, native, Camera, Photo, Video, Text) is covered.
- SHOW-015 (performance lock) will keep this control available; nothing here blocks that.
