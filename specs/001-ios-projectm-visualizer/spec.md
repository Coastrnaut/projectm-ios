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

## Clarifications

### Session 2026-11-07

- Q: What is the minimum iOS version the app must support? → A: iOS 26 and later. System/App
  Capture is offered only on OS versions that provide the required system capture flow (presumed
  iOS 27+, pending RI-001/RI-004); iOS 26 devices get Microphone and In-App Playback only. No
  legacy (ReplayKit) capture adapter. *(Note added 2026-11-08: the "presumed iOS 27+" part is
  superseded by FR-008; RI-004 confirmed iOS/iPadOS 27.0.)*
- Q: If Stage 1 shows that no other app's audio can be captured, may the first release ship with
  only microphone and in-app playback? → A: Yes. The release proceeds with the fallback modes,
  honestly described.
- Q: Is iPad support required for the first release? → A: Yes. iPhone and iPad are both launch
  requirements, including split-screen/resizable windows on iPad.
- Q: What is the oldest hardware that must be supported? → A: Any device that runs iOS 26. The
  oldest iOS 26-capable iPhone and iPad obtainable are the minimum test devices; their performance
  is measured and published, not promised in advance. *(Test-device part superseded by Session
  2026-11-08: the project device set D1–D3.)*
- Q: Must the first release be distributed through the public App Store? → A: Yes. A license and
  App Store compliance review of all bundled components (including the LGPL-2.1 visualization
  engine) is a release-blocking requirement.

### Session 2026-11-08

- Q: Which physical devices does the project test on? → A: Only the three devices the project
  owner has: **D1** iPhone 15 on iOS 27.0.1 (reference device), **D2** iPad Pro 13-inch (M5) on
  iPadOS 27.2, and **D3** iPad (A16) on iPadOS 26.5 (see `docs/test-reports/devices.md`). No other
  devices will be bought. The roles "second capture-capable iPhone", "iPhone on iOS 26", and
  "current-generation iPhone" are **not applicable**. Their absence does not block any phase or
  gate. The consequence is a limit on claims, not on development: compatibility and performance
  claims cover only the device classes and OS versions actually tested (FR-062).

## Delivery Gating *(mandatory for this feature)*

This feature is delivered in stages. Each stage maps to the constitution's phases and gates:

| Stage | Constitution phase | Gates that must pass to exit | User stories |
|-------|--------------------|------------------------------|--------------|
| Stage 1 — Capture Feasibility | Phase 0 | Gate 0 (API availability), Gate 1 (external samples), Gate 2 (sustained capture) | US1–US3 |
| Stage 2 — Full Visualizer | Phases 1–3 | Gate 3 (engine build/render), Gate 4 (end-to-end) | US4–US7 |
| Release | Phase 4 | FR-064 license/App Store review, privacy review (SC-011) | — |

Stages and phases run strictly in sequence: a phase starts only after the previous phase's exit
evidence is reviewed and approved (constitution workflow). No phase work runs in parallel with an
earlier phase.

