# Feature Specification: UIX-001 Guided First Scene

**Feature Branch**: `feature/uix-001` (spec directory `075-uix-001-guided-first-scene`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement UIX-001 (Guided first scene) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Create a complete playable scene
through a short local tutorial." Acceptance, verbatim: "New user can finish with no account or network
access." P0, effort M, depends on SCN-001. Verification: SwiftUI UI tests + simulator."

Identifiers in this feature carry the roadmap ID: requirements `UIX-001-R1…`, success criteria
`UIX-001-S1…`, tasks `UIX-001-T01…`. Other features' IDs are cited as they are: FR-071 (the
photosensitivity notice), FR-002 (no source starts before the user picks one), VIS-001/VIS-002
(Circular and Linear Spectrum), FX-001 (glow), MED-009 (Text visual), SCN-002 (scene autosave),
PERF-010 (session recovery offer), SHOW-001 (cue list), OSC-001 (OSC receiver, off by default),
UIX-014 (offline help, later), UIX-015 (permission explainer, later; it owns every permission
explanation).

## Baseline: what a new user meets today (audit of 2026-11-13, commit `1e3ed83`)

| Step | Today | Gap for this row |
|---|---|---|
| First launch | The photosensitivity notice (FR-071), then the source chooser (System/App Capture, Microphone, In-App Playback with the built-in reference track, Your Audio, Diagnostics). | Nothing explains what a "scene" is or how to make one. |
| Sound | The user must know that In-App Playback needs no permission; Microphone shows its explainer and then the system prompt; System/App Capture shows the system picker. | A new user may hit a permission prompt or a system picker before seeing anything. |
| Visual | projectM starts; the other visuals (Circular/Linear Spectrum, Camera, Photo, Video, Text) are in Settings › Visual, reachable only through the hidden controls. | The look choices are hidden. |
| Look | Glow, bars and the Text message are in Settings. | Same. |
| Keeping it | SCN-002 commits the scene when the visual changes or Settings closes; restored on the next launch. | Nothing tells the user the scene is kept. |
| Accounts, network | The app has no accounts; its only network traffic is the optional App Store purchase and the optional OSC receiver (off by default). | None; the tutorial must keep it so. |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A new user makes and plays a first scene in a few taps (Priority: P1)

After acknowledging the photosensitivity notice on a fresh install, the user is guided through a short
local tutorial: what it will do, the sound (the built-in track, no permission), a visual, one look
setting, then **Play**. The visualizer starts with that scene, and the scene is kept: it is still the
shown scene after the app is closed and opened again. No account, sign-in, internet connection or
permission prompt is involved at any point.

**Why this priority**: This is the row's observable behavior and acceptance.

**Independent Test**: On a fresh install with no network, acknowledge the notice, go through every
tutorial step choosing Circular Spectrum with glow on, tap Play: the visualizer runs with the built-in
track, the scene is committed, no permission alert appeared, the OSC listener is off; relaunch: the
tutorial does not reappear and the restored scene is Circular Spectrum with glow.

**Acceptance Scenarios**:

1. **Given** a fresh install, **When** the user acknowledges the notice, **Then** the tutorial's first
   step is shown instead of the bare source chooser.
2. **Given** the tutorial, **When** the user completes every step and taps Play, **Then** the built-in
   track plays, the chosen visual runs with the chosen look, and the scene is committed.
3. **Given** the tutorial was finished, **When** the app is relaunched, **Then** the tutorial is not
   shown and the committed scene is restored.
4. **Given** any step, **When** the user goes through it, **Then** no permission prompt, system picker,
   sign-in or network access occurs.

### User Story 2 - I can skip it at any step and it never nags (Priority: P1)

A user who does not want the tutorial taps **Skip** on any step and lands on the normal source chooser
with nothing started. The tutorial is not shown again on its own.

**Why this priority**: A tutorial that cannot be skipped, or that keeps coming back, is worse than none.

**Independent Test**: Fresh install, notice, Skip on step 2: the chooser is shown, no source started;
relaunch: the chooser is shown without the tutorial.

**Acceptance Scenarios**:

1. **Given** any tutorial step, **When** the user taps Skip, **Then** the tutorial closes, the source
   chooser (or the screen it was opened over) is shown, and nothing is started or changed.
