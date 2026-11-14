# Feature Specification: SHOW-004 Cue Transition Override

**Feature Branch**: `feature/show-004` (spec directory `224-show-004-cue-transition-override`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: Roadmap row SHOW-004 (P1, size S, depends on SCN-007 and SHOW-001, both integrated). Observable
behavior, verbatim: "Override default scene transition for a specific cue edge." Acceptance, verbatim: "Cue
override wins without altering scene default." Tech: scene timeline engine, monotonic clocks, Codable;
deterministic timeline tests + simulator.

Identifiers carry the roadmap ID: requirements `SHOW-004-R1…`, success criteria `SHOW-004-S1…`, tasks
`SHOW-004-T01…`, research decisions `SHOW-004-D1…`. Other features are cited by their own IDs: SHOW-001 (show and
cues, `show.json`), SHOW-002 (dwell, the optional per-cue field pattern), SHOW-003 (quantized cue steps), SCN-001
(scene document), SCN-003 (Duplicate Scene), SCN-007 (cue transitions), SCN-012 (repair report), SCN-015 (scene
lock), CMP-014 (transition bus), FILE-005 (library backup), ACC-004 (announcer lanes), ACC-005 (accessible sliders).

## Baseline (audit of 2026-11-14, commit `0ec67c56`)

| Area | What exists | What SHOW-004 adds |
|---|---|---|
| Scene transition (SCN-007) | Each cue entry in `show.json` carries the optional `transition` (type, duration 0…10 s, MOD-004 easing) for the scene it shows; nil = the scene appears at once. Edited in Settings → Show → "Transition…" (`CueTransitionView`, the editor's `transitionSheet`). The scene document (SCN-001) holds no transition. | This stays the **scene default** and is never changed by an override |
| Applying a cue (SHOW-001 `ShowCoordinator.perform` → `show` → `apply`) | Every step that moves (Next, Previous, Go to, timed advance, quantized step, pad, keys, MIDI, OSC, switcher) reads the scene, resolves the cue's transition (`CueTransitionResolver`: Reduce Motion, Reduce flashing) and drives it just before `applyScene` | The resolved transition is the cue's override when it has one, else the scene default |
| Optional per-cue fields (SHOW-002 `advanceAfter`) | Written only when set; read leniently (an invalid value is dropped with a counted warning); no version bump | An optional per-cue `transitionOverride`, same pattern |
| Scene lock (SCN-015) | Edits refused in `ShowCoordinator` (`refusedByLock`); navigation allowed | Editing an override is an edit (refused while locked) |
| Quantized steps (SHOW-003), crossfade bus (CMP-014) | Steps run through `stepNow` → `perform`; the bus takes a resolved `SceneTransitionSpec` | Nothing new: the override changes only which transition is resolved |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the conservative,
local-first option.

- Q: What is the "default scene transition"? → A: SCN-007's transition, as SCN-007 stores it: in the show, with the cue entry that shows the scene (the scene document SCN-001 holds no transition; SCN-007 rejected storing it there). It is what "Transition…" edits and what applies when nothing overrides it; without one the scene appears at once.
- Q: What is a "cue edge"? → A: The edge **into** a cue: every step that makes that cue active (Next, Previous, Go to Cue, a timed or quantized advance, the pad, keys, MIDI, OSC, the scene switcher). Rejected: a from→to pair (a cue reached from several cues would need one override per predecessor, and Go to Cue and the scene switcher have no single predecessor).
- Q: Where is an override stored? → A: In the show, as an optional `transitionOverride` object in the cue's entry in `show.json` (same fields and rules as SCN-007's `transition`: type, duration 0…10 s, easing), written only when set. Never in the scene document and never in the cue's `transition`, so the scene default keeps its value and its bytes. No format version bump.
- Q: How do the override and the default combine? → A: The override replaces the whole default (type, duration and easing) for that edge; it is not merged field by field. A cue without an override uses its scene default exactly as before. Reduce Motion and Reduce flashing then resolve whichever was chosen (SCN-007-R5, R6), so an override can never bypass the safety rules.
- Q: Can an override be "no transition"? → A: Yes: an override of type Cut makes that edge instant even when the default is a crossfade. "Use Scene Default" removes the override.
- Q: Where is it edited? → A: Settings → Show, per cue: context menu "Transition Into This Cue…", a leading swipe action "Into", and a VoiceOver action "Transition Into This Cue". The sheet is SCN-007's transition sheet with "Use Scene Default" as the first type choice and a footer naming the scene default. A cue with an override shows "Into this cue: Cut" under its label (VoiceOver ", into this cue Cut"); the SCN-007 line stays as it was.

### Session 2026-11-14 (speckit-clarify)

- Q: Does Duplicate Scene copy the override? → A: Yes, as it copies the SCN-007 transition and the SHOW-002 dwell (the copy behaves like its source). Templates (SCN-011) and scene packs (SCN-014) arrive without one.
- Q: What does an unknown override type in a file do? → A: As SCN-007: kept verbatim and written back, a warning names the cue and type, and applying it is a cut (the override still wins; the default is not used). An invalid override (bad duration, unreadable easing, wrong JSON type) is dropped with a counted warning; the cue then uses its scene default and the show still loads.
- Q: Does editing an override apply anything or move the show? → A: No. It saves at once and applies nothing (SHOW-001-R6); the next step into the cue uses it. It does not restart a SHOW-002 countdown (the dwell is unchanged).
- Q: Does the override need its own announcement? → A: No. Editing is silent like SCN-007 edits; a step announces what it always does (cue lane, ACC-004).
- Q: Does a backup carry it? → A: Yes, automatically: FILE-005 re-encodes `show.json` through the show's own decode and encode, which keep the override.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - One cue enters differently (Priority: P1) — MVP

A performer's scene "Sunrise" fades in with a 2 s crossfade wherever it is used. For cue 4, which follows a
blackout hit, they want Sunrise to snap in. They choose "Transition Into This Cue…" on cue 4 and pick Cut.
Stepping into cue 4 is now instant; stepping into cue 7 (also Sunrise) still crossfades; Sunrise's default is
untouched.

**Why this priority**: It is the roadmap row and its acceptance.

**Independent Test**: A show with two cues of one scene whose default is a 2 s crossfade; give the first an override
of Cut; step into each with a transition-driver spy; compare the scene file bytes and the defaults before and after.

**Acceptance Scenarios**:

1. **Given** cues A and B showing the same scene with a 2 s crossfade default and A carrying a Cut override, **When** the show steps into A, **Then** the transition driven is a cut.
2. **Given** the same show, **When** the show steps into B, **Then** the transition driven is the 2 s crossfade.
3. **Given** the override was set and both cues were stepped into, **Then** the scene file is byte-identical to before and both cues' default transitions are unchanged.
4. **Given** A's override is removed ("Use Scene Default"), **When** the show steps into A, **Then** the 2 s crossfade is driven.

### User Story 2 - The override survives the file (Priority: P1)

The performer quits and reopens the app; cue 4 still snaps in. A show without overrides is written exactly as
before.

**Independent Test**: Round-trip a show with overrides through the show file (equal values, identical bytes); compare a
show without overrides with the bytes the app wrote before this feature; read files with invalid or unknown
overrides.

**Acceptance Scenarios**:

1. **Given** a show with overrides (crossfade with custom easing, cut, unknown type), **When** it is encoded and decoded, **Then** every override is equal (bit-identical duration) and re-encoding gives the same bytes.
2. **Given** a show without overrides, **When** it is encoded, **Then** the bytes contain no `transitionOverride` key and equal SHOW-002's output.
3. **Given** a file whose override is not a valid transition, **When** it is read, **Then** the show loads, that cue has no override, and a warning counts it.

### User Story 3 - Edit it in the show editor (Priority: P1)

**Independent Test**: In the simulator, open "Transition Into This Cue…" on a cue, choose Cut; the row shows "Into
this cue: Cut"; choose "Use Scene Default"; the line disappears. With the scene locked the edit is refused.

**Acceptance Scenarios**:

1. **Given** a cue, **When** the performer chooses Cut in "Transition Into This Cue…", **Then** the row reads "Into this cue: Cut" and the show file stores it.
2. **Given** the scene is locked (SCN-015), **When** an override edit is attempted, **Then** it is refused with the lock message and nothing is saved.

### Edge Cases

- The show steps into a cue through a SHOW-003 quantized step or a SHOW-002 timed advance: the same override applies (every step goes through one path).
- A cue's scene is missing or needs repair (SCN-012): the override is used when the repaired scene is opened, as SCN-007's transition is.
- Reduce Motion is on: the override, like any transition, resolves to a cut; with Reduce flashing a Cut override becomes the 0.5 s crossfade (SCN-007-R6).
- The default is removed or changed while an override exists: the override still wins; removing the override later uses the new default.
- An override equal to the default is kept as an override (the performer chose it); nothing collapses it.
- Moving, renaming or reordering cues keeps each cue's override (it belongs to the cue ID).

## Requirements *(mandatory)*

### Functional Requirements

- **SHOW-004-R1**: Each cue MUST support an optional transition override with the same content and validation as an SCN-007 transition (type, duration 0…10 s, easing).
- **SHOW-004-R2**: The override MUST be stored in the show file as an optional per-cue field, written only when set (shows without overrides keep their bytes), with no format version change; an invalid stored override MUST be dropped with a counted warning, and an unknown type MUST be kept with a warning, while the rest of the show loads.
- **SHOW-004-R3**: Every step that makes a cue active MUST drive the cue's override when it has one, and otherwise its scene default (SCN-007 transition), resolved by the existing safety rules; an override of an unknown type applies as a cut (the scene default is not used).
- **SHOW-004-R4**: Setting, changing, removing or using an override MUST NOT change the scene default of any cue or any scene file.
- **SHOW-004-R5**: The show editor MUST offer "Transition Into This Cue…" per cue (context menu, swipe action, VoiceOver action) with "Use Scene Default" as the first choice, and MUST show an existing override under the cue's label (and in its VoiceOver value).
- **SHOW-004-R6**: Override edits MUST save at once and never apply a scene or move the position; they MUST be refused while the scene is locked (SCN-015).
- **SHOW-004-R7**: Duplicate Scene MUST copy the source cue's override to the new cue.
- **SHOW-004-R8**: No network access, no new stored settings key, no wall-clock time.

### Key Entities

- **Scene default transition**: SCN-007's per-cue `transition` for the cue's scene (unchanged by this feature).
- **Cue transition override**: a cue's optional transition used for the edge into that cue, stored with the cue in the show.
- **Effective transition**: override ?? scene default ?? instant, then resolved for Reduce Motion and Reduce flashing.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SHOW-004-S1**: In the acceptance test, stepping into the overridden cue drives a cut and stepping into the other cue of the same scene drives the 2 s crossfade (2 of 2 steps correct), and the scene file and both defaults are byte-identical / equal before and after.
- **SHOW-004-S2**: A show with overrides round-trips through the file byte for byte; a show without overrides is byte-identical to the output before this feature.
- **SHOW-004-S3**: Every invalid override case in the lenient-read test (wrong JSON type, bad duration, bad easing, empty type) loads the show with the override dropped and counted.
- **SHOW-004-S4**: In the app (simulator UI test under 30 s), setting and clearing an override changes the cue row's text accordingly.

## Assumptions

- The live renderer drives transitions on screen only for compositor visuals (XFADE); projectM stays a cut. The override changes which transition is driven, not how it is drawn.
- Simulator results prove behavior only; no device task is needed for this feature.