**Gate criteria** (each gate's go/no-go rule and evidence artifact):

| Gate | Go criterion | Evidence artifact |
|------|--------------|-------------------|
| Gate 0 — API availability | RI-001 and RI-004 exit criteria met; ADR-0001 and ADR-0002 accepted | `docs/platform-research/screencapturekit-ios.md`, ADRs |
| Gate 1 — External samples | Every FR-030 source has an FR-031 entry from at least the devices in SC-001 | compatibility report + diagnostics exports |
| Gate 2 — Sustained capture | For each source rated "Works": a 30-minute foreground capture on the reference device with zero unrecovered stream failures, dropped audio under 1%, median start-to-first-audio under 2 s, capture-plus-classifier CPU under 15% of one core (the normalizer pipeline is built and measured in Plan Phase B), and memory growth of 10% or less (minute 5 vs minute 30); RI-003 device evidence recorded for each lifecycle event on D1 and D2 (T041; owner ruling 2026-11-08) | report rows + exports |
| Gate 3 — Engine build/render | ADR-0003 exit thresholds met and ADR-0003 accepted | ADR-0003 measurements |
| Gate 4 — End-to-end | SC-005 to SC-010 and SC-013 met with each available source mode | test report |

**Approver**: The project owner approves every stage transition and records the decision, date, and
evidence in the compatibility report (FR-033).

**Stage 2 approval rule**: Stage 2 MAY start only when all of the following are true:

1. The compatibility report (FR-030–FR-033) exists, has been reviewed, and records at least one
   source mode with verified non-silent audio on a physical device.
2. RI-007 (engine license / App Store compliance) and RI-010 (upstream's App Store warning) have
   preliminary written conclusions that App Store distribution is achievable, so Stage 2 is not
   built on a component that cannot ship.

If no external-app source passes, Stage 2 and the first release proceed with Microphone and In-App
Playback only, and that limitation is stated in the product description and store listing.

**Stage 2 acceptance rule**: User Stories 4 and 5 cannot be accepted until Gate 3 passes (RI-005:
a known preset renders on a physical device). Capture evidence alone is not sufficient.

**Release rule**: The release cannot be submitted until RI-007 and RI-010 have final go conclusions
(FR-064, ADR-0005), the privacy review (SC-011) has passed, the privacy manifest and App Privacy
disclosure are complete (FR-066), and the Licenses screen is complete (FR-067).

**Reference device**: The newest capture-capable iPhone available to the project, chosen and
recorded in `docs/test-reports/devices.md` before Phase A testing starts (FR-034). The same device
is used for Gate 2, SC-005 to SC-009, SC-013 to SC-015, and ADR-0003.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Verify external-app audio capture (Priority: P1)

A tester starts music in another app (for example a streaming app or a browser video), opens the
feasibility app, taps **Choose Audio Source**, picks System/App Capture, and selects a source in
Apple's system sharing prompt. The app shows live diagnostics proving whether real audio is
arriving: sample count, sample rate, channel count, timestamps, buffer cadence, and peak/RMS level.
It reports exactly one audio state (FR-010), distinguishing "No audio received", "Audio received —
silent", and "Active audio".

**Why this priority**: Whether other apps' audio can be captured at all is the central product risk.
Every later story depends on this answer.

**Independent Test**: On a physical device, play audio in a source app, start capture, and confirm
the diagnostic screen classifies the stream correctly for a playing source, a paused source, and a
source that delivers nothing.

**Acceptance Scenarios**:

1. **Given** an OS that offers System/App Capture (FR-008) and a source app playing audible content,
   **When** the user starts System/App Capture and confirms the system prompt, **Then** the app
   displays "Active audio" only after the FR-011 active threshold is met, and shows sample rate,
   channel count, and level updating at least once per second.
2. **Given** capture is running with "Active audio", **When** the source app is paused, **Then** the
   status changes to "Audio received — silent" within 2 seconds while sample counters keep
   increasing.
3. **Given** capture has started, **When** no audio data arrives for 5 seconds after start, **Then**
   the app shows "No audio received" and suggests choosing another source or using Microphone.
4. **Given** the user cancels the system picker, **When** control returns to the app, **Then** the
   app shows "Not started — cancelled" and remains usable. If the user instead declines screen
   recording, the app shows "Screen recording not allowed" and remains usable (owner ruling
   2026-11-08).
5. **Given** a device whose OS does not offer System/App Capture (e.g., iOS 26), **When** the user
   opens the source chooser, **Then** System/App Capture is shown as unavailable with the reason
   "Requires a newer iOS version", and Microphone and In-App Playback remain selectable.

---

### User Story 2 - Fallback sources: microphone and in-app playback (Priority: P1)

A user who cannot (or chooses not to) capture another app's audio selects **Microphone** or
**In-App Playback**. Microphone mode explains that it hears sound in the room. In-App Playback plays
a bundled reference audio track the app itself controls, audibly through the current output. Each
mode is labeled unmistakably.

**Why this priority**: Fallbacks guarantee the product works on every supported device regardless
of external-capture results, and In-App Playback provides a repeatable reference for testing.

**Independent Test**: Select each fallback mode on a device with System/App Capture unavailable and
confirm audio diagnostics (Stage 1) or visuals (Stage 2) respond, with the correct label shown.

**Acceptance Scenarios**:

1. **Given** microphone permission has not been requested, **When** the user selects Microphone,
   **Then** the app explains that it captures ambient sound and then requests permission.
2. **Given** microphone permission is denied, **When** the user selects Microphone, **Then** the app
   shows "Microphone permission denied" with how to enable it in Settings, and offers other sources.
3. **Given** permission is granted but no microphone input is available, **When** the user selects
   Microphone, **Then** the app shows "Microphone unavailable" and offers other sources.
4. **Given** the user selects In-App Playback, **When** playback starts, **Then** the reference
   track is audible, the source label reads "In-App Playback", and the audio state reaches "Active
   audio" within 1 second.
5. **Given** the reference track cannot be played, **When** the user selects In-App Playback,
   **Then** the app shows "In-App Playback failed" and offers other sources.
6. **Given** any fallback is active, **When** the user views the source indicator, **Then** it never
   reads as System/App Capture.
7. **Given** any fallback is active, **When** the user taps Stop, **Then** the source stops within
   1 second and the state shows "Stopped".

---

### User Story 3 - Source compatibility report (Priority: P1)

The product team runs a defined test procedure on physical devices for each candidate source
(Spotify, Apple Music, YouTube Music, Safari video, in-app reference audio, microphone) and records
the results in a compatibility report that decides what the product may claim.

**Why this priority**: The report is the go/no-go evidence that gates Stage 2 and bounds every
compatibility claim the product makes.

**Independent Test**: Review the report and confirm every tested source has a complete entry and a
result on the FR-031 scale, reproducible from its recorded steps.

**Acceptance Scenarios**:

1. **Given** a test run on a physical device, **When** the tester exports diagnostics, **Then** the
   export contains the FR-021 fields and no raw audio or device identifiers.
2. **Given** a source delivers no audio or only silence, **When** it is recorded, **Then** the report
   marks it "Does not work" for that device/OS/source-app version with the observed behavior.
3. **Given** the report is complete, **When** Stage 2 approval is reviewed, **Then** the approval
   decision, approver, date, and list of claimable sources are recorded in the report.

---

### User Story 4 - Full-screen visualization of live audio (Priority: P2)

A user with an active audio source sees a full-screen visualization driven by that audio, with the
audio-to-visual delay defined in SC-006. Tapping the screen reveals or hides controls. The
visualization adapts to portrait and landscape on iPhone and iPad.

**Why this priority**: This is the core user value once feasibility is proven.

**Independent Test**: With In-App Playback active, open the visualizer and confirm visuals react to
the music, fill the screen in both orientations, and controls toggle on tap.

**Acceptance Scenarios**:

1. **Given** an active audio source, **When** the visualizer is open, **Then** the visualization
   fills the screen, and an audible impulse produces a visible change within the SC-006 delay.
2. **Given** controls are hidden, **When** the user taps the screen, **Then** controls appear;
   **When** the user does not interact for 5 seconds, **Then** they hide again.
3. **Given** the device is rotated, **When** orientation changes, **Then** the visualization and
   controls re-lay out within 1 second without restarting capture.
4. **Given** an iPad in split-screen or a resized window, **When** the window size changes, **Then**
   the visualization fills the available area and all controls remain reachable within 1 second.

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
2. **Given** the preset browser is open, **When** the user selects a preset, **Then** the browser
   closes, the selected preset becomes active within 1 second, and its name is displayed.
3. **Given** the user favorites a preset, **When** the app is relaunched, **Then** the preset is
   still marked as a favorite and appears when the browser is filtered to favorites.
4. **Given** a preset fails to load, **When** it is selected, **Then** the app shows "Preset could
   not be loaded", keeps the previous preset running, and does not crash.

---

### User Story 6 - Source status and capture control (Priority: P2)

At any time the user can see which source is active (System/App Capture, Microphone, or In-App
Playback), whether audio is actually arriving, and why capture stopped if it did. The user can pause
the visualization and stop capture.

**Why this priority**: Truthful status builds trust and makes failures understandable.

**Independent Test**: Exercise start, pause, resume, stop, switch, and an OS-ended capture; confirm
the indicator and messages match reality at each step.

**Acceptance Scenarios**:

1. **Given** capture is active, **When** the user taps Stop, **Then** capture ends within 1 second,
   the indicator shows "Stopped", and no further audio is received.
2. **Given** the visualization is paused, **When** the user resumes, **Then** visuals continue from
   the live source without re-selecting it.
3. **Given** the OS ends the capture session (e.g., user stops sharing from system UI), **When**
   this occurs, **Then** the app shows "Ended by system" within 2 seconds and offers to choose a
   source.
4. **Given** a source is active, **When** the user switches to another source, **Then** the old
   source stops first, the indicator shows the new mode with "Waiting", and it shows "Active audio"
   only after the new source meets the FR-011 active threshold.

---

### User Story 7 - Lifecycle and interruption resilience (Priority: P3)

The app behaves predictably when the user leaves the app, locks the device, receives a phone call,
connects or disconnects headphones, or the system interrupts audio.

**Why this priority**: Prevents crashes and confusing states in everyday use.

**Independent Test**: Run a scripted sequence of background/foreground, lock/unlock, interruption,
and audio-route changes during each source mode and confirm the FR-050–FR-055 behavior with no
crash.

**Acceptance Scenarios**:

1. **Given** any source is active, **When** the app moves to the background or the device locks,
   **Then** the visualization pauses; on return, the app follows FR-050 for that source mode.
2. **Given** an audio interruption (e.g., a call) during Microphone or In-App Playback, **When** the
   interruption ends and the OS indicates audio may resume, **Then** the source resumes
   automatically within 2 seconds; otherwise the state shows "Interrupted" with a one-tap restart.
3. **Given** In-App Playback is playing through headphones, **When** the headphones disconnect,
   **Then** playback pauses and the state shows "Paused — audio route changed".
4. **Given** Microphone is active, **When** the input route changes, **Then** capture continues on
   the new input or the state shows "Microphone unavailable", without crashing.

---

### Edge Cases

Each edge case below maps to a functional requirement.

- OS version lacks the system capture flow → FR-004, FR-008.
- User cancels the system sharing prompt → US1-AS4, FR-015.
- Source delivers no audio data vs. delivers silent audio → FR-010, FR-011, FR-012.
- Protected or excluded content (DRM) → reported as "No audio received" or "Audio received —
  silent"; the app never attempts to work around it and never claims the source works (FR-003,
  FR-062).
- Source app starts/stops playback mid-session → FR-011 transitions; prolonged silence → FR-018.
- Audio format changes mid-stream (sample rate or channel count) → FR-017.
- Capture ended by system, device lock, or app backgrounding → FR-050, FR-054, US6-AS3.
- Rapid repeated start/stop or source switching → FR-052.
- Microphone permission revoked in Settings while backgrounded → FR-053.
- Bundled preset missing or malformed → FR-045.
- Very long session (30+ minutes) → SC-008.
- Low-power mode or thermal pressure → FR-049, SC-013.

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
  as unavailable with the reason "Requires a newer iOS version" while keeping fallback modes
  available. On an OS that supports it, if the OS reports that screen recording is not allowed on
  this device, the mode MUST show as unavailable with the reason "Screen recording not allowed"
  (owner ruling 2026-11-08).
- **FR-005**: Microphone mode MUST explain, before requesting permission, that it captures ambient
  sound in the room. If no microphone input is available, it MUST report "Microphone unavailable".
- **FR-006**: In-App Playback MUST provide at least one bundled reference audio track with verified
  redistribution rights. The track MUST be audible through the current output route at the system
  media volume, MUST loop until stopped, and MUST report "In-App Playback failed" if it cannot play.
- **FR-007**: Users MUST be able to stop the active source, in every mode, at any time; the source
  MUST stop within 1 second.
- **FR-008**: The app MUST run on iOS/iPadOS 26 and later. System/App Capture MUST be offered only
  on OS versions where the required system capture flow is available: iOS/iPadOS 27.0 and later
  (RI-004, resolved 2026-11-08 from the iOS 27.2 SDK availability annotations; the iOS 26.5 SDK has no
  ScreenCaptureKit; see `docs/platform-research/screencapturekit-ios.md`). On iOS 26 it MUST appear
  as unavailable per FR-004.
- **FR-009**: The app MUST NOT include a legacy/deprecated capture path to provide System/App
  Capture on OS versions that lack the current system capture flow.

**Audio state truthfulness**

- **FR-010**: System MUST classify the active source as exactly one of: Not started, Waiting, No
  audio received, Audio received — silent, Active audio, Paused, Interrupted, Stopped, or Ended by
  system. "Active audio" is the canonical name for the state the README calls "Receiving audio";
  only "Active audio" is used in the UI. **Paused** means the app suspended the source itself
  (backgrounding, device lock, or lost output route) and will resume it automatically or on one
  tap; the source delivers no audio while Paused. Pausing the *visualization* (FR-046) never changes
  the audio state.
- **FR-011**: "Active audio" MUST be shown only after non-silent audio is verified during the
  current session: peak level at or above −50 dBFS for at least 250 ms. The state returns to "Audio
  received — silent" when peak level stays below −60 dBFS for at least 2 seconds. (Initial values;
  tuned per the threshold assumption.)
