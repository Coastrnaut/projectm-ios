# Feature Specification: OUT-001 External Display Scene

**Feature Branch**: `feature/out-001` (spec directory `049-out-001-external-display-scene`)

**Created**: 2026-11-13

**Status**: Implemented 2026-11-13 (OUT-001-T01-T14, T19 verified on the Mac: host, iOS 27.2 and 26.5 simulators, simulated external display; T15-T18 `{device}` open)

**Input**: User description: "Implement OUT-001 (External display scene) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Present a clean
visualization-only window on connected display." Acceptance, verbatim: "External display shows
composited scene while device retains controls." Depends on CMP-001 (integrated). Verification:
simulator external display, then physical displays last (USB-C/HDMI adapter and AirPlay to an Apple
TV on D1/D2/D3, Stage Manager extended display on D2, hot-plug during playback, resolution and
refresh changes). Implement only OUT-001; OUT-002 to OUT-014 build on it."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `OUT-001-R1…`, success criteria `OUT-001-S1…`, tasks `OUT-001-T01…`. Requirements
of other features are cited by their own IDs: FR-084 (auto-lock), FR-072 (Reduce flashing),
FX-019-R11 (flash history survives pauses), CMP-001-R9 and R10 (no per-frame allocation, composite
flash guard), PERF-011 (presentation loss), CAM-001-R7 and CAM-012 (camera runs only while shown).

## Baseline: what exists today (audit of 2026-11-13, commit `b2d557d`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| Scenes | One SwiftUI window group; no scene configuration for any other role. | A connected display gets the system's mirror of the whole device screen, controls, badges and banners included. |
| Visuals | projectM (one EGL context and engine bound to one view), the native spectra, Camera and Photo (each one compositor bound to one view). Each draws for its view's size and screen scale. | Nothing can draw into a second window. |
| Flash safety | projectM: the strobe envelope post-pass in the renderer. Compositor visuals: the composite flash guard. Both keep their history across pauses. | No external output exists to cover. |
| Scene events | The Camera and Photo visuals stop when *any* scene disconnects and start when *any* scene connects. | A display unplugged would stop the camera on the device; a display plugged in could restart it while the device scene is gone. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: While the visualization is on the external display, does the device also draw a live preview of it? → A: No. The device shows the controls over a black background with a short note ("Showing on external display"); the one visualization is drawn once, on the external display. Drawing twice would double the GPU cost on the busiest path (on D1 only 22 of 28 starter presets reach 55 fps under ANGLE and the slowest runs at 26 fps; `docs/test-reports/performance.md`) and would need a second projectM engine and EGL context whose picture drifts from the first (presets, blends and beat state are engine-internal and cannot be shared between contexts), or a GPU copy between ANGLE's and the app's Metal devices. A live preview belongs with OUT-006 (output variants) and OUT-012 (rehearsal). Rejected: render twice (cost, divergence); a mirrored screenshot of the device picture (not the external display's resolution).
- Q: Does anything other than the visualization appear on the external display (a small status, a logo, the paused label)? → A: Nothing. The window is the visualization alone; the paused state shows as the frozen last frame (FR-085's dimming and "Paused" text stay on the device). Rejected: a tiny status corner (it would be projected to a whole room and is what OUT-011 diagnostics on the device are for).
- Q: What does the external display show while no visualization runs (notice, source chooser)? → A: Black. Menus and the photosensitivity notice are never projected. Rejected: mirroring the device (shows controls on stage, the row's opposite); the last frame (stale, and the visualizer's resources are released when it stops).
- Q: When the external display's scene goes to the background, has no size yet, or a second external scene connects, where does the visualization go? → A: Background or zero size: back to the device until the scene is foreground with a size again. A second external scene: the first connected one keeps the visualization until it disconnects, then the next connected one (if any) takes it. Rejected: keeping the visualization on a backgrounded external scene (nothing would be visible anywhere).
- Q: Which frame loop paces the external output? → A: The visual's existing frame loop (at most 60 fps, FR-049) keeps running unchanged; the external display shows each frame when it is presented. Per-output pacing (a frame loop tied to the external display's refresh, for example 50 Hz or 24 Hz televisions) is OUT-013; the cost of the mismatch is measured on devices (`{device}` task). Rejected: switching to the external display's own frame timing now (it would change every visual's loop in this row).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The connected display shows only the visualization (Priority: P1)