2. **Given** the tutorial was skipped, **When** the app is relaunched, **Then** it is not shown.
3. **Given** the app is closed in the middle of the tutorial (never finished or skipped), **When** it
   is relaunched, **Then** the tutorial is offered again from its first step.

### User Story 3 - I can open it again from Settings (Priority: P2)

Settings has a **Guided first scene** row. It opens the same tutorial; when the user finishes it while
a sound is already playing, the new visual and look are applied without touching the sound.

**Why this priority**: Lets anyone who skipped it, or existing users after an update, try it later.

**Independent Test**: With the visualizer running, open Settings › Guided first scene, finish with
Linear Spectrum: the visual changes, the source is not restarted.

**Acceptance Scenarios**:

1. **Given** Settings, **When** the user taps Guided first scene, **Then** Settings closes and the
   tutorial's first step is shown.
2. **Given** the tutorial was opened while a source runs, **When** the user finishes it, **Then** the
   chosen visual and look are applied and committed, and the running source is not restarted.
3. **Given** the tutorial was opened from the chooser (nothing playing), **When** the user finishes it,
   **Then** the built-in track starts as in User Story 1.

### User Story 4 - The tutorial is usable with VoiceOver, large text and Reduce Motion (Priority: P2)

Every step reads in order with VoiceOver (a heading, the explanation, labelled choices with their
selected state, then the buttons). At the largest accessibility text size nothing is cut off: text
wraps and the step scrolls, and every button can be reached and tapped. Nothing in the tutorial
animates.

**Why this priority**: The first experience must work for everyone.

**Independent Test**: Run the tutorial at the largest accessibility text size: every step's primary
button can be scrolled to and tapped.

**Acceptance Scenarios**:

1. **Given** the largest accessibility text size, **When** each step is shown, **Then** its primary
   button is reachable by scrolling and tappable, and no text is truncated.
2. **Given** VoiceOver, **When** a step appears, **Then** its title is a heading and every control has
   a label (and a selected state for choices).
3. **Given** Reduce Motion (or not), **When** the user moves between steps, **Then** there is no
   animated transition.

### Edge Cases

- The PERF-010 recovery offer is pending at launch (the previous session ended abnormally): the
  tutorial is not shown on that launch (the offer must not be covered or competed with); it stays
  pending for a later launch or Settings.
- Existing users updating to this version (the notice was acknowledged before): the tutorial is not
  shown by itself; Settings can open it.
- The chosen visual cannot be created on this device (VIS-001-R16): the existing fallback to projectM
  with its notice applies; the tutorial still finishes.
- The Text step's message is left empty: the Text visual shows the spectrum without text (MED-009);
  Play is still allowed.
- The user wants Microphone, System/App Capture, Camera, Photo or Video: the tutorial says these are
  in the source list or Settings and ask for permission or a picker there; it offers only
  permission-free choices itself.
- The app is backgrounded during the tutorial: nothing runs (no source has started); on return the
  same step is shown.
- UI tests: existing suites launch with `-uitestResetNotice` and `-autostart`; the tutorial must not
  appear in them unless a test asks for it.
- Glow cannot be built on this device (FX-001-R13): the existing notice applies; the scene still plays.

## Requirements *(mandatory)*

### Functional Requirements

- **UIX-001-R1 When it is offered**: The tutorial is offered once per install: right after the user
  acknowledges the photosensitivity notice on a fresh install, and again on later launches until it is
  finished or skipped. It is never shown by itself to an install that acknowledged the notice before
  this feature, nor while the PERF-010 recovery offer is pending.
- **UIX-001-R2 Steps**: The tutorial has five short steps, in order: (1) Welcome: what it does, that it
  takes under a minute, needs no account or internet, and can be skipped; (2) Sound: the built-in
  track, which needs no permission (with a note on where the other sources are and that they ask
  first); (3) Visual: a choice of permission-free visuals; (4) Look: one setting for the chosen visual;
  (5) Play: a summary of the scene and the Play button.
- **UIX-001-R3 Choices**: Visual offers Circular Spectrum (preselected), Linear Spectrum and Text. Look
  offers Glow on/off for the spectra (preselected on) and the message for Text (prefilled with a short
  default). Nothing that needs a permission, a system picker or a file is offered.