- **FR-012**: "No audio received" MUST be shown when no audio data arrives within 5 seconds of a
  successful capture start.
- **FR-013**: The source indicator MUST always show the active mode label, and Microphone or In-App
  Playback MUST never be labeled as System/App Capture.
- **FR-014**: The app MUST NOT display any third-party app name for System/App Capture unless the OS
  itself identifies the selected content **and** Active audio has been verified for it in the
  current session. When the OS does not identify the content, the label is "System/App Capture".
- **FR-015**: When a source stops or fails for any reason other than the user, the app MUST display
  one of these reasons: cancelled, permission denied, microphone unavailable, In-App Playback
  failed, interrupted, audio route changed, ended by system, unsupported OS, screen recording not
  allowed, or error (with a short description).
- **FR-016**: Switching sources MUST fully stop the previous source before the new one starts. While
  the new source is being classified, the indicator MUST show the new mode with "Waiting".
- **FR-017**: A mid-stream change in sample rate, channel count, or sample type MUST NOT stop the
  source or crash the app as long as the format can be converted; diagnostics MUST reflect the new
  format within 1 second. Streams with more than 2 channels are downmixed to stereo; unknown
  layouts use channels 1 and 2. Only a format that cannot be converted at all stops the source,
  with reason "error".
- **FR-018**: If the active source stays "Audio received — silent" for 60 seconds, the app MUST show
  a non-blocking hint (e.g., "No sound detected — is playback paused?") and MUST keep the source
  running.
