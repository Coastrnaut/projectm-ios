# Feature Specification: PERF-011 Background resource release

**Feature Branch**: `feature/perf-011` (spec directory `004-perf-011-background-resource-release`)

**Created**: 2026-11-12

**Status**: Draft

**Input**: User description: "Implement PERF-011 (Background resource release) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Stop GPU loops and release camera when app cannot present frames." Acceptance, verbatim: "Background transition reduces active resources and resumes cleanly." Dependencies: none. Honor the repository constitution."

**Roadmap row**: PERF-011, priority P0, effort M, no dependencies
(`docs/FEATURE_ROADMAP_AUTONOMOUS.md`, PERF table).

**ID convention**: requirements are `PERF-011-R1…`, success criteria `PERF-011-S1…`, tasks
`PERF-011-T01…`. Identifiers such as FR-050 cite feature 001
(`specs/001-ios-projectm-visualizer/spec.md`).

## What already exists (audit of HEAD, 2026-11-12)

This feature adds only what is missing. The audit read the code and its tests at commit `e679131`.

| Area | What HEAD does when the app leaves the foreground | Evidence | Gap |
|---|---|---|---|
| Frame loop | Background and lock pause the renderer's display link while a visualization is on screen; foreground and unlock resume it unless the user paused (FR-046, FR-050, FR-054). | `LifecycleCoordinator.swift`, `LifecycleCoordinatorTests.swift` (T098, T099); `ANGLERendererTests.testPauseAndResumeTheDisplayLink` | "Paused by the user" and "cannot present" share one flag in the renderer, so any later `resume()` call (starting a source, a user-pause toggle, an automation mode) restarts the loop while the app still cannot present. An unlock that arrives while the app is still in the background resumes the visualization. |
| Preset warm-up | Nothing. The warm-up thread keeps its own graphics context, engine instance and render target alive, finishes its queue and accepts new requests. A request that is waiting out its delay still starts. | `PresetPrewarmer.swift`, `ANGLERenderer.prewarm` | Background GPU work continues; warm-up memory is held for the whole background period. |
| Drawable surface and post-pass target | Nothing. The window surface (its drawables) and the Reduce-flashing target stay allocated. | `ANGLERenderer.swift` | Full-screen GPU memory is held while nothing can be shown. |
| Audio sources | Per-source matrix: System/App Capture continues; Microphone and In-App Playback are suspended and resume within 2 s (FR-050, ADR-0001 ruling 17). | `CaptureManager.handle(_:)`, `LifecycleCoordinatorTests` | None. **Out of scope and unchanged.** |
| Auto-lock | Suppressed only while the visualization runs and the app is active (FR-084). | `IdleTimerPolicy.swift`, `IdleTimerPolicyTests.swift` | None. Unchanged. |
| Camera | The app has no camera code. | `docs/autonomous/AUDIT.md` (MED, CAM: missing) | No mechanism exists that a camera (or any later frame source) could join to be released in the background. |

## Clarifications

### Session 2026-11-12

Answered under the standing delegation (recommended option first; no owner question was needed).

- Q: Does the inactive state (Control Center, a call banner, the app switcher with the app still on screen) count as "cannot present frames"? → A: No. Only background and device lock do. In the inactive state the app is still visible and the system still shows its frames, so stopping would freeze a visible picture; HEAD already keeps rendering there and only auto-lock handling reacts (FR-084). (R1, S5)
- Q: What happens when the device is unlocked while the app is still in the background? → A: Nothing resumes. Background and lock are two independent conditions; frames can be presented only when neither holds. "Will enter foreground" clears both, so a missing unlock signal can never leave the app suspended. This corrects HEAD, where that unlock resumed the visualization. The capture layer still receives every event unchanged. (R1)
- Q: How much does the visible renderer give up while suspended? → A: The frame loop, the window surface (its drawables) and the Reduce-flashing target. It keeps the engine, the current preset and its textures, because rebuilding those costs up to a second of shader compiles and would change the picture on return. The warm-up, which holds a second engine and context only to save time later, is torn down completely. (R6, R7)
- Q: Must warm-up work have stopped by the time the suspend operation returns, or may it finish in the background? → A: It must have stopped. Suspend waits for the warm-up thread to reach its next safe point (it checks between loading a preset and each of its two frames) and to destroy its context. The wait is bounded by one engine call and happens once per background transition; no GPU work is then left running behind the app. (R7)
- Q: Is any of this state stored, and how is the change rolled back? → A: Nothing is stored. Availability is derived from live signals and starts as "can present" at launch; the registry lives in memory. There is no migration and no setting. Rollback is reverting the commits; no data is left behind. (R14)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Nothing draws while the app cannot be seen (Priority: P1)

