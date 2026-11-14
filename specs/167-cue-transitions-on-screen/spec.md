# Feature Specification: XFADE Cue Transitions On Screen

**Feature Branch**: `fix/cue-transitions-on-screen` (spec directory `167-cue-transitions-on-screen`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (XFADE-T01-T08 verified on the Mac: Compositor host tests and the feature's own
iOS 27.2 simulator "XFADE"; no device claim). Compositor 518 tests (7 skipped, pre-existing; 9 new), app
`CueTransitionStageTests` 2, `CueTransitionUITests.testACueCrossfadeShowsOnScreen` 7.5 s. Open follow-up: native
visuals and projectM still change with a cut (their frames do not pass through a compositor output pass).

**Input**: Follow-up to CMP-014 (transition bus, ADR-0042) and SCN-007 (transition presets,
`specs/158-scn-007-transition-presets`); not a new roadmap row. SCN-007 stores a transition per cue and
resolves it to a `SceneTransitionSpec`, but the app's driver (`CueTransitionRecorder`) only records it, so on
screen every cue is an instant cut. Goal: when a cue applies a scene, the visible output goes from the old
look to the new one with the cue's stored transition, wherever that is feasible, and degrades to today's cut
where it is not.

Identifiers: requirements `XFADE-R1…`, success criteria `XFADE-S1…`, tasks `XFADE-T01…`. Other features are
cited by their own IDs: CMP-001 (compositor), CMP-013 (render caching), CMP-014 (bus, clock, weights), SCN-007
(cue transitions), FX-009 (trails), FX-019 (composite flash guard), ACC-001 (Reduce Motion), ACC-012 (sensory
safety envelope), PERF-004 (texture pool), REC-001/REC-003 (capture, recording), OUT-001/OUT-002 (external
display), VIS-001…VIS-004 (native visuals), MED-001/002/009/010 (photo, video, text, logo).

## Baseline: what exists today (audit of 2026-11-14, commit `36cc239a`)

| Visual | How it renders | Output pass |
|---|---|---|
| Photo, Video, Text (each with Logo; Trails), Camera | One CMP-001 `Compositor` per host (`PhotoVisualHost`, `VideoVisualHost`, `TextVisualHost`, `CameraVisualHost`), `composite(into:)` into a `CAMetalLayer` drawable on the host's own command queue; all hosts share one PERF-004 pool per device (`SharedTexturePool`). The finished frame (composite or FX-009 trails frame, `rgba16Float`, linear premultiplied) goes through the FX-019 flash guard and `cmp_output` (grade, tone map); REC-003 repeats that pass with `encodeOutput`, REC-001 captures it. | yes |
| Circular and linear spectrum, oscilloscope, Lissajous | `NativeSpectrumHost` draws straight into its drawable (generator plus FX-001 glow); recording copies the drawable. | no compositor |
| projectM | ANGLE (GL on Metal) in its own layer; preset changes blend inside projectM. A scene never stores a preset (`ShowSceneSnapshot`: projectM is `[]`), so no cue changes only the preset. | no compositor |
| Transition bus (CMP-014) | `SceneTransitionBus` holds two whole compositors, runs both stacks (`encodeScene`, no FX-020 grade pass) and its own flash guard and output pass. No app code creates one. | own |
| Cue apply (SCN-007) | `ShowCoordinator.apply` → `transitionDriver.driveTransition(resolved spec)` → `applyScene` sets the live settings; a visual change releases the old host and creates and resumes the new one synchronously (`visualSettingsChanged`). | — |

## Clarifications

### Session 2026-11-14 (spec)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the
conservative, local-first option.

- Q: Two live scenes (option a) or a frozen last frame (option b)? → A: **(b) frozen frame.** When a cue with a non-instant transition applies, the shown compositor's last finished frame (the texture its flash guard and output pass used) is copied into one pooled texture; the incoming scene renders live, and its compositor's output pass shows the CMP-014 mix of the frozen frame and the live frame. Option (a) is rejected: it doubles the render cost for the whole transition and needs two live layer stacks (two hosts, two decoders, the camera twice).
- Q: Use `SceneTransitionBus` itself? → A: No: the bus would replace each host's own output path (its own flash guard history, no FX-020 grade pass, its own capture and recording outputs). The frozen-frame blend lives in the compositor's own output path and reuses CMP-014's pieces exactly: `SceneTransitionClock` (frame presentation times), `SceneTransitionMix.weights` (cut, crossfade, dip to black), the same weighted-sum shader formula, and the PERF-004 pool. So the flash guard keeps one history, and recording, capture and the external display repeat the blended frame because it is the shown frame.
- Q: Which visuals transition? → A: Every transition whose outgoing **and** incoming visuals are compositor-backed: Photo, Video and Text (with Logo and Trails) in any combination, within one host (Text → Text) or across hosts (Photo → Text); Camera can be the outgoing one (a scene never selects Camera). A transition from or to a native visual (spectra, oscilloscope, Lissajous) or projectM is a cut, exactly as today, recorded as the outcome "unsupported" in the DEBUG probe: their frames never pass through a compositor output pass, so a blend there could not be measured by the flash guard or shown in recording. This is a follow-up, not a regression.
- Q: projectM preset changes? → A: Scenes store no preset, so no cue changes only the preset; projectM's own preset blend is untouched. A cue that changes the visual to or from projectM is a cut.
- Q: A cue applied while a transition runs? → A: **Restart from the current blended frame**: the frozen frame is taken from what is shown now (the blend), the old frozen frame and blend target are released, and the new transition starts at progress 0 from that frame. No jump, no snap.
- Q: Frame sizes differ (rotation, external display resize) during a transition? → A: The transition ends at once (the live scene alone, as a cut) and its textures are released.
- Q: Grade and tone map? → A: The frozen frame is taken before the output pass, so the output pass grades and tone-maps the blend with the current grade (one grade for both scenes; the grade is an app setting, not part of a scene).
- Q: Trails? → A: FX-009-R5 as CMP-014: a transition start resets the incoming compositor's trails; the frozen frame is a separate copy and never enters the trails history.
- Q: Pause? → A: The CMP-014 clock adds at most one clamped frame step across a gap, so a paused visual resumes its transition where it was.
- Q: Cross-queue safety? → A: The copy is encoded on the outgoing host's own queue after its last frame and signals a Metal event; the incoming compositor waits for that event in every transition frame. The copy's command buffer also fences the outgoing compositor's pictures in the pool, so a released host's composite is never handed out before the copy has read it.
- Q: Texture cost? → A: Two pooled `rgba16Float` textures at the output size while a transition runs (the frozen frame and the blend target), one mix pass per frame, and nothing when idle (the mix pipeline is built at the first transition). Both go back to the pool at the end, on a cut, on an interruption, on a size change and when the compositor is released.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A cue's crossfade is visible (Priority: P1) — MVP

A performer sets cue 2 (a Text scene) to a 1 s crossfade and presses Next while cue 1 (another Text scene)
is shown. The old text fades into the new one over one second on the screen, in the recording and on the
external display.

**Independent Test**: GPU test of the compositor with an injected 60 Hz clock: A solid red, B solid blue.

**Acceptance Scenarios**:

1. **Given** A red shown and a 1 s linear crossfade to B blue, **When** frames are encoded at 60 Hz, **Then** the frame at t = 0 is A byte for byte, at 0.5 s the output is (0.5, 0, 0.5) in linear light, and at 1 s it is B byte for byte.
2. **Given** an easeIn (exponent 2) curve, **When** t = 0.5 s, **Then** the mix is 0.25 B.
3. **Given** a dip to black, **When** t = 0.5 s, **Then** the output is black.
4. **Given** a cut, **When** a cue applies, **Then** nothing is frozen and the frames are byte-identical to today's.

### User Story 2 - Safety still wins (Priority: P1)

**Acceptance Scenarios**:

1. **Given** Reduce Motion, **When** a crossfade cue applies, **Then** the change is a cut.
2. **Given** Reduce flashing and a cut cue, **When** it applies between compositor visuals, **Then** a 0.5 s crossfade shows (SCN-007-R6).
3. **Given** a strobing sequence of short transitions between white and black, **When** frames are shown, **Then** the flash guard lowers the gain of the blended frames.

### Edge Cases

- A visual change to or from a native visual or projectM: a cut (outcome "unsupported").
- A cue during a transition: restart from the blended frame.
- 20 transitions in a row: the pool's checked-out count returns to its idle value.
- The outgoing host was released before the incoming one drew: the frozen frame stays valid (it is a copy).

## Requirements *(mandatory)*

- **XFADE-R1**: When a cue applies with a non-instant resolved spec and the shown visual is compositor-backed, the app copies the shown frame (`Compositor.freezeShownFrame`) before the scene is applied, and after the apply starts the transition on the compositor shown then (`beginOutputTransition`).
- **XFADE-R2**: During the transition the compositor's shown frame is the frozen frame at progress 0, the CMP-014 mix of the frozen frame and the live frame at 0 < progress < 1, and the live frame alone from progress 1; the clock is CMP-014's on the frame presentation times, with the spec's easing or MOD-004 curve.
- **XFADE-R3**: The flash guard (with the ACC-012 envelope), the output pass, `encodeOutput` (REC-003, OUT-001/002) and frame capture (REC-001) all use the shown (blended) frame.
- **XFADE-R4**: A cut, an instant spec, or Reduce Motion freezes nothing and changes nothing on the output path (byte-identical to today).
- **XFADE-R5**: A transition start resets the incoming compositor's trails (FX-009-R5).
- **XFADE-R6**: The frozen frame and the blend target come from the PERF-004 pool and return to it at the end, on a cut, on an interruption, on a size change and on release; idle frames take nothing.
- **XFADE-R7**: A cue during a transition restarts from the current shown (blended) frame.
- **XFADE-R8**: A transition from or to a native visual or projectM is a cut; the DEBUG probe reports it as unsupported.
- **XFADE-R9**: A DEBUG probe (`-uitestDiagnostics` builds only) reports the last outcome, the blended frame count, the progress and whether textures are held.

## Success Criteria *(mandatory)*

- **XFADE-S1**: The red/blue GPU acceptance (US1 scenarios 1-3) passes on the host.
- **XFADE-S2**: A cut is byte-identical to a compositor that never transitioned; Reduce Motion gives a cut.
- **XFADE-S3**: After 20 transitions the pool's checked-out count equals the idle count.
- **XFADE-S4**: The flash guard's gain falls below 1 on a strobing transition sequence.
- **XFADE-S5**: An app test applies a cue with a stored 1 s crossfade through `ShowCoordinator` and the app's driver, and the incoming compositor blends exactly 59 frames at 60 Hz.
- **XFADE-S6**: A UI test under 30 s steps between two Text cues and reads a blended transition from the probe.
