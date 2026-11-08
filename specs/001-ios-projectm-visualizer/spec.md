# Feature Specification: ProjectM-iOS Visualizer

**Feature Branch**: `001-ios-projectm-visualizer`

**Created**: 2026-11-07

**Status**: Draft

**Input**: User description: "Specify ProjectM-iOS: a native iPhone/iPad application that visualizes
eligible audio from other iOS applications using the ProjectM C++ engine and MilkDrop-compatible
presets. User chooses system/app capture and selects a source using Apple's supported system UI
when available; the app receives only the audio permitted by the OS and selected source; full-screen
real-time visualization; preset selection, favorites, switching, pause/stop, visible source and
capture state; microphone and in-app playback as explicit, distinctly labeled fallbacks. Do not
promise capture from every app; do not bypass DRM, private APIs, permissions, or protected playback;
handle unsupported OS, no samples, silent samples, interruption, source changes, capture termination,
and permission denial; no recording or upload by default; Phase 0 feasibility app and physical-device
source compatibility report before full implementation; iPhone/iPad responsive layouts and foreground
lifecycle handling. Capture feasibility is a blocking requirement before the full application is
approved."

## Delivery Gating *(mandatory for this feature)*

This feature is delivered in two stages. Stage 2 MUST NOT be approved until Stage 1's evidence is
reviewed.

- **Stage 1 — Capture Feasibility (User Stories 1–3)**: A diagnostic application and a
  physical-device source compatibility report establishing which audio sources deliver usable
  audio through the supported system flow.
- **Stage 2 — Full Visualizer (User Stories 4–7)**: The visualization experience, built only for
  the source modes Stage 1 proved usable.

**Approval rule**: Stage 2 is approved when the compatibility report (FR-030–FR-033) exists, has
been reviewed, and records at least one source mode with verified non-silent audio on a physical
device. If no external-app source passes, Stage 2 proceeds with microphone and in-app playback only,
and that limitation is stated in the product description.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Verify external-app audio capture (Priority: P1)

A tester starts music in another app (for example a streaming app or a browser video), opens the
feasibility app, taps **Choose Audio Source**, picks system/app capture, and selects a source in
Apple's system sharing prompt. The app shows live diagnostics proving whether real audio is
arriving: sample count, sample rate, channel count, timestamps, buffer cadence, and peak/RMS level.
It clearly reports one of three outcomes: no audio received, audio received but silent, or active
audio.

**Why this priority**: Whether other apps' audio can be captured at all is the central product risk.
Every later story depends on this answer.

**Independent Test**: On a physical device, play audio in a source app, start capture, and confirm
the diagnostic screen classifies the stream correctly for a playing source, a paused source, and a
source that delivers nothing.

**Acceptance Scenarios**:

1. **Given** a supported OS and a source app playing audible content, **When** the user starts
   system/app capture and confirms the system prompt, **Then** the app displays "Active audio"
   only after non-silent samples arrive, and shows sample rate, channel count, and level updating.
2. **Given** capture is running, **When** the source app is paused, **Then** the status changes to
   "Audio received — silent" within 2 seconds while sample counters keep increasing.
3. **Given** capture is running, **When** no audio buffers arrive for 5 seconds after start,
   **Then** the app shows "No audio samples received" and suggests choosing another source or using
   microphone mode.
4. **Given** the user cancels or declines the system prompt, **When** control returns to the app,
   **Then** the app shows that capture was not started and remains usable.
5. **Given** a device whose OS does not offer the required system capture flow, **When** the user
   opens the source chooser, **Then** system/app capture is shown as unavailable with the reason,
   and microphone and in-app playback remain selectable.

---

### User Story 2 - Fallback sources: microphone and in-app playback (Priority: P1)

A user who cannot (or chooses not to) capture another app's audio selects **Microphone** or
**In-App Playback**. Microphone mode explains that it hears sound in the room. In-app playback plays
a bundled reference audio track the app itself controls. Each mode is labeled unmistakably.

**Why this priority**: Fallbacks guarantee the product works on every supported device regardless
of external-capture results, and in-app playback provides a repeatable reference for testing.

