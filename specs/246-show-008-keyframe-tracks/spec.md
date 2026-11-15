# Feature Specification: SHOW-008 Keyframe Tracks

**Feature Branch**: `feature/show-008` (spec directory `246-show-008-keyframe-tracks`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: Roadmap row SHOW-008 (P1, size L, depends on SHOW-007 and MOD-001, both integrated). Observable behavior,
verbatim: "Animate numeric and color parameters along timeline." Acceptance, verbatim: "At keyframe timestamps values
match stored samples exactly."

Identifiers carry the roadmap ID: requirements `SHOW-008-R1…`, success criteria `SHOW-008-S1…`, tasks `SHOW-008-T01…`,
research decisions `SHOW-008-D1…`. Other features are cited by their own IDs: SHOW-001 (show file, cue list), SHOW-002
(dwell), SHOW-005 (Hold = Pause, Skip), SHOW-007 (show timeline, seek, scrub, Loop), MOD-001 (parameter registry),
MOD-002 (audio feature bindings), MOD-017 (quantized parameter changes), MIDI-003 and OSC-003 (external live values),
ACC-003 (colour-blind-safe palette), ACC-005 (accessible sliders), ACC-012 (sensory safety clamp), UIX-011 (palettes),
SCN-015 (scene lock), SHOW-009 (keyframe easing, a later row).

## Baseline (audit of 2026-11-14, commit `c8dea0e1`)

| Area | What exists | Gap for this row |
|---|---|---|
| Show timeline (SHOW-007) | `ShowTimeline` maps a time to a cue and back (non-skipped timed cues end to end; Loop wraps). The transport's position is the active cue's start plus the playhead's elapsed time (an injected monotonic clock). A seek applies the destination cue once. | Nothing is scheduled within a cue: values change only at cue boundaries. |
| Parameters (MOD-001) | A typed registry (continuous, integer, boolean, enum, colour) with ranges. The native visual's live path (MIDI-003/OSC-003 `externalValues`) drives the four glow parameters per frame, then MOD-002 bindings, then ACC-012's clamp. | No source of values along time. |
| Colours (UIX-011) | Palettes are defined in sRGB and used in linear light; the native visual takes one palette (ACC-003's colour-blind-safe switch wins). | No colour parameter in the registry and nothing that changes a colour over time. |
| Show file (SHOW-001) | `show.json` version 1 with optional, leniently read fields (transitions, dwells, overrides, skip, folders, tags). | No place for tracks. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the conservative,
local-first option.

- Q: Where are tracks stored? → A: In the show (`show.json`), as an optional `tracks` list written only when the show has a track, with no version bump; older shows keep their bytes. A track names one parameter and holds its keyframes; a keyframe holds a time on the show timeline in whole milliseconds, a value (a number, or an sRGB colour with alpha, components 0…1) and the interpolation to the next keyframe.
- Q: Which interpolations? → A: Hold (the value stays until the next keyframe), Linear and Ease (smoothstep, slow at both ends). Colours interpolate in linear light (decoded from sRGB, mixed, encoded back). SHOW-009 adds more curves later.
- Q: How is "exactly" guaranteed? → A: Evaluation is a pure function of the timeline time. At a keyframe's time the result is the stored sample itself, bit for bit (never recomputed); between two keyframes the fraction is computed within that segment only, from integer times, so float drift cannot accumulate along the track. Before the first keyframe the first value holds; after the last, the last value holds.
- Q: Which parameters can a track drive? → A: The registry parameters the live path applies per frame (the four glow parameters: intensity, radius, threshold, knee) and one colour target, "Visual Colour", which paints the native visual in one colour while its track has a value (ACC-003's colour-blind-safe switch still wins). Other parameters are not offered; a stored track for any other well-formed ID is kept and reported as "not available", and drives nothing.
- Q: How do track values reach the output without changing the scene? → A: Through a live-value layer like MIDI-003/OSC-003: track values replace the manual glow values, MIDI and OSC live values replace track values (the performer's hands win), then MOD-002 bindings and ACC-012's clamp apply as before. Numbers are clamped to the registry range (values entered in the editor are clamped when stored, so the clamp never changes a keyframe's value). The stored scene and the settings are never rewritten; MOD-017 quantize does not apply to tracks.
- Q: When are tracks sampled? → A: Whenever the show has a position on the timeline: every display frame while playing, once after a seek (or a scrub's release, a loop wrap or a cue step) and once when paused (the time is frozen, so the look holds). A value is applied only when it differs from the last applied one, so a seek to a keyframe time applies that value exactly once. At Standby or off the timeline, tracks release their parameters (manual values return).

### Session 2026-11-14 (speckit-clarify)

Five questions, each answered with the recommended option (owner rules 4 and 9).

- Q: What value does Add Keyframe at Playhead store? → A: The track's evaluated value at the playhead when it has keyframes; otherwise the value the output uses now (the manual glow setting, clamped to the registry range; white for Visual Colour). The time is the transport's position rounded to whole milliseconds, or 0:00 at Standby or off the timeline.
- Q: Does an edit change the output at once? → A: Yes. After every track edit the tracks are sampled once at the current position (an unchanged value applies nothing), so the performer sees the edited value without a seek.
- Q: Do scenes capture track values? → A: No. Track values are a live layer like MIDI and OSC: scene capture, autosave and scene history read the manual settings, which tracks never write.
- Q: How are values edited? → A: Numbers with an ACC-005 accessible slider over the parameter's range (one swipe = one registry step, or 1/100 of the range) and the value as text; colours with the system colour picker (sRGB, opacity kept); interpolation with a three-way picker (Hold, Linear, Ease). A keyframe's time is set only by Add Keyframe at Playhead (move the playhead, add, delete the old one); the list is in time order.
- Q: Does Visual Colour use the colour's alpha? → A: The colour is stored and evaluated with alpha (exactness covers all four components); the visual uses red, green and blue (bars are opaque), so alpha has no visible effect in this version.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Glow rises along the show (Priority: P1) — MVP

A VJ has a timed show of three 30 s cues. They want the glow to rise from 0.2 at 0:00 to 1.5 at 0:30 and stay there,
then snap back to 0.4 at 1:00. They add a Glow Intensity track, add keyframes at those times and play the show.

**Independent Test**: A track with keyframes at 0, 30 s and 60 s (Linear, Hold, Linear); evaluating at each keyframe
time returns exactly the stored value; at 15 s it returns the linear midpoint; between 30 s and 60 s it holds 1.5.

**Acceptance Scenarios**:

1. **Given** the track, **When** the show plays across 0:30 with an injected clock, **Then** the glow intensity applied at 0:30 is exactly 1.5, and the sequence of applied values is the same on every run.
2. **Given** the show paused, **When** the performer seeks to 1:00, **Then** 0.4 is applied exactly once and nothing else is applied for the track.
3. **Given** a MIDI control mapped to glow intensity, **When** the performer moves it, **Then** the MIDI value wins over the track.
4. **Given** the show at Standby, **When** nothing plays, **Then** the glow is the manual setting.

### User Story 2 - Colour along the show (Priority: P1)

The VJ adds a Visual Colour track: deep blue at 0:00, magenta at 0:30 (Linear). The visual blends through colours in
linear light and is exactly the stored magenta at 0:30.

**Acceptance Scenarios**:

1. **Given** the colour track, **When** evaluated at 0:30, **Then** the colour equals the stored sRGB sample component for component.
2. **Given** the colour track, **When** evaluated at 0:15, **Then** each channel is the linear-light midpoint encoded back to sRGB.
3. **Given** ACC-003's colour-blind-safe palette is on, **When** the track plays, **Then** the colour-blind-safe palette is still shown.

### User Story 3 - Edit tracks (Priority: P1)

In Settings → Show → Keyframe Tracks the VJ adds a track for a parameter, adds a keyframe at the playhead, changes its
value and interpolation, and deletes keyframes or tracks. VoiceOver reads each keyframe ("0:30, 1.50, Linear").

**Acceptance Scenarios**:

1. **Given** the show at 0:15, **When** Add Keyframe at Playhead is chosen, **Then** a keyframe at 0:15 with the current value is stored and listed.
2. **Given** the scene is locked (SCN-015), **When** the editor opens, **Then** editing is refused and the controls are disabled.
3. **Given** a keyframe already at the playhead time, **When** Add Keyframe is chosen again, **Then** that keyframe's value is replaced (no duplicate time).

### Edge Cases

- A track with one keyframe holds that value at every time.
- Two keyframes cannot share a time on one track; adding at an existing time replaces the value.
- A keyframe after the end of the timeline is kept; evaluation never reaches past the end (the last value before it may still interpolate towards it).
- With Loop, the time wraps, so the track restarts from its value at 0:00 each pass.
- A track's parameter that is not available in this version is kept in the file, listed as "not available" and drives nothing.
- A file with a damaged track or keyframe (bad ID, non-finite number, colour component outside 0…1, mixed kinds, unknown interpolation, time out of range) loads with that item dropped and a counted warning; the rest of the show loads.
- Removing the last keyframe removes nothing else; a track without keyframes drives nothing.

## Requirements *(mandatory)*

### Functional Requirements

- **SHOW-008-R1**: The show MUST store keyframe tracks (at most 16 tracks, one per parameter; at most 256 keyframes per track, unique times 0…921,600,000 ms) as an optional field written only when present, read leniently with counted warnings, with no format version change.
- **SHOW-008-R2**: Evaluating a track at a keyframe's time MUST return the stored sample exactly (numbers and colours, every component bit for bit).
- **SHOW-008-R3**: Between keyframes, evaluation MUST follow the earlier keyframe's interpolation (Hold, Linear, Ease); colours MUST interpolate in linear light; before the first and after the last keyframe the nearest value MUST hold.
- **SHOW-008-R4**: Evaluation MUST be a pure function of the timeline time (no wall clock, no accumulated state), so playing across keyframes with the same clock gives the same values.
- **SHOW-008-R5**: Track values MUST be applied through a live-value layer under MIDI/OSC live values and before MOD-002 bindings and ACC-012's clamp, clamped to the parameter's range; they MUST NOT rewrite the stored scene or settings and MUST NOT be quantized.
- **SHOW-008-R6**: Tracks MUST be sampled every frame while the show plays, once after a seek, scrub release, step or wrap, and once on pause; a value MUST be applied only when it changed (a seek to a keyframe time applies it exactly once). At Standby or off the timeline the parameters MUST return to their manual values.
- **SHOW-008-R7**: The Visual Colour target MUST paint the native visual in the evaluated colour; ACC-003's colour-blind-safe palette MUST win.
- **SHOW-008-R8**: The editor MUST list tracks and keyframes, add a track, add a keyframe at the playhead (replacing one at the same time), edit a keyframe's value (clamped) and interpolation, and delete keyframes and tracks, with VoiceOver labels and ACC-005 sliders. Every edit MUST be refused while the scene is locked (SCN-015).
- **SHOW-008-R9**: No network access, no new UserDefaults key, no wall-clock assertions in tests; ShowControl MUST keep building on Linux.

### Key Entities

- **Keyframe track**: a track ID, a parameter ID and its keyframes in time order.
- **Keyframe**: time (ms on the show timeline), value (number or sRGB colour), interpolation to the next keyframe.
- **Track values**: the evaluated value per parameter at a time; the live-value layer applied to the output.

## Success Criteria *(mandatory)*

- **SHOW-008-S1**: For every keyframe of a numeric and a colour test track, evaluating at its time returns exactly the stored value (100% of keyframes, bit-exact).
- **SHOW-008-S2**: Midpoints follow the interpolation (Linear: halfway; Ease: halfway at the middle, a quarter-way point below linear; Hold: the earlier value).
- **SHOW-008-S3**: A seek to a keyframe time records exactly one application of that value; a repeated seek records none; playing across three keyframes with an injected clock gives the same recorded sequence twice.
- **SHOW-008-S4**: A show with tracks survives save and load unchanged; a damaged track or keyframe is dropped with a counted warning and the show still loads.
- **SHOW-008-S5**: A UI test (under 30 s) adds a track and a keyframe at the playhead and sees it listed.

## Assumptions

- Simulator results prove behavior only; a `{device}` task checks a glow ramp during a running show on D1.
- MIDI, OSC and keyboard control of tracks, curves beyond Hold/Linear/Ease (SHOW-009) and drawing tracks on a graph are out of scope.
- Tracks apply only to the native visuals' live path (the projectM engine's preset parameters are not driven).