- **UIX-001-R4 Navigation**: Every step has a primary button (Next, or Play on the last step) and
  Skip; steps 2-5 also have Back. Back keeps the choices made.
- **UIX-001-R5 Finish (Play)**: Play applies the chosen visual and look through the same settings
  Settings uses, commits the scene at once (SCN-002), marks the tutorial finished, closes it, and, if
  no source is running, starts In-App Playback with the built-in track (the same path as the chooser's
  In-App Playback row). A running source is never restarted or changed.
- **UIX-001-R6 Skip**: Skip marks the tutorial finished-by-skip, closes it, and changes nothing else:
  no setting, no scene, no source.
- **UIX-001-R7 Stored state**: One local setting records the tutorial's state (offered and pending;
  finished or skipped). Absent means "never offered". It is reset by the UI-test reset and removed with
  the app. It holds no choices, times or content.
- **UIX-001-R8 Re-open**: Settings has a "Guided first scene" row that closes Settings and opens the
  tutorial from step 1 with the default choices. Finishing or skipping it there behaves as R5/R6.
- **UIX-001-R9 Offline and accountless**: The tutorial and everything it starts use only on-device
  content. It makes no network request, opens no listener (the OSC receiver keeps its own setting,
  off by default), and never shows a sign-in or account screen.
- **UIX-001-R10 No permission requests**: The tutorial never triggers a camera, microphone, photo
  library, screen capture or local network prompt. Explaining those permissions is UIX-015's job.
- **UIX-001-R11 Accessibility**: Each step's title is a heading; every control has a label and, for
  choices, a selected state; reading order is title, text, choices, buttons. Text wraps and each step
  scrolls at every Dynamic Type size including the accessibility sizes; buttons keep at least a 44 pt
  touch target. The tutorial covers the screen and is modal to VoiceOver.
- **UIX-001-R12 No motion**: Step changes and opening or closing the tutorial are not animated, so
  Reduce Motion is respected without a separate path.
- **UIX-001-R13 Test harness**: In DEBUG builds a launch from a UI test, unit-test host or automation
  run (any `-uitest…` or `-autostart` argument, `XCTestConfigurationFilePath`, `PROJECTM_AUTORUN`)
  never offers the tutorial by itself unless `-uitestGuidedFirstScene` is passed; Release builds always
  follow R1. The Settings row works in every build.
- **UIX-001-R14 Privacy policy**: The privacy policy's list of stored values names the tutorial
  state.

### Key Entities

- **Tutorial state** (stored): never offered; pending (offered, not finished); finished; skipped.
- **Tutorial session** (in memory): the current step and the draft choices (visual, glow, message).
- **Guided scene**: what Play applies: the built-in track as the sound (only when nothing plays), the
  visual, and its one look setting.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **UIX-001-S1**: A new user with no network and no account can go from the notice to a running,
  committed scene through the tutorial in 5 taps when the defaults are kept (Next four times, then
  Play), with no permission prompt.
- **UIX-001-S2**: After finishing or skipping, the tutorial is shown by itself on 0 later launches.
- **UIX-001-S3**: Skip is available on 5 of 5 steps and changes no setting or scene.
- **UIX-001-S4**: At the largest accessibility text size, 5 of 5 steps' primary buttons can be reached
  and tapped, with no truncated text.
- **UIX-001-S5**: Existing UI suites run unchanged: the tutorial appears in 0 of their launches.
- **UIX-001-S6**: The finished scene is the one restored on the next launch in 100% of test runs.

## Assumptions

- "A complete playable scene" means a sound, a visual and its look, applied and committed by SCN-002
  so it plays now and comes back after relaunch. Adding it as a show cue (SHOW-001) is not part of the
  tutorial; Settings › Show can add it.
- SCN-001 (the scene document) and SCN-002 (autosave) exist and are what "scene" means here.
- The roadmap's `{device}` verification (first launch on D1 in Airplane Mode, a VoiceOver pass) is done
  by the owner; simulator results are not device evidence (Constitution X).
- The app has no accounts and no networking code paths outside StoreKit and the OSC receiver
  (Constitution; compliance check), so "no network access" is preserved by not touching either.