A performer connects the iPhone or iPad to a TV or projector (cable or AirPlay) while the visualizer
runs. The big screen shows the visualization alone, edge to edge, at its own resolution: no
controls, no badges, no banners, no status bar. The device keeps the controls, the badges and every
sheet, and shows a short note that the visualization is on the external display.

**Why this priority**: It is the row's acceptance.

**Independent Test**: In the simulator, turn on its external display while the visualizer runs;
the external screen shows the visualization and nothing else, the device shows the controls and the
note. A unit-level fake of the external scene checks the same routing without the simulator.

**Acceptance Scenarios**:

1. **Given** the visualizer runs (any visual: projectM, a native spectrum, Camera or Photo), **When**
   a display connects, **Then** the visualization appears on it, sized to fill it, with no control,
   badge, banner or text over it.
2. **Given** the visualization is on the external display, **When** the user taps the device screen,
   **Then** the controls appear on the device and work as before (pause, next preset, settings,
   stop), and their effect shows on the external display.
3. **Given** the visualization is on the external display, **When** the user changes the visual in
   Settings, **Then** the new visual appears on the external display, not on the device.
4. **Given** the app is on the notice or the source chooser, **When** a display is connected,
   **Then** the external display stays black (nothing is visualized yet) and the device is
   unchanged; when the visualizer starts, the visualization goes to the external display.

---

### User Story 2 - Plugging and unplugging never interrupts the music (Priority: P1)

The performer plugs and unplugs the display during a set. The audio source keeps playing, and the
picture moves between screens without restarting anything.

**Why this priority**: A visualizer that restarts its source or crashes on a cable wiggle cannot be
used on stage.

**Independent Test**: Coordinator tests with fakes: connect, disconnect, reconnect, size change and
background; a UI test with a simulated external display counts source starts across connect and
disconnect.

**Acceptance Scenarios**:

1. **Given** the visualizer runs on the device, **When** a display connects, **Then** the
   visualization moves to it within the next few frames and the audio source is not restarted.
2. **Given** the visualization is on the external display, **When** the display disconnects,
   **Then** the device shows the visualization full screen again and the audio source is not
   restarted.
3. **Given** the display is connected, **When** its size or resolution changes, **Then** the
   visualization is redrawn for the new size, with no crash and no restart.
4. **Given** the Camera visual runs on the external display, **When** the display disconnects,
   **Then** the camera keeps running and its picture shows on the device.

---

### User Story 3 - The big screen is as flash-safe as the device (Priority: P1)

The external output passes through the same flash limiting as the device output, so a projected
picture never flashes more than the device would.

**Why this priority**: A projector magnifies a strobe to a whole room (Constitution: photosensitive
safety).

**Independent Test**: Renderer tests: a strobe composited at device size and then at 1920 × 1080
stays within the envelope across the switch, and the envelope's history is not reset by the switch.

**Acceptance Scenarios**:

1. **Given** Reduce flashing on or off, **When** a strobe is drawn on the external display, **Then**
   it is limited exactly as on the device (same envelope, same setting).
2. **Given** a strobe in progress, **When** the visualization moves between the device and the
   external display, **Then** the strobe's flash budget continues; the move does not give it a fresh
   budget.

### Edge Cases

- A display connects while the app is in the background: nothing draws until the app returns
  (PERF-011); then the visualization goes to the display.
- The external display's scene goes to the background while the device stays active: the
  visualization returns to the device.
- A second external display scene connects while one is in use (rare): the first keeps the
  visualization; the second stays black.
- The external display reports a zero size while it configures: the visualization stays on the
  device until the display has a size.
- The external display's size changes repeatedly (resolution change, AirPlay renegotiation): each
  size is drawn once it is reported; no crash on any size.
- The user stops the visualizer (back to the chooser): the external display goes black.
- The device locks or the app backgrounds while connected: frames stop as today (PERF-011); auto-lock
  behaviour on the device is unchanged (FR-084).
- iPad Stage Manager on an extended display moves the whole app window there; that is the system's
  window management, not this row's external scene, and it keeps working as before.
- Screen recording or AirPlay mirroring chosen by the user without an external scene: the system
  mirrors the device as before.

## Requirements *(mandatory)*

### Functional Requirements