A person is watching the visualizer and switches to another app, goes to the Home Screen or locks
the device. From that moment the app does no drawing work at all: the frame loop is stopped, the
background preset warm-up is stopped and its graphics resources are freed, and the full-screen
drawing surfaces are released. If System/App Capture is running it keeps running exactly as before
(FR-050), but nothing is rendered from it.

**Why this priority**: This is the roadmap row's observable behavior. With System/App Capture the
app stays alive in the background, so any drawing work left running costs battery and memory for
as long as the capture lasts, and background GPU work risks the system ending the app.

**Independent Test**: With test doubles for the app-state signals, send "entered background" and
check that every registered presentation-bound resource reports suspended, that the renderer draws
no frame and holds no window surface, and that the warm-up has no thread, context or queued work.

**Acceptance Scenarios**:

1. **Given** the visualizer is running, **When** the app enters the background, **Then** the frame
   loop is stopped, no frame is drawn until the app can present again, the warm-up is idle with
   its graphics resources released, and the window surface is released.
2. **Given** the visualizer is running with a warm-up request waiting for its delay, **When** the
   app enters the background, **Then** that request does not start any work in the background.
3. **Given** the app is in the background, **When** something asks the renderer to resume, draw,
   lay out its surface or warm presets (a source start, a late preset selection, a system layout
   pass), **Then** no frame loop starts, no surface is created and no warm-up work begins.
4. **Given** System/App Capture, Microphone or In-App Playback is the active source, **When** the
   app enters the background, **Then** the source behaves exactly as feature 001 specifies
   (FR-050, FR-054); this feature changes nothing about capture.
5. **Given** the app shows the source chooser (no visualization), **When** it enters the
   background, **Then** nothing fails and any registered resource is still suspended.

---

### User Story 2 - The picture comes back cleanly (Priority: P1)

The person returns to the app. The visualization continues within the time feature 001 already
promises for the audio (2 s): the surface is recreated at the current size, the frame loop restarts
once, and the warm-up is ready for the presets most likely to be chosen next. A visualization the
user had paused stays paused (FR-046).

**Why this priority**: Releasing resources is only acceptable if returning is invisible to the
user. The roadmap's acceptance criterion names both halves.

**Independent Test**: After a background transition, send "will enter foreground" and check each
resource resumed exactly once in the defined order, the renderer has a surface of the right size
and draws a frame, and the warm-up accepts the remembered request.

**Acceptance Scenarios**:

1. **Given** the app was sent to the background while visualizing, **When** it returns to the
   foreground, **Then** every resource that was suspended resumes exactly once, in registration
   order, and the renderer draws frames again.
2. **Given** the user had paused the visualization before leaving, **When** the app returns,
   **Then** the surface is ready but the frame loop stays paused until the user resumes.
3. **Given** the device rotated or the window changed size while the app was in the background,
   **When** it returns, **Then** the surface is created at the new size.
4. **Given** warm-up presets were requested before or during the background period, **When** the
   app returns, **Then** the most recent request is warmed after the normal delay.
5. **Given** background and foreground signals alternate rapidly (for example ten flips in a row,
   or two "background" signals in a row), **When** the sequence ends, **Then** each resource's
   state matches the last signal and no resource was suspended or resumed twice in a row.

---

### User Story 3 - Later frame sources join the same mechanism (Priority: P2)

A developer adding a camera layer, a video layer or another frame producer registers it as a
presentation-bound resource. Without further app changes it is released when the app cannot
present frames and reacquired when it can, in a defined order relative to the other resources. A
resource that registers while the app cannot present is suspended immediately, so it never starts
running in the background.