**Independent Test**: Select each fallback mode on a device with external capture disabled and
confirm audio diagnostics (Stage 1) or visuals (Stage 2) respond, with the correct label shown.

**Acceptance Scenarios**:

1. **Given** microphone permission has not been requested, **When** the user selects Microphone,
   **Then** the app explains that it captures ambient sound and then requests permission.
2. **Given** microphone permission is denied, **When** the user selects Microphone, **Then** the app
   shows that permission is denied and how to enable it in Settings, and offers other sources.
3. **Given** the user selects In-App Playback, **When** playback starts, **Then** the source label
   reads "In-App Playback" and audio diagnostics show active audio within 1 second.
4. **Given** any fallback is active, **When** the user views the source indicator, **Then** it never
   reads as system or app capture.

---

### User Story 3 - Source compatibility report (Priority: P1)

The product team runs a defined test procedure on physical devices for each candidate source
(Spotify, Apple Music, YouTube Music, Safari video, in-app reference audio, microphone) and records
the results in a compatibility report that decides what the product may claim.

**Why this priority**: The report is the go/no-go evidence that gates Stage 2 and bounds every
compatibility claim the product makes.

**Independent Test**: Review the report and confirm every tested source has a complete entry and a
pass/fail/partial result reproducible from its recorded steps.

**Acceptance Scenarios**:

1. **Given** a test run on a physical device, **When** the tester exports diagnostics, **Then** the
   export contains device model, OS build, app build, source mode, buffer arrival, non-silence
   result, sample rate, channel count, and observed timing — and no raw audio.
2. **Given** a source delivers no audio or only silence, **When** it is recorded, **Then** the report
   marks it unsupported for that device/OS/app version with the observed behavior.
3. **Given** the report is complete, **When** Stage 2 approval is reviewed, **Then** the approval
   decision and the list of claimable sources are recorded in the report.

---

### User Story 4 - Full-screen visualization of live audio (Priority: P2)

A user with an active audio source sees a full-screen, real-time visualization driven by that audio.
Tapping the screen reveals or hides controls. The visualization adapts to portrait and landscape on
iPhone and iPad.

**Why this priority**: This is the core user value once feasibility is proven.

**Independent Test**: With in-app playback active, open the visualizer and confirm visuals react to
the music, fill the screen in both orientations, and controls toggle on tap.

**Acceptance Scenarios**:

1. **Given** an active audio source, **When** the visualizer is open, **Then** the visualization
   fills the screen and visibly responds to changes in the audio (e.g., beats, silence).
2. **Given** controls are hidden, **When** the user taps the screen, **Then** controls appear;
   **When** the user does not interact for 5 seconds, **Then** they hide again.
3. **Given** the device is rotated, **When** orientation changes, **Then** the visualization and
   controls re-lay out within 1 second without restarting capture.
4. **Given** an iPad in split-screen or a resized window, **When** the window size changes, **Then**
   the visualization fills the available area and controls remain reachable.

---

### User Story 5 - Preset selection, switching, and favorites (Priority: P2)

A user browses the bundled visual presets, picks one by name, moves to the next/previous or a random
preset, and marks favorites to find again later. The current preset name is shown.

**Why this priority**: Presets are the main way users personalize the experience.

**Independent Test**: With any source active, switch presets via next/previous/random and the
browser, favorite two presets, relaunch the app, and confirm favorites persist.

**Acceptance Scenarios**:

1. **Given** the visualizer is running, **When** the user taps Next, **Then** a different preset
   begins within 1 second and its name is displayed.
2. **Given** the preset browser is open, **When** the user selects a preset, **Then** it becomes
   active and the browser closes or indicates the active preset.
3. **Given** the user favorites a preset, **When** the app is relaunched, **Then** the preset is
   still marked as a favorite and can be filtered to.
4. **Given** a preset fails to load, **When** it is selected, **Then** the app shows that it could
   not be loaded, keeps the previous preset running, and does not crash.

---

### User Story 6 - Source status and capture control (Priority: P2)

At any time the user can see which source is active (System/App Capture, Microphone, or In-App
Playback), whether audio is actually arriving, and why capture stopped if it did. The user can pause
the visualization and stop capture.

