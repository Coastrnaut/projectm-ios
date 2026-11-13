# Feature Specification: ACC-001 Reduce Motion Mode

**Feature Branch**: `feature/acc-001` (spec directory `080-acc-001-reduce-motion-mode`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement ACC-001 (Reduce motion mode) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Disable nonessential UI animations
while keeping visual content controllable." Acceptance, verbatim: "System reduce-motion toggle changes
editor transitions immediately." P0, size S, depends on UIX-001 (integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `ACC-001-R1…`, success criteria `ACC-001-S1…`, tasks `ACC-001-T01…`. Other features
are cited by their own IDs: FR-072 (Reduce flashing follows Reduce Motion by default), FR-042 (tap
toggles the controls), FR-070 (accessibility), UIX-001 (guided first scene), PERF-014 (render
placeholder), OUT-010 / SHOW-014 (blackout and its restore fade), CAM-012 (camera badge), OSC-007
(listener badge), ACC-002 (reduced-flash preset policy, done), ACC-012 (sensory safety profile,
later).

## Baseline: what exists today (audit of 2026-11-13, commit `7ec3fe5`)

The row's gap status is "Gap candidate; re-audit at implementation". A search of the app and every
package for `withAnimation`, `.animation(`, `.transition(`, `matchedGeometryEffect`, `UIView.animate`,
`UIViewPropertyAnimator`, `CATransaction`, Core Animation animations, `symbolEffect`,
`contentTransition`, phase/keyframe animators and programmatic scrolling finds this inventory:

| # | Where | What moves | Class |
|---|---|---|---|
| A1 | Visualizer: the controls overlay and the always-visible status indicator swap when the controls show or hide (tap, 5 s auto-hide) | 0.2 s ease-in-out cross-fade | **Decoration** (the editor/controls transition) |
| A2 | Visualizer top stack: OSC listener badge, recovery card, "Camera on" badge (CAM-012), blackout badge (OUT-010) | opacity transition, animated only when it coincides with A1 | **Decoration** (the badges' state change itself is information and stays) |
| A3 | Visualizer bottom stack: route explanation (AUD-007), show notice (SHOW-001), emergency Black out button (SHOW-014) | opacity transition, animated only with A1 | **Decoration** |
| A4 | Render placeholder (PERF-014-R10) | 0.5 s linear fade to and from black | **Safety** (one monotonic luminance change; flash safety, FX-019) |
| A5 | Blackout and its restore fade (OUT-010, SHOW-014), drawn by the renderer, length set by Reduce flashing | content fade | **Safety** |
| A6 | External display slot (OUT-001) | Core Animation actions already disabled | Already instant |
| A7 | Guided first scene (UIX-001) | animations already removed | Already instant |
| A8 | Sheets, navigation pushes, alerts, confirmation dialogs, share sheets, file pickers | system presentation | **System-owned** (iOS applies its own Reduce Motion adaptations) |
| A9 | Visual content: projectM presets, spectrum bars, glow, camera, photo, video, text visuals | the visualization | **Content** (governed by Reduce flashing and the visual settings, not by this row) |
| A10 | Diagnostics readouts that refresh periodically (performance overlay, DEBUG probes) | text updates, no motion | Not an animation |

Today nothing reads the system Reduce Motion setting except FR-072 (Reduce flashing's default). The
setting's change notification is observed only while the visualizer is on screen.

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the recommended, conservative, local-first option.

- Q: Should the app offer its own Reduce Motion switch, or only follow the system setting? → A: Follow the system setting only (`ACC-001-R1`). Apple's guidance is to honor the system preference, users set it once for every app, and ACC-012 (sensory safety profile) is where per-user limits will live. Rejected: an in-app switch with "Follow system" like Reduce flashing (a second source of truth for a UI-only preference; Reduce flashing has one because it protects against content, which iOS does not control).
- Q: With Reduce Motion on, should decorative transitions become instant or shorter cross-fades? → A: Instant (`ACC-001-R2`). Every decorative transition in the inventory is already a 0.2 s opacity fade, so a "replacement cross-fade" would change nothing; the row says "disable". Rejected: keeping the fades (no visible effect of the mode); shorter fades (arbitrary numbers, still motion).
- Q: Should the app replace the system's sheet, navigation and alert animations? → A: No; they stay system-managed (`ACC-001-R6`). iOS adapts its own presentations to Reduce Motion, and overriding them would need non-standard presentation code on every sheet. Rejected: presenting every sheet without animation (fights the platform, more code at many call sites, risks breaking interactive dismissal).
- Q: How is "immediately" proven on the simulator, where UI tests cannot change system settings? → A: Test builds accept a launch argument that sets the starting Reduce Motion state and a hidden test control that simulates a system change through the same path the system notification takes; the UI test reads a test-only probe with the last controls transition's duration (`ACC-001-R9`). Whether changing the simulator's accessibility defaults from the Mac reaches a running app is tried once and recorded in research; the device task (`ACC-001-S6`) is the real-toggle check. Rejected: relying on simulator defaults alone (undocumented, may not post the notification); no UI test (the row asks for accessibility UI verification).
- Q: Is a project check that flags new app animations practical, and where does it run? → A: Yes: a script check over the app's Swift sources, run with the other script tests (`python3 scripts/test_scripts.py`) and therefore in CI, that fails on any `withAnimation` or `.animation(` call outside the shared rule, except an allowlist of safety fades (`ACC-001-R7`). Transitions (`.transition(`) only animate inside an animation, so they need no check. Rejected: a lint rule in a new tool (new dependency); no check (the next feature would silently add motion).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Controls appear without motion (Priority: P1)

A viewer with vestibular sensitivity has Reduce Motion turned on in iOS Settings. They open the app,
start a source and tap the visualization: the controls appear at once, with no fade. A tap hides them
at once; after 5 s they disappear at once. The visualization keeps running exactly as before.

**Why this priority**: It is the row's behavior: nonessential UI animations are disabled.

**Independent Test**: Launch with Reduce Motion on, show and hide the controls, open and close
Settings; the app reports that every app-owned transition took no time, and the visualization is
still drawing.

**Acceptance Scenarios**:

1. **Given** Reduce Motion is on, **When** the controls show or hide (tap or auto-hide), **Then** the
   change is instant.
2. **Given** Reduce Motion is off, **When** the controls show or hide, **Then** they cross-fade as
   before (0.2 s).
3. **Given** Reduce Motion is on, **When** a status badge or notice appears or goes, **Then** it
   appears or goes at once; its text and announcement are unchanged.

---

### User Story 2 - Changing the system setting takes effect at once (Priority: P1)

The viewer is mid-session with the controls visible. They open Control Center or Settings, turn
Reduce Motion on and come back: the very next controls transition is instant, without relaunching or
touching any in-app setting. Turning it off restores the fade the same way.

**Why this priority**: It is the row's acceptance criterion ("changes editor transitions
immediately").

**Independent Test**: With the app running, change the Reduce Motion state; the next transition's
reported duration follows the new state.

**Acceptance Scenarios**:

1. **Given** the app is running with Reduce Motion off, **When** Reduce Motion is turned on, **Then**
   the next controls transition is instant, with no relaunch.
2. **Given** the change happens while the app shows the source chooser or a sheet, **When** the user
   reaches the visualizer, **Then** its transitions already follow the new state.
3. **Given** Reduce flashing is set to "Follow system", **When** Reduce Motion changes, **Then** Reduce
   flashing follows it as today (FR-072), independently of the transitions.

---

### User Story 3 - Safety fades and the visualization stay (Priority: P2)

With Reduce Motion on, the performer blacks out the output and restores it, and a visual that cannot
draw shows the "Visual unavailable" placeholder. The restore and the placeholder still fade, because
a sudden jump between black and a bright picture is a flash.

**Why this priority**: Removing a safety fade would make the app less safe for the very users who
asked for less motion.

**Independent Test**: With Reduce Motion on, the placeholder fade still lasts 0.5 s and the restore
fade keeps the length Reduce flashing gives it.

**Acceptance Scenarios**:

1. **Given** Reduce Motion is on, **When** the render placeholder shows, **Then** it fades in over
   0.5 s as before.
2. **Given** Reduce Motion is on, **When** the output is restored after a blackout, **Then** the
   restore fade's length is unchanged.
3. **Given** Reduce Motion is on, **When** the visualizer runs, **Then** the visualization keeps
   drawing and every visual setting keeps working.

### Edge Cases

- VoiceOver running: the controls already stay until hidden (FR-070); with Reduce Motion they still
  appear and go instantly, and nothing announced changes.
- The setting changes while the app is in the background: the next activation reads the current
  value.
- The setting changes during a running fade: the fade in flight finishes; the next transition
  follows the new state.
- A future view adds an animation: a project check flags any app animation that does not go through
  the shared reduce-motion rule, unless it is listed as a safety fade.

## Requirements *(mandatory)*

### Functional Requirements

- **ACC-001-R1**: The app MUST follow the system Reduce Motion setting; it offers no separate in-app
  switch for UI motion.
- **ACC-001-R2**: While Reduce Motion is on, every decorative app-owned UI transition (inventory
  A1-A3) MUST complete instantly; while it is off, they keep their current animation.
- **ACC-001-R3**: A change of the system setting MUST apply to the next transition without a
  relaunch, on every screen, and MUST be re-read when the app becomes active.
- **ACC-001-R4**: Safety fades (A4, A5) MUST keep their current timing whatever the Reduce Motion
  state; only Reduce flashing governs them.
- **ACC-001-R5**: The visualization (A9) MUST keep running and stay controllable through its
  existing settings; Reduce Motion changes no visual parameter. Reduce flashing keeps following
  Reduce Motion by default (FR-072).
- **ACC-001-R6**: System presentations (A8) MUST stay system-managed; the app adds no custom
  presentation animation.
- **ACC-001-R7**: All app-owned UI animation MUST go through one shared reduce-motion rule, and a
  project check MUST fail when an app animation bypasses it, except listed safety fades.
- **ACC-001-R8**: Text, accessibility labels, identifiers and announcements MUST be identical with
  Reduce Motion on or off.
- **ACC-001-R9**: Test builds MUST be able to report the duration of the last controls transition
  and simulate a Reduce Motion change, so the behavior is testable without a device; shipping builds
  contain neither.

### Key Entities

- **Motion policy**: the current Reduce Motion state and the rule that turns a decorative animation
  into an instant change while it is on; safety fades are outside it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ACC-001-S1**: With Reduce Motion on, 100% of the decorative transitions in the inventory take
  0 s; with it off they keep their current durations.
- **ACC-001-S2**: After the setting changes while the app runs, the first following controls
  transition already follows the new state (0 of 1 transitions use the old state).
- **ACC-001-S3**: Safety fades keep 100% of their duration with Reduce Motion on.
- **ACC-001-S4**: The visualization keeps drawing frames throughout (frames per second above zero
  before and after the change).
- **ACC-001-S5**: The project check reports zero unlisted app animations bypassing the rule.
- **ACC-001-S6** `{device}`: On D1, toggling Reduce Motion while the app runs changes the controls
  transition at once and leaves VoiceOver behavior unchanged.

## Assumptions

- "Editor transitions" means the app's own transitions around editing and control: the controls
  overlay and the status badges and notices that move with it (A1-A3). Settings and the other editors
  open as system sheets (A8).
- Instant changes, not cross-fades, are used because every existing decorative transition is already
  a short fade; the roadmap row asks to disable them.
- ACC-012 will later add per-user motion limits for content; this row does not limit content motion.
- Simulator results are never evidence for device behavior; the device check is a separate,
  owner-run task.