**Why this priority**: The roadmap row says "release camera". The app has no camera yet, so the
deliverable is the tested mechanism the camera features (CAM rows) will adopt.

**Independent Test**: Register fake resources, drive the signals, and check the call log: one
suspend per loss in reverse registration order, one resume per regain in registration order,
immediate suspension for late registrations, and no calls to resources that were unregistered or
deallocated.

**Acceptance Scenarios**:

1. **Given** three registered resources, **When** presentation is lost and regained, **Then** they
   are suspended in reverse registration order and resumed in registration order, once each.
2. **Given** presentation is lost, **When** a new resource registers, **Then** it is suspended
   immediately and resumed with the others on regain.
3. **Given** a resource was unregistered or deallocated, **When** presentation changes, **Then**
   it receives no call and nothing fails.
4. **Given** a diagnostics listener, **When** presentation changes, **Then** it is told how many
   resources were active before and after, so the reduction can be recorded.

---

### Edge Cases

- **Inactive, not background** (Control Center, Notification Center, an incoming-call banner, the
  app switcher while the app is still on screen, a system alert): the app can still present frames
  and the user can see them, so nothing is suspended. Auto-lock handling is unchanged (FR-084).
- **Lock** is handled like background (FR-054). A lock signal while already in the background
  changes nothing.
- **Unlock while still in the background** (the device was locked and unlocked while another app
  was in front): the app still cannot present, so nothing resumes until it enters the foreground.
- **Foreground without a preceding unlock signal**: entering the foreground proves the app can
  present, so everything resumes; the app never stays suspended waiting for an unlock signal.
- **Repeated signals** (two backgrounds, two foregrounds): the second one does nothing.
- **Resource registered twice**: the second registration is ignored.
- **A resource that registers or unregisters another resource from inside its own suspend or
  resume**: the change takes effect without skipping or repeating any resource.
- **Renderer destroyed while suspended**: it is released without touching objects it already
  released.
- **Renderer fallback** (the OpenGL ES renderer used when the ANGLE renderer cannot start): its
  frame loop obeys the same suspension.
- **Preset selected while in the background** (a load that was already in flight): the preset is
  loaded into the engine, but nothing is drawn until the app can present.
- **Warm-up in the middle of a preset when the app enters the background**: the warm-up stops at
  the next safe point; when suspension returns, no warm-up work is running.
- **RendererLab and CaptureLab** (harness apps) do not adopt the mechanism and behave as before.

## Requirements *(mandatory)*

### Functional Requirements

- **PERF-011-R1**: The app MUST decide "can present frames" from the app-state signals it already
  observes: it cannot present from "entered background" until "will enter foreground", and from
  "device locked" until "device unlocked" or "will enter foreground", whichever comes first. The
  inactive state alone MUST NOT count as "cannot present".
- **PERF-011-R2**: There MUST be one registry of presentation-bound resources. A resource states a
  name and provides a suspend and a resume operation. The registry MUST NOT keep a resource alive.
- **PERF-011-R3**: When presentation is lost, every registered resource that is not already
  suspended MUST be suspended exactly once, in reverse registration order. When presentation is
  regained, every resource the registry suspended MUST be resumed exactly once, in registration
  order. Repeated signals MUST NOT repeat calls.
- **PERF-011-R4**: A resource registered while the app cannot present MUST be suspended
  immediately. Unregistering a resource MUST stop all further calls to it and MUST NOT resume it.
- **PERF-011-R5**: While suspended, the visible renderer MUST NOT run its frame loop or draw a
  frame, whatever its user-pause state and whatever is asked of it. User pause (FR-046) and
  suspension are independent: the loop runs only when neither applies.
- **PERF-011-R6**: While suspended, the visible renderer MUST release its window surface and its
  Reduce-flashing render target, MUST NOT create them, and on resume MUST recreate the surface at
  the view's current size before the first frame. The engine, its current preset and the loaded
  textures are kept, so the picture continues from the same preset.