**Why this priority**: Truthful status builds trust and makes failures understandable.

**Independent Test**: Exercise start, pause, resume, stop, and an OS-ended capture; confirm the
indicator and messages match reality at each step.

**Acceptance Scenarios**:

1. **Given** capture is active, **When** the user taps Stop, **Then** capture ends, the indicator
   shows "Stopped", and no further audio is received.
2. **Given** the visualization is paused, **When** the user resumes, **Then** visuals continue from
   the live source without re-selecting it.
3. **Given** the OS ends the capture session (e.g., user stops sharing from system UI), **When**
   this occurs, **Then** the app shows "Capture ended by system" and offers to choose a source.
4. **Given** the user switches source, **When** the new source starts, **Then** the indicator
   reflects the new source only after its audio is verified.

---

### User Story 7 - Lifecycle and interruption resilience (Priority: P3)

The app behaves predictably when the user leaves the app, locks the device, receives a phone call,
connects headphones, or the system interrupts audio.

**Why this priority**: Prevents crashes and confusing states in everyday use.

**Independent Test**: Run a scripted sequence of background/foreground, lock/unlock, interruption,
and audio-route changes during each source mode and confirm the documented behavior with no crash.

**Acceptance Scenarios**:

1. **Given** any source is active, **When** the app moves to the background, **Then** the
   visualization pauses and, on return, the app either resumes the source or clearly states that
   capture ended and why.
2. **Given** an audio interruption (e.g., a call), **When** it ends, **Then** the app resumes or
   shows the source as interrupted with a one-tap restart.
3. **Given** the audio route changes (e.g., headphones connected), **When** the change occurs,
   **Then** the app continues or reports the new state without crashing.

---

### Edge Cases

- OS version lacks the system capture flow → system/app capture shown as unavailable with reason;
  fallbacks remain.
- User cancels the system sharing prompt → no capture, clear message, app usable.
- Source delivers no buffers at all vs. delivers silent buffers → reported as different states.
- Protected or excluded content (DRM) → treated as "no audio" or "silent"; app never attempts to
  work around it and never claims the source works.
- Source app starts/stops playback mid-session → status transitions between silent and active.
- Audio format changes mid-stream (sample rate or channel count) → diagnostics update; no crash.
- Capture ended by system, device lock, or app backgrounding → state shown on return.
- Rapid repeated start/stop or source switching → no crash, no duplicate sessions.
- Microphone permission revoked in Settings while app is backgrounded → detected on return.
- Bundled preset missing or malformed → skipped with message; previous preset continues.
- Very long session (30+ minutes) → no growing memory use or degrading responsiveness.
- Low-power mode or thermal pressure → visualization may reduce quality but status stays truthful.

## Requirements *(mandatory)*

### Functional Requirements

**Capture and sources**

- **FR-001**: System MUST offer three source modes — System/App Capture, Microphone, and In-App
  Playback — and only one MAY be active at a time.
- **FR-002**: System/App Capture MUST start only after an explicit user action and the OS's own
  user-facing sharing/selection prompt; the app MUST NOT start capture silently.
- **FR-003**: System MUST use only capabilities Apple makes available to App Store apps and MUST NOT
  attempt to bypass DRM, protected playback, app capture restrictions, or OS permissions.
- **FR-004**: System MUST detect whether the device supports System/App Capture and, if not, show it
  as unavailable with an explanation while keeping fallback modes available.
- **FR-005**: Microphone mode MUST explain, before requesting permission, that it captures ambient
  sound in the room.
- **FR-006**: In-App Playback MUST provide at least one bundled reference audio track with legally
  redistributable rights.
- **FR-007**: Users MUST be able to switch sources and stop capture at any time.

**Audio state truthfulness**

- **FR-010**: System MUST classify incoming audio as exactly one of: Not started, Waiting, No audio
  received, Audio received — silent, Active audio, Interrupted, Stopped, or Ended by system.
- **FR-011**: "Active audio"/"Receiving audio" MUST be shown only after non-silent samples are
  verified during the current session. Silence threshold: peak level below −60 dBFS sustained for
  at least 2 seconds (subject to tuning during Stage 1, with the final value recorded).