- **FR-019**: Every permission prompt the app triggers MUST carry a usage description string that
  matches the in-app explainer for that mode (microphone text in contracts/ui-states.md). For
  System/App Capture the key is `NSScreenCaptureUsageDescription`, named by Apple's ScreenCaptureKit
  overview (RI-001, resolved 2026-11-08), with the text in contracts/ui-states.md; whether iOS 27
  shows or enforces it is recorded on device in T040.

**Feasibility diagnostics (Stage 1)**

- **FR-020**: The feasibility app MUST display live sample count, sample rate, channel count,
  first/last sample timestamps, buffer cadence, peak and RMS level, and the current audio state,
  updated at least once per second.
- **FR-021**: The feasibility app MUST let the tester export a diagnostics summary, only when the
  tester taps Export, as a human-readable file and a structured machine-readable file shared through
  the system share sheet. Contents: device model, OS build, app build, source mode, buffer arrival,
  non-silence result, sample rate, channel count, timing statistics (FR-022), the stop reason and
  stop detail (for System/App Capture including the OS's stop code; owner ruling 2026-11-08), and an
  optional free-text note the tester types (e.g., the source app's name; limited to 500 characters, with an
  on-screen reminder not to enter personal information). It MUST NOT contain raw audio,
  device identifiers (serial number, advertising or vendor identifiers), or account information.
- **FR-022**: The feasibility app MUST record dropped or late buffers and start-to-first-audio time.

**Compatibility report (Stage 1)**

- **FR-030**: A compatibility report MUST exist covering at minimum: Spotify, Apple Music, YouTube
  Music, Safari video, in-app reference audio, and microphone.
- **FR-031**: Each entry MUST record device model, exact OS build, development toolchain version,
  source app version, capture mode and selection made, whether audio arrived, whether it was
  non-silent, sample rate, channel count, average and worst observed latency, interruption/end
  behavior, result, and reproduction steps. Result scale:
  - **Works**: Active audio in at least 95% of one-minute windows across a 10-minute run with this
    app foregrounded, with dropped audio under 1%.
  - **Partial**: Active audio is observed, but the source misses the "Works" thresholds or works
    only for some content, or only until a lifecycle event (e.g., lock). The limitation MUST be
    written in the entry.
  - **Does not work**: No audio received, or silent only, throughout the run.
  Evidence for any rating is the diagnostics export(s) of the run. Screenshots of the picker or the
  app's UI are not evidence.
- **FR-032**: Testing MUST cover the project device set (Clarifications 2026-11-08): **D1** iPhone 15
  on iOS 27 (System/App Capture and fallbacks; reference device), **D2** iPad Pro (M5) on iPadOS 27
  (System/App Capture and fallbacks), and **D3** iPad (A16) on iPadOS 26 (the iOS 26 fallback-only
  path). An iOS 26 iPhone, a second capture-capable iPhone, and a current-generation iPhone are not
  applicable.
- **FR-033**: The report MUST record each stage decision (go/no-go), the approver, the date, the
  evidence used, and the list of claimable sources.
- **FR-034**: The report MUST live at `docs/test-reports/compatibility-report.md`, with one row per
  device × source with the FR-031 columns, and the concrete device models and OS builds for each
  FR-032 role recorded in `docs/test-reports/devices.md` before testing starts.

**Visualization and presets (Stage 2)**

- **FR-040**: System MUST render a full-screen visualization driven by the active source's audio,
  compatible with MilkDrop-style presets, meeting SC-005 and SC-006.
- **FR-041**: System MUST support portrait and landscape on iPhone and iPad, and resizable/split
  windows on iPad.
- **FR-042**: Tapping the visualization MUST toggle controls; controls MUST auto-hide after 5 seconds
  without interaction. A compact source-and-state indicator (mode label plus audio state) MUST stay
  visible when the controls are hidden, so the active source can be seen at any time (US6).
- **FR-043**: Users MUST be able to choose a preset from a browser (which closes on selection), go to
  next/previous/random, and see the current preset's name.
- **FR-044**: Users MUST be able to mark and unmark favorites, filter the browser to favorites, and
  have favorites persist across launches.
- **FR-045**: A preset that fails to load MUST be reported to the user, skipped, and MUST NOT
  interrupt the currently running visualization.
- **FR-046**: Users MUST be able to pause and resume the visualization independently of stopping
  capture.
- **FR-047**: Only presets with reviewed redistribution rights MAY be bundled.
- **FR-048**: A performance overlay showing frame rate and audio state MUST be available to users
  through a setting, off by default.
- **FR-049**: Under low-power mode or thermal pressure, the visualization MAY lower its frame rate
  (not below 30 frames per second) or its rendering resolution. It MUST NOT change audio-state
  accuracy, labels, or controls.

**Lifecycle**

- **FR-050**: On backgrounding, the app MUST pause the visualization. In-App Playback MUST pause;
  Microphone capture MUST stop. On return to the foreground:
  - Microphone and In-App Playback MUST resume automatically within 2 seconds if permission and the
    audio route still allow it; otherwise the state shows the FR-015 reason.
  - System/App Capture MUST continue if the system session is still delivering audio; otherwise
    the state shows "Ended by system". Whether the session survives backgrounding is measured in
    RI-003 and recorded in the report; it is not promised.
- **FR-051**: The app MUST handle audio interruptions and route changes without crashing. Microphone
  and In-App Playback MUST resume automatically when the OS indicates audio may resume; otherwise
  they show "Interrupted" with a one-tap restart. In-App Playback MUST pause when the output route
  is lost (e.g., headphones disconnected). For System/App Capture, an audio interruption does not by
  itself change the state: if the stream keeps delivering, the source continues; if the stream
  stops, the state is "Ended by system". The observed behavior is recorded under RI-003.
- **FR-052**: Starting, stopping, and switching sources MUST be safe when repeated at intervals as
  short as 200 ms (no crash, no duplicate sessions, final state matches the last action).
- **FR-053**: The app MUST detect permission changes (e.g., microphone revoked in Settings) when it
  returns to the foreground and show the "permission denied" reason.
- **FR-054**: Device lock MUST be handled exactly like backgrounding (FR-050).
- **FR-055**: After any non-user stop, the app MUST offer a one-tap way to restart the same source
  or choose another. For System/App Capture, that tap re-presents the system picker; the app never
  restarts capture without it (FR-002).

**Privacy and claims**

- **FR-060**: The app MUST NOT record audio to storage, upload audio, or send audio off-device. There
  is no setting that enables this in the first release.
- **FR-061**: Diagnostics MAY contain audio metadata (levels, formats, timing) but MUST NOT contain
  raw audio; diagnostics leave the device only through the tester-initiated export (FR-021).
- **FR-062**: The app, its documentation, and its store listing MUST NOT claim universal system-audio
  capture or guaranteed compatibility with any specific third-party app. Any claim MUST:
  - be limited to sources rated "Works" in the compatibility report;
  - be scoped to the OS version range and device class tested, as of the source-app version tested;
  - not present "Partial" sources as supported. They MAY be described only in in-app help, together
    with their recorded limitation;
  - cover iPad only if an iPad entry is rated "Works" for that source.
- **FR-063**: A privacy policy MUST be available before release. It MUST state: the three source
  modes and what each captures; the permissions requested and why; that audio is processed only in
  memory on the device and never recorded, stored, or transmitted; what is stored on the device
  (FR-065); that diagnostics leave the device only through a user-initiated export; and that no
  analytics or tracking are used.
- **FR-064**: The first release targets the public App Store. Before release, a recorded license
  and App Store compliance review MUST confirm that every bundled component (including the
  LGPL-2.1 visualization engine, presets, and reference audio) can be distributed there and how
  each license's obligations are met. A failed review blocks release.
- **FR-065**: On-device persistence MUST be limited to: favorites, the last-selected preset, user
  settings (FR-048, FR-072), and whether the photosensitivity notice was acknowledged (FR-071). No
  audio, listening history, or source-app history is stored.
- **FR-066**: The app MUST include a privacy manifest that declares every required-reason API it
  uses (including on-device settings storage) with an approved reason, and its App Privacy disclosure MUST state
  that no data is collected. Both are checked in the release review.
- **FR-067**: Settings MUST include a Licenses screen listing every bundled third-party component,
  preset pack, and asset with its license text and attribution, and, for LGPL-2.1 components, how to
  obtain the corresponding source and replace the library (per ADR-0005).
- **FR-068**: The app MUST make no network connections and MUST NOT include networking code paths,
  analytics, advertising, or third-party SDKs. The only way data leaves the device is the
  user-initiated diagnostics export (FR-021).
- **FR-069**: The microphone MUST be activated only in Microphone mode. System/App Capture MUST be
  configured to exclude microphone audio, and In-App Playback MUST NOT open any input.

**Accessibility**

- **FR-070**: Every control and the source/audio-state indicator MUST have accessible labels for
  screen readers. Audio-state changes MUST be announced to screen-reader users. Control text MUST
  scale with the system text-size setting.
- **FR-071**: On first launch, before any visualization is shown, the app MUST display a
  photosensitivity notice about flashing visuals. The user must acknowledge it.
- **FR-072**: The app MUST provide a "Reduce flashing" setting that limits rapid full-screen
  brightness changes. It MUST be on by default when the system Reduce Motion setting is on.

**User experience**

- **FR-080**: The source chooser MUST list all three modes. Each shows its label, a one-line
  description of what it captures (contracts/ui-states.md), and its availability, with the reason
  if unavailable.
- **FR-081**: On first launch the app MUST show the photosensitivity notice (FR-071), then the source
  chooser. On later launches it opens on the source chooser. No source starts until the user picks
  one (FR-002).
- **FR-082**: The controls overlay MUST contain: the source-and-state indicator, Stop, Pause/Resume
  visualization, Previous, Next, Random, the preset browser, the current preset name, and Settings.
- **FR-083**: Status and failure messages MUST appear as a non-modal banner with the actions listed
  in contracts/ui-states.md. Modal dialogs are used only by the system (picker and permission
  prompts).
- **FR-084**: While the visualization is running in the foreground, device auto-lock MUST be
  suppressed. It MUST be restored when the visualization is paused or stopped, or the app leaves the
  foreground.
- **FR-085**: While the visualization is paused, the last frame MUST stay on screen, dimmed, with a
  "Paused" label.
- **FR-086**: In the visualizer, the status bar and home indicator MUST hide while controls are
  hidden, except where hiding would hide the system's capture or microphone-in-use indicator
  (FR-089).
- **FR-087**: In compact width (including the smallest iPad split-view size), the overlay MUST use a
  single-row compact layout with the preset browser as a sheet; every FR-082 control stays
  reachable.
- **FR-088**: The preset browser MUST list presets alphabetically by display name. Random MUST never
  pick the current preset. When the favorites filter is on and there are none, it shows "No
  favorites yet — tap the star on a preset to add one."
- **FR-089**: The app MUST NOT obscure or suppress the system's screen-capture or microphone-in-use
  indicator. Whether full-screen presentation affects that indicator is recorded under RI-001.
- **FR-090**: CaptureLab is an internal test tool. It is distributed only to testers (e.g., via
  TestFlight) and is never submitted to the App Store.

### Key Entities

- **Audio Source**: A selectable origin of audio. Attributes: mode (System/App Capture, Microphone,
  In-App Playback), display label, availability on this device, current audio state, stop reason.
- **Audio State**: The truthfulness status of the active source (FR-010), with timestamps of the
  last transition and last non-silent sample.
- **Visualization State**: Running, paused by the user (FR-046, FR-085), or suspended because the
  app left the foreground (FR-050). Independent of Audio State.
- **Audio Diagnostics Snapshot**: Metadata about a capture session — sample count, sample rate,
  channel count, timestamps, cadence, peak/RMS, dropped buffers, start-to-first-audio time. Never
  contains raw audio or device identifiers.
- **Compatibility Test Record**: One row of the compatibility report (fields in FR-031), linked to
  a device, OS build, source app, and result.
- **Stage Decision**: A recorded go/no-go decision with approver, date, and evidence (FR-033).
- **Preset**: A visual program. Attributes: name, source/license, load status, favorite flag.
- **Favorites List**: The user's saved set of favorite presets; persists across launches.
- **User Settings**: Performance overlay toggle, Reduce flashing, photosensitivity notice
  acknowledged (FR-065).

## Success Criteria *(mandatory)*

### Measurable Outcomes

**Stage 1 (blocking)**

- **SC-001**: For every System/App Capture source in the test matrix, the compatibility report
  records a reproducible result on D1 (iPhone) and D2 (iPad). For Microphone and In-App Playback,
  it records a result on D1, D2, and D3. Zero entries rated "Works" lack an export showing non-silent
  audio.
- **SC-002**: The feasibility app classifies playing, paused, and absent audio correctly in 100% of
  20 scripted trials per available source mode.
- **SC-003**: Status changes from silent to active (and back) are shown to the user within 2 seconds
  of the audio change in 95% of trials.
- **SC-004**: Microphone and In-App Playback each reach "Active audio" within 2 seconds of starting
  with audible input, on every tested device.

**Stage 2**

- **SC-005**: On the reference device (see Delivery Gating), the visualization sustains at least 55
  frames per second for 95% of a 10-minute session with the visualizer in the foreground. Frame rate
  is computed from the renderer's frame-presentation timestamps over 1-second windows. On 120 Hz
  displays the visualization is capped at 60 fps. The minimum-supported devices' sustained rates are
  measured and published in `docs/test-reports/performance.md` and in the app's support notes.
- **SC-006**: Measured audio-to-visual delay is under 150 ms on the reference device. Method: play a
  sharp audible click through In-App Playback, film the device screen and speaker with a camera at
  240 frames per second or more, and measure the time from the click to the first visible change.
  Take the median of 20 clicks. (The target is confirmed against Stage 1 latency measurements.)
- **SC-007**: In 95% of switches across the bundled set, the new preset's first frame is presented
  within 1 second of the request. Any blend transition into it lasts no more than 2 seconds.
- **SC-008**: In a 30-minute session with an active source, the app's memory use at minute 30 is
  within 10% of its memory use at minute 5, peak memory stays under 300 MB on the reference device
  (D2 and D3 measured and published), and the app does not crash.
- **SC-009**: 50 consecutive start/stop/switch cycles at 200 ms intervals, and a scripted
  background/foreground/lock/interruption/route-change sequence per source mode, complete with zero
  crashes and a correct final state.
- **SC-010**: In usability testing with at least 8 participants who were not involved in development
  (at least 3 using an iPad), at least 90% of participants correctly identify which source
  mode is active and whether audio is being received, on first attempt.
- **SC-011**: A privacy review confirms zero instances of raw audio written to storage or sent
  off-device, and that persisted data matches FR-065 exactly.
- **SC-012**: Every control and status element passes a screen-reader audit (labeled, reachable,
  announced) on iPhone and iPad.
- **SC-013**: In a 30-minute session at 20–25 °C room temperature, unplugged, at 50% screen
  brightness, on the reference device (D1) and on D3: the device never reaches the
  critical thermal state, frame rate never drops below the FR-049 floor of 30 fps, and the app is
  never terminated for thermal reasons. Thermal states observed are recorded.
- **SC-014**: A 60-minute visualization session on the reference device at 50% brightness, unplugged,
  uses no more than 20% of battery (initial target; finalized at Gate 4 per the threshold
  assumption).
- **SC-015**: Cold launch to an interactive source chooser takes under 2 seconds on the reference
  device (D1) and under 4 seconds on D3.

## Assumptions

- Target users are iPhone and iPad owners who want visuals for music playing on their device or in
  the room.
- Minimum OS is iOS/iPadOS 26 (clarified). System/App Capture needs iOS/iPadOS 27.0 or later: RI-004
  confirmed this on 2026-11-08 from the iOS 27.2 SDK availability annotations (FR-008). Whether it
  delivers other apps' audio, and how it behaves across app lifecycle events, are still open until
  device testing (RI-002, RI-003).
- iPhone and iPad are both launch requirements (clarified).
- Supported hardware is any iOS 26-capable device; performance is measured and published only for
  the project device set D1–D3, and is not guaranteed for other devices (clarified 2026-11-07 and
  2026-11-08).
- If no external-app source passes Stage 1, the first release ships with Microphone and In-App
  Playback only, honestly described (clarified; see Delivery Gating).
- Distribution target is the public App Store (clarified); FR-064 makes the license review a
  release blocker.
- Capture and visualization run while the app is in the foreground. Background capture
  continuation is measured in Stage 1 (RI-003) but not promised.
- Users have no accounts; all persisted data stays on the device (FR-065).
- **Tunable thresholds**: silence −60 dBFS / 2 s, active −50 dBFS / 250 ms, no-audio 5 s,
  prolonged-silence hint 60 s, controls auto-hide 5 s, 55 fps, 30 fps floor, 150 ms, 200 ms
  cycle interval, 300 MB peak memory, 20% battery per hour, 2 s / 4 s launch. These are initial
  defaults. *Owner*: project owner. *Exit*: capture and classification thresholds (dBFS levels,
  timeouts, 200 ms cycle) are finalized in the Stage 1 compatibility report before Stage 2 starts;
  rendering and device thresholds (fps, 30 fps floor, 150 ms, memory, battery, launch, auto-hide)
  are finalized in `docs/test-reports/performance.md` at Gate 4. The affected FR/SC lines are
  updated at each exit.
- The "Works" thresholds (95% of windows, <1% dropped) in FR-031 follow the same owner and exit
  criterion as the tunable thresholds.
- The ProjectM engine (MilkDrop-compatible) is a fixed product dependency named by the stakeholder;
  its version, license, and rendering approach are decided in planning.
- Building and testing on Apple hardware is required for all device and performance criteria;
  results from other environments are not accepted as evidence.

**Open Research Items**

These cannot be settled by stakeholder decision; each needs documentation review or a
physical-device experiment. Owner for all items: project owner (until delegated). None may be
stated as fact in the plan until its exit criterion is met.

- **RI-001 — System capture capabilities in the chosen SDK** (blocks Gate 0; updates FR-002,
  FR-008, FR-014, FR-019): Which content-sharing picker modes and selection scopes (single app,
  window, or whole display) exist, which stream configuration options and audio output types exist
  on iOS/iPadOS in the selected SDK, which usage-description keys are required, whether app audio
  (not only microphone) is delivered, whether microphone audio can be excluded (FR-069), whether
  the OS identifies the selected content, and how the system capture indicator behaves when the app
  hides the status bar (FR-089). *Exit*: inventory written from the SDK headers and current Apple docs, saved in
  `docs/platform-research/`, with availability annotations.
- **RI-002 — External app audio while this app is foregrounded** (blocks Gate 1; updates FR-062
  claimable sources): Whether audio from the selected source arrives, non-silent, while the
  visualizer stays in the foreground, per source in the FR-030 matrix. *Exit*: compatibility report
  entries (FR-031) with diagnostics exports from physical devices.
- **RI-003 — Background modes and picker behavior** (blocks Gate 2; updates FR-050, FR-054;
  owner ruling 2026-11-08: not part of Gate 0, whose criteria are RI-001, RI-004 and the two ADRs): Required usage descriptions and background modes; what the system picker allows; whether
  capture survives backgrounding, device lock, and the source app changing. *Exit*: documented
  configuration plus device test results for each lifecycle event in User Story 7.
- **RI-004 — iOS 26 capture availability** (blocks Gate 0; updates FR-008, FR-004): Confirm that
  the required system capture flow is unavailable on iOS 26 (so iOS 26 = fallbacks only), and
  identify the exact first OS version that provides it. *Exit*: SDK availability annotations
  recorded; FR-008 updated with the exact version.
- **RI-005 — Visualization engine rendering on iOS** (blocks Gate 3 and acceptance of US4/US5;
  updates FR-040, SC-005): The pinned engine documents a need for OpenGL Core 3.3 or OpenGL ES 3.2;
  iOS provides only deprecated OpenGL ES 3.0. Determine the viable rendering path (e.g., a
  translation layer or a Metal-based renderer) and its preset compatibility. *Exit*: renderer ADR
  plus a known preset rendering on a physical device.
- **RI-006 — Engine version pin** (blocks Gate 3; updates the dependency record): The engine
  submodule currently points at an untagged upstream commit (`eae22de`, after v4.1.0;
  in-development 4.2.0). Decide whether to pin to a tagged release or keep the commit. *Exit*:
  dependency-pinning ADR naming the exact tag/commit.
- **RI-007 — LGPL-2.1 and App Store compliance** (preliminary conclusion blocks Stage 2 start;
  final conclusion blocks release; updates FR-064): How the engine's LGPL-2.1 obligations (for
  example, relinking provisions) can be met in an App Store app. *Exit*: written license review /
  ADR with a go/no-go conclusion.