- **PERF-011-R7**: While suspended, the preset warm-up MUST do no work: a request waiting for its
  delay is cancelled, queued presets are dropped, the warm-up thread ends, and its graphics
  context, engine instance and render target are destroyed. The suspend operation waits for the
  thread to reach its next safe point (between a preset's load and each of its frames), so when
  it returns no warm-up work is running.
- **PERF-011-R8**: On resume, the most recent warm-up request (made before or during suspension)
  MUST be issued again with the normal delay. Presets already warmed MUST NOT be warmed again.
- **PERF-011-R9**: The fallback renderer's frame loop MUST obey R5.
- **PERF-011-R10**: The app MUST register the renderer's presentation-bound resources when it
  creates the renderer, and MUST drive the registry from the same lifecycle events that already
  pause the visualization, before forwarding the event to the capture layer.
- **PERF-011-R11**: Capture behavior MUST NOT change: the per-source background matrix (FR-050,
  FR-051, FR-054, ADR-0001 ruling 17) and auto-lock handling (FR-084) stay exactly as tested today.
  No entitlement, background mode, permission or network use is added.
- **PERF-011-R12**: Each presentation change MUST be reportable to diagnostics as: the new state,
  and the number of active resources before and after. The report MUST contain no user content.
- **PERF-011-R13**: All suspend and resume operations MUST be safe to repeat and MUST NOT use an
  object after it was released, including when the renderer is destroyed while suspended.

- **PERF-011-R14**: Nothing about presentation availability or the registry is persisted. At
  launch the app assumes it can present; the registry and its marks live in memory only.

### Key Entities

- **Presentation availability**: whether the app can currently present frames, derived from the
  background and lock conditions (R1).
- **Presentation-bound resource**: anything that only has value while frames can be presented: a
  frame loop, a drawable surface, background GPU work, and later a camera session or video
  decoder. Has a name, a suspend operation and a resume operation.
- **Presentation resource registry**: the ordered list of registered resources with, for each, a
  "suspended by the registry" mark; applies R3 and R4 and reports R12.
- **Presentation transition report**: new availability plus active-resource counts before and
  after (R12).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PERF-011-S1**: After a background or lock transition, the number of active presentation-bound
  resources is zero, and the visible renderer draws zero frames until the app can present again.
- **PERF-011-S2**: After a background transition, the warm-up holds no thread, graphics context or
  queued preset, and the visible renderer holds no window surface.
- **PERF-011-S3**: After returning to the foreground, every suspended resource has resumed exactly
  once, the renderer's surface matches the view's current size, and the next frame is drawn from
  the same preset as before.
- **PERF-011-S4**: A sequence of 100 alternating and repeated background, foreground, lock and
  unlock signals ends with every resource in the state the last signal implies, with suspend and
  resume calls strictly alternating for each resource.
- **PERF-011-S5**: Inactive-only transitions cause zero suspend calls.
- **PERF-011-S6**: The existing lifecycle tests of feature 001 (per-source matrix, user pause,
  auto-lock) pass unchanged in meaning.
- **PERF-011-S7** `{device}`: On D1, with System/App Capture running, the app's GPU time is zero
  and its memory footprint is lower 10 s after entering the background than while visualizing;
  after returning, frames resume within 2 s. Measured in the final device stage; not claimed
  until then.
- **PERF-011-S8** `{device}`: On D1-D3, the app switcher card and the first frame after returning
  show the visualization (no black or stale flash longer than one blend).

## Assumptions

- The four signals the app already observes (entered background, will enter foreground, protected
  data will become unavailable, protected data became available) are sufficient; no new system
  observer is added. Devices without a passcode never send the lock signals and are covered by the
  background signal.
- The layer keeps showing its last presented frame after the window surface is released, so the
  app switcher card is not blank. This is an assumption about platform behavior and is checked on
  devices (S8); it is not stated as fact.
- A simulator can prove the state transitions, surface release and recreation, and warm-up
  teardown. It cannot prove GPU time, memory or battery effects (constitution X); those are S7.
- The app has one window scene. Multi-window presentation is out of scope.
- Camera, video and other frame sources are later roadmap features (CAM, MED rows). This feature
  delivers the mechanism and its first two adopters only.
- Memory-warning eviction is PERF-006 and crash recovery is PERF-010; neither is part of this
  feature.