- **FR-012**: "No audio received" MUST be shown when no audio data arrives within 5 seconds of a
  successful capture start.
- **FR-013**: The source indicator MUST always show the active mode label, and Microphone or In-App
  Playback MUST never be labeled as system/app capture.
- **FR-014**: The app MUST NOT name a specific third-party app as connected or captured unless
  verified audio from that selection arrived in the current session.
- **FR-015**: When capture stops for any reason other than the user, the app MUST display the reason
  (permission denied, cancelled, ended by system, interrupted, unsupported, error).

**Feasibility diagnostics (Stage 1)**

- **FR-020**: The feasibility app MUST display live sample count, sample rate, channel count,
  first/last sample timestamps, buffer cadence, peak and RMS level, and the current audio state.
- **FR-021**: The feasibility app MUST let the tester export a diagnostics summary containing only
  metadata (no raw audio).
- **FR-022**: The feasibility app MUST record dropped or late buffers and start-to-first-audio time.

**Compatibility report (Stage 1)**

- **FR-030**: A compatibility report MUST exist covering at minimum: Spotify, Apple Music, YouTube
  Music, Safari video, in-app reference audio, and microphone.
- **FR-031**: Each entry MUST record device model, exact OS build, development toolchain version,
  source app version, capture mode and selection made, whether audio arrived, whether it was
  non-silent, sample rate, channel count, average and worst observed latency, interruption/end
  behavior, result (works / partial / does not work), and reproduction steps.
- **FR-032**: At least one supported iPhone at the minimum OS and one current-generation iPhone MUST
  be tested; an iPad MUST be tested if iPad is a launch requirement.
- **FR-033**: The report MUST record the Stage 2 go/no-go decision and the list of claimable sources.

**Visualization and presets (Stage 2)**

- **FR-040**: System MUST render a full-screen visualization driven by the active source's audio,
  compatible with MilkDrop-style presets.
- **FR-041**: System MUST support portrait and landscape on iPhone and iPad, and resizable/split
  windows on iPad.
- **FR-042**: Tapping the visualization MUST toggle controls; controls MUST auto-hide after 5 seconds
  without interaction.
- **FR-043**: Users MUST be able to choose a preset from a browser, go to next/previous/random, and
  see the current preset's name.
- **FR-044**: Users MUST be able to mark and unmark favorites, filter to favorites, and have
  favorites persist across launches.
- **FR-045**: A preset that fails to load MUST be reported to the user, skipped, and MUST NOT
  interrupt the currently running visualization.
- **FR-046**: Users MUST be able to pause and resume the visualization independently of stopping
  capture.
- **FR-047**: Only presets with reviewed redistribution rights MAY be bundled.
- **FR-048**: An optional on-screen performance overlay MUST be available showing frame rate and
  audio state (for testing and support).

**Lifecycle**

- **FR-050**: On backgrounding, the app MUST pause visualization and, on return to foreground, either
  resume the source or show why capture ended.
- **FR-051**: The app MUST handle audio interruptions and route changes without crashing and MUST
  offer a one-tap restart when a source cannot resume automatically.
- **FR-052**: Starting, stopping, and switching sources MUST be safe when repeated rapidly (no
  crash, no duplicate sessions).
- **FR-053**: The app MUST detect permission changes (e.g., microphone revoked in Settings) when it
  returns to the foreground.

**Privacy and claims**

- **FR-060**: The app MUST NOT record audio to storage, upload audio, or send audio off-device.
- **FR-061**: Diagnostics MAY contain audio metadata (levels, formats, timing) but MUST NOT contain
  raw audio.
- **FR-062**: The app, its documentation, and its store listing MUST NOT claim universal system-audio
  capture or guaranteed compatibility with any specific third-party app; claims MUST be limited to
  sources marked "works" in the compatibility report.
- **FR-063**: A privacy policy accurately describing capture, permissions, and data handling MUST be
  available before release.

### Key Entities

- **Audio Source**: A selectable origin of audio. Attributes: mode (System/App Capture, Microphone,
  In-App Playback), display label, availability on this device, current audio state, stop reason.