- **OUT-001-R1**: The app MUST provide a window for a connected non-interactive external display
  that shows only the visualization, filling the display, with no controls, badges, banners, text or
  status indicators over it. While the user has paused, it shows the last frame (the dimming and
  "Paused" text stay on the device); while no visualization runs, it is black.
- **OUT-001-R2**: While a usable external display is connected and the visualizer runs, the
  visualization MUST be drawn on the external display at the display's own size and scale (not a
  copy of the device picture), and the device MUST keep the controls, badges, banners and sheets and
  show a short note that the visualization is on the external display.
- **OUT-001-R3**: Only one visualization MUST be drawn at a time: while it is on the external
  display the device shows no live preview, so the GPU cost does not double.
- **OUT-001-R4**: Connecting, disconnecting, reconnecting or resizing the external display MUST NOT
  restart, stop or pause the audio source, and MUST NOT reset the chosen visual, preset or settings.
- **OUT-001-R5**: When the external display disconnects, goes to the background or has no size, the
  visualization MUST return to the device full screen.
- **OUT-001-R6**: The visualization MUST appear on a newly connected display (and return to the
  device after a disconnect) without waiting for user action, within 0.5 s of the system reporting
  the change.
- **OUT-001-R7**: A size or scale change of the external display MUST redraw the visualization for
  the new size and never crash; no resource is created per frame at a steady size (CMP-001-R9).
- **OUT-001-R8**: The external output MUST pass through the same flash limiting as the device
  output (FR-072, FX-019; CMP-001-R10 for compositor visuals), and moving the visualization between
  displays MUST NOT reset the flash history (FX-019-R11).
- **OUT-001-R9**: Scene events of the external display MUST NOT stop or start the camera, the photo
  visual or any other device-scene resource; only the device's own scene events do (CAM-001-R7,
  CAM-012).
- **OUT-001-R10**: The device's auto-lock behaviour (FR-084), presentation-loss handling (PERF-011)
  and system overlay rules (FR-086, FR-089, CAM-001-R10) MUST be unchanged.
- **OUT-001-R11**: The feature MUST use only public, documented platform APIs (Constitution I) and
  MUST build for both supported OS versions (iOS 26 and 27).
- **OUT-001-R12**: The routing rules (which screen shows the visualization for each combination of
  connection, size, background and visualizer state) MUST be testable without a display, the
  simulator or a device.

### Key Entities

- **External display state**: whether an external display scene is connected, its size and scale,
  and whether it is in the foreground.
- **Output target**: where the visualization is drawn: the device or the external display.
- **Visualization slot**: a place a visualization can be shown in (the device's visualizer, the
  external window); exactly one slot holds the visualization at a time.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **OUT-001-S1**: With a simulated external display, the external screen shows the visualization and
  the device shows the controls and the note, in 100% of runs (the acceptance; simulator check, then
  devices last).
- **OUT-001-S2**: Across connect, disconnect and reconnect, the audio source is started exactly once
  (0 restarts).
- **OUT-001-S3**: The routing rules give the expected target in 100% of the specified transitions
  (connect, disconnect, reconnect, size change, zero size, background, second display, visualizer
  stopped).
- **OUT-001-S4**: A visualization drawn for a 1920 × 1080 display produces 1920 × 1080 output, and
  frames at a steady size create no new resources.
- **OUT-001-S5**: A strobe that crosses a move between displays stays within the flash envelope's
  transition limit in every area, and its budget is not reset by the move.
- **OUT-001-S6**: On physical displays (USB-C/HDMI, AirPlay, D1-D3; Stage Manager on D2) the
  acceptance holds, hot-plug during playback never restarts the source, and resolution and refresh
  changes never crash (device stage, owner's hands).

## Assumptions

- Output resolution control (OUT-003), aspect correction (OUT-004), per-display variants and
  mirroring choice (OUT-006), blackout (OUT-010), diagnostics (OUT-011) and per-output frame pacing
  (OUT-013) are later rows; this row draws the visualization at the display's native size and scale
  with the device's frame loop.
- The external window is non-interactive: no input arrives there, so all control stays on the
  device.
- When no visualization runs (notice, chooser), the external display stays black rather than
  mirroring the device's menus.
- Simulator results are never device evidence (Constitution X); physical display checks are
  `{device}` tasks left to the owner.