- **RI-009 — Engine runtime library loading on iOS** (blocks Gate 3; updates ADR-0003): Whether the
  engine's GL resolver calls `dlopen` on iOS when the host supplies a load_proc, which libraries it
  tries, and whether that is acceptable for App Review. *Exit*: source-and-device analysis in
  ADR-0003. If loading cannot be avoided, a minimal documented patch disabling it on iOS (patch log)
  is the fallback.
- **RI-010 — Upstream's App Store warning** (preliminary conclusion blocks Stage 2 start; updates
  FR-064): Identify why the engine's build docs warn that Apple's terms may prevent Store use (for
  example, the license, or presets being runtime-interpreted code). Bundled, reviewed presets with
  no user import or download are the planned mitigation for the latter. *Exit*: written analysis in
  ADR-0005.
- **RI-011 — Engine iOS build configuration** (blocks Gate 3): The CMake configuration for iOS
  (system name and toolchain, GLES option, dynamic framework output, device and simulator slices).
  *Exit*: `scripts/build_projectm_xcframework.py` produces the xcframework on CI, with the
  configuration documented in ADR-0004.
- **RI-008 — Bundled preset and reference-audio sources** (blocks Gate 3 and Stage 1 In-App
  Playback; updates FR-006, FR-047): The engine repository ships only test presets. Identify a
  starter preset set and reference audio track with verified redistribution rights. *Exit*: license
  record for each bundled asset.

### Out of Scope (non-goals)

- Bypassing DRM, protected content, OS privacy controls, or using non-public capabilities.
- Guaranteed compatibility with Spotify, Apple Music, YouTube Music, or any specific app.
- Combining microphone and system capture simultaneously.
- Recording, saving, sharing, or streaming audio or video.
- Music playback/streaming service features.
- Overlaying visuals on top of other apps.
- Visualization or In-App Playback while the app is in the background.
- Downloading community presets or importing user presets.
- Localization: the first release is English only.