- **Audio State**: The truthfulness status of incoming audio (see FR-010), with timestamps of the
  last transition and last non-silent sample.
- **Audio Diagnostics Snapshot**: Metadata about a capture session — sample count, sample rate,
  channel count, timestamps, cadence, peak/RMS, dropped buffers, start-to-first-audio time. Never
  contains raw audio.
- **Compatibility Test Record**: One row of the compatibility report (fields in FR-031), linked to
  a device, OS build, source app, and result.
- **Preset**: A visual program. Attributes: name, source/license, load status, favorite flag.
- **Favorites List**: The user's saved set of favorite presets; persists across launches.

## Success Criteria *(mandatory)*

### Measurable Outcomes

**Stage 1 (blocking)**

- **SC-001**: For every source in the test matrix, the compatibility report records a reproducible
  result on at least two physical iPhone models, with zero entries marked "works" lacking evidence
  of non-silent audio.
- **SC-002**: The feasibility app classifies playing, paused, and absent audio correctly in 100% of
  20 scripted trials per available source mode.
- **SC-003**: Status changes from silent to active (and back) are shown to the user within 2 seconds
  of the audio change in 95% of trials.
- **SC-004**: Microphone and In-App Playback each reach "Active audio" within 2 seconds of starting
  with audible input, on every tested device.

**Stage 2**

- **SC-005**: On the reference current-generation device, the visualization sustains at least 55
  frames per second for 95% of a 10-minute session with the visualizer in the foreground; the
  minimum-supported device's sustained rate is measured and published.
- **SC-006**: Visuals respond to audio changes with a delay a user does not perceive as lagging —
  measured audio-to-visual delay is under 150 ms on the reference device (to be confirmed by
  Stage 1 latency measurements).
- **SC-007**: Preset switches complete within 1 second in 95% of switches across the bundled set.
- **SC-008**: A 30-minute session with an active source shows no continuous memory growth and no
  crash.
- **SC-009**: 50 consecutive rapid start/stop/switch cycles, and a scripted background/foreground/
  interruption sequence per source mode, complete with zero crashes.
- **SC-010**: In usability testing, at least 90% of participants correctly identify which source
  mode is active and whether audio is being received, on first attempt.
- **SC-011**: A privacy review confirms zero instances of raw audio written to storage or sent
  off-device.

## Assumptions

- Target users are iPhone and iPad owners who want visuals for music playing on their device or in
  the room.
- System/App Capture availability depends on the OS version; the presumed primary path requires a
  recent iOS release (iOS 27 or later). The exact minimum OS, whether earlier versions get only
  fallback modes, and whether a legacy capture path is needed are left to `/speckit-clarify` and
  planning.
- iPad is assumed to be a launch requirement (responsive layout is in scope); if clarified
  otherwise, FR-032's iPad test and FR-041's split-window behavior become non-blocking.
- If no external-app source passes Stage 1, the first release ships with Microphone and In-App
  Playback only, honestly described (see Delivery Gating). This default should be confirmed during
  `/speckit-clarify`.
- Capture and visualization run while the app is in the foreground; background visualization is
  out of scope. Background capture continuation is investigated in Stage 1 but not promised.
- The app does not draw over other apps.
- Users have no accounts; favorites are stored on the device only.
- User import of custom presets is out of scope for this feature.
- Thresholds (silence −60 dBFS / 2 s, no-audio 5 s, controls auto-hide 5 s) are initial defaults to
  be tuned in Stage 1 and recorded.
- The ProjectM engine (MilkDrop-compatible) is a fixed product dependency named by the stakeholder;
  its version, license, and rendering approach are decided in planning.
- Building and testing on Apple hardware is required for all device and performance criteria;
  results from other environments are not accepted as evidence.

### Out of Scope (non-goals)

- Bypassing DRM, protected content, OS privacy controls, or using non-public capabilities.
- Guaranteed compatibility with Spotify, Apple Music, YouTube Music, or any specific app.
- Combining microphone and system capture simultaneously.
- Recording, saving, sharing, or streaming audio or video.
- Music playback/streaming service features.
- Overlaying visuals on top of other apps.
- Downloading community presets.
