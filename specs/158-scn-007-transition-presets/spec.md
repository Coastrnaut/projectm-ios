# Feature Specification: SCN-007 Scene Transition Presets

**Feature Branch**: `feature/scn-007` (spec directory `158-scn-007-transition-presets`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (SCN-007-T01-T14 verified on the Mac: host package tests and the
feature's own iOS 27.2 simulator "SCN7"; no device claim). ShowControl 74 tests (1.8 s; 7 new), Compositor
all suites pass (CompositorTests 498, 7 skipped; 4 new model tests, 1 new bus test), LibraryBackup 69 (13.4 s; 1 new),
app CueTransitionAcceptanceTests 3 (0.04 s), CueTransitionUITests 1 (29.6 s, 27.6 s). Linux: not run here;
the Compositor Linux shape builds on the Mac (`-DCOMPOSITOR_NO_METAL …`). Follow-up outside this row: the live
renderer does not run the CMP-014 bus, so a cue's transition is recorded (`CueTransitionRecorder`) but the
scene still changes at once on screen. Closed for compositor visuals by XFADE (`specs/167-cue-transitions-on-screen`, 2026-11-14):
`CueTransitionStage` blends a frozen frame out on Photo, Video and Text; native visuals and projectM stay cuts.

**Input**: Roadmap row SCN-007 (P1, size M, depends on CMP-014, integrated). Observable behavior,
verbatim: "Store transition type, duration and easing with each cue." Acceptance, verbatim:
"Reopening scene restores transition settings exactly."

Identifiers carry the roadmap ID: requirements `SCN-007-R1…`, success criteria `SCN-007-S1…`, tasks
`SCN-007-T01…`. Other features are cited by their own IDs: CMP-014 (transition bus, ADR-0042),
SHOW-001 (cue list, `show.json`), SCN-003 (duplicate scene), SCN-004 (folders), SCN-005 (tags),
MOD-004 (mapping curves), FX-009 (trails reset), FX-019 (composite flash guard), ACC-001 (Reduce
Motion), ACC-005 (accessible sliders), ACC-006 (AX-size audit), ACC-012 (sensory safety profile),
FILE-005 (library backup), FR-070 (accessibility).

## Baseline: what exists today (audit of 2026-11-14, commit `ef00371d`)

| Area | Today |
|---|---|
| Transition model (CMP-014) | `SceneTransitionSpec`: style `cut`, `crossfade`, `dipToBlack`; duration finite 0…10 s; easing `linear` or `easeInOut` (smoothstep). Codable. Reduce Motion resolves any transition to a cut (CMP-014-R10). `SceneTransitionClock` advances on frame presentation times (no wall clock). |
| Transition bus (CMP-014) | `SceneTransitionBus.transition(to:spec:reduceMotion:)` blends two compositors; a transition start and a cut reset trails (FX-009-R5); one composite flash guard (FX-019; ACC-012's envelope override) runs on every shown frame, blended or not. The bus never lengthens a cut. |
| App use of the bus | None: no app code creates a `SceneTransitionBus`. A cue applies its scene by setting the live settings at once (an instant change). `MotionPolicy.sceneTransition` exists for the bus. |
| Cues (SHOW-001) | `show.json` version 1: cue `id`, `scene`, `label`; no transition. SCN-004 and SCN-005 added optional top-level keys that are omitted when empty, so older shows keep their bytes. |
| Easing curves (MOD-004) | `MappingCurve`: linear, easeIn/easeOut/easeInOut (exponent 1 < p ≤ 8), logarithmic/exponential (0 < k ≤ 1000), piecewise (≤ 8 points); validated, monotonic, exact at 0 and 1, with a lossless text form (`easeIn:2.0`). |
| Backup (FILE-005) | Re-encodes `show.json` through `ShowCueList.decode` → `encoded()`; exact restore writes those bytes. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the
conservative, local-first option.

- Q: Where is a transition stored? → A: On the cue, as an optional `transition` object in that cue's entry in `show.json` (the row says "with each cue"). The scene file is unchanged, so two cues showing the same scene can enter it differently. "Reopening scene restores exactly" is read as: reopening the show (relaunch, or a new coordinator loading the same folder) restores every cue's transition exactly, bit-identical durations and the same curve. Rejected: a field in the SCN-001 scene document (a scene is shared by cues and the transition describes entering a cue).
- Q: What does a transition hold? → A: A type (`cut`, `crossfade`, `dipToBlack`, the CMP-014 styles), a duration in seconds (finite, 0…10, CMP-014's bound) and an easing that is a MOD-004 `MappingCurve` (stored as its text form; default linear). Rejected: CMP-014's two-value easing (the row asks for easing presets; MappingCurve already gives validated, monotonic, exact-ended curves with a text form).
- Q: What does a cue without a transition do? → A: Today's behaviour: the scene appears at once (a cut). The key is absent and `show.json` keeps the bytes it had before this row.
- Q: How do the bus and the cue meet? → A: The bus learns an optional `MappingCurve` on its spec (`SceneTransitionSpec.curve`, nil = the existing easing, so CMP-014's encoding and behaviour are unchanged). Each cue apply resolves the cue's transition to a `SceneTransitionSpec` and hands it to a transition driver before the scene is applied. Because the live renderer does not run the bus yet (baseline), the app's driver records the spec (a DEBUG probe); wiring the bus into the visualizer is outside this row and is recorded as a follow-up.
- Q: What about Reduce Motion and Reduce flashing? → A: Reduce Motion first: CMP-014-R10 makes any transition a cut. Otherwise, with Reduce flashing on, a cut or a transition shorter than 0.5 s becomes a 0.5 s linear crossfade (a dip to black of under 0.5 s too), so a bright change is spread over at least half a second; the FX-019 flash guard still measures every shown frame. Reduce Motion beats Reduce flashing because a dissolve is still a decorative transition under CMP-014-R10, and the flash guard covers the cut. The stored values never change; only the applied spec is resolved.
- Q: What happens to an unknown transition type in a file (a newer app)? → A: The cue keeps it verbatim (with its duration and easing) and writes it back unchanged; reading reports a warning naming the type; applying such a cue is a cut; the editor shows "Unknown transition (<type>)". An invalid transition (bad duration, unreadable easing, wrong JSON type) is dropped from that cue with a counted warning; the show still loads.
- Q: Where is it edited? → A: A "Transition" sheet per cue from Settings → Show (leading swipe "Transition", context menu "Transition…", VoiceOver action "Transition"), with a type picker, a duration slider (ACC-005 `.accessibleParameter`, 0…10 s in 0.1 s steps) and an easing picker (Linear, Ease In, Ease Out, Ease In-Out, plus "Custom" shown when the stored curve is another MappingCurve); the type picker's first choice, "Default", removes the transition. The cue row shows "Transition: Crossfade 1.5 s" under its label. Edits save at once and never apply a scene.
- Q: Does Duplicate Scene copy the transition? → A: Yes, the inserted cue gets its source cue's transition (it behaves like its source, as with folder and tags).

### Session 2026-11-14 (speckit-analyze)

- Consistency pass over spec, plan and tasks: every requirement R1-R11 maps to a task (R3 → T06, T10; R9 → T11, T12; R11 → T13). One fix applied: "Use Default" became the type picker's first choice "Default" (one control instead of a separate button; R9 and the sheet agree).
- Implementation note (2026-11-14): `-uitestResetNotice` removes the show folder, so the UI test's relaunch omits it.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: Which exponents do the easing presets use? → A: 2 (quadratic): Ease In `easeIn:2.0`, Ease Out `easeOut:2.0`, Ease In-Out `easeInOut:2.0`. Any other valid MappingCurve (from a file or a later editor) is kept and shown as "Custom (<text form>)".
- Q: Is the duration rounded when stored? → A: The slider steps by 0.1 s and sets the value the step gives; the model stores exactly the Double it is given (validated, not rounded), so a file's value survives bit for bit.
- Q: Does a cut keep a duration and easing? → A: Yes, as stored (the editor disables the duration and easing controls for a cut); a cut ignores them when applied. Keeping them means switching back to a crossfade restores the user's values.
- Q: Do merge restore and FILE-004 import carry transitions of incoming cues? → A: Incoming scenes arrive as new cues without a transition (they carry scenes, not cues); existing cues keep theirs. Exact restore carries every transition.
- Q: Are unknown keys inside a transition object kept? → A: No: only `type`, `duration` and `easing` are read and written; extra keys inside the object are dropped (counted in no warning, as other optional keys in `show.json`).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - I give each cue its own transition and it comes back exactly (Priority: P1) — MVP

A performer sets cue 2 to a 1.5 s crossfade with Ease Out and cue 3 to a 0.8 s dip to black with a
custom curve. They quit and reopen the app: both cues show the same transitions, and stepping to cue 2
drives the transition with exactly a 1.5 s crossfade and that curve.

**Independent Test**: Set distinct transitions on cues through the show coordinator, reload the show
folder with a new coordinator, compare values bit for bit, then step to each cue with a transition
driver spy and compare the specs it received.

**Acceptance Scenarios**:

1. **Given** cues with distinct transitions (type, duration, easing including a custom curve), **When** the show is saved and reloaded from disk by a new coordinator, **Then** every cue's type, duration (bit-identical) and curve are equal.
2. **Given** that reloaded show, **When** a cue is applied, **Then** the transition driver receives exactly that cue's type, duration and curve before the scene is applied.
3. **Given** a cue without a transition, **When** it is applied, **Then** the driver receives a cut (today's behaviour).

---

### User Story 2 - Old shows and newer files stay safe (Priority: P2)

**Independent Test**: Fixtures: a show without transitions re-encodes byte for byte; a cue with an
unknown type keeps it and reports it; invalid transitions are dropped with a warning.

**Acceptance Scenarios**:

1. **Given** a show file written before this row, **When** it is read and written again, **Then** the bytes are identical.
2. **Given** a cue whose transition type is `wipeLeft`, **When** the show is read and written, **Then** the type is kept verbatim and a warning names it; applying the cue is a cut.
3. **Given** a transition with a duration of 12 s, a negative or non-numeric duration, or an unreadable easing, **When** the show is read, **Then** that transition is dropped with a counted warning and the show loads.
4. **Given** a show with transitions, **When** it is backed up and restored exactly, **Then** the transitions and the show bytes are the same.

---

### User Story 3 - Safety settings still win (Priority: P2)

**Independent Test**: Unit tests of the resolution.

**Acceptance Scenarios**:

1. **Given** a 2 s crossfade cue and Reduce Motion on, **When** it is applied, **Then** the driver receives a cut.
2. **Given** a cut cue and Reduce flashing on (Reduce Motion off), **When** it is applied, **Then** the driver receives a 0.5 s linear crossfade.
3. **Given** a 2 s crossfade and Reduce flashing on, **When** it is applied, **Then** it is unchanged.

### Edge Cases

- A cue whose scene is missing or needs repair: the position moves, nothing is applied and no transition is driven (as today).
- A dip to black shorter than 0.5 s with Reduce flashing is lengthened to 0.5 s and keeps its style and curve.
- Moving, renaming or removing other cues never changes a cue's transition.
- A transition edit that cannot be saved stays in effect for the session with "The show could not be saved." (as other show edits).

## Requirements *(mandatory)*

### Functional Requirements

- **SCN-007-R1**: Each cue can carry a transition: a type (`cut`, `crossfade`, `dipToBlack`, or an unknown type kept verbatim), a duration (finite, 0…10 s) and an easing (a valid MOD-004 curve; default linear).
- **SCN-007-R2**: The transition is stored in the cue's `show.json` entry as an optional `transition` object with keys `duration` (number), `easing` (curve text form) and `type` (string); the format version stays 1; a cue without one has no key, and a show without transitions encodes to the bytes it had before this row; decode → encode is byte-identical.
- **SCN-007-R3**: Reopening the show restores each transition exactly: the same type text, a bit-identical duration and an equal curve.
- **SCN-007-R4**: An invalid transition never refuses the show: it is dropped from its cue with a warning that counts them. An unknown type is kept (with its duration and easing) and reported in a warning naming the cue and type. A type is 1…64 characters.
- **SCN-007-R5**: Applying a cue (Next, Previous, Go to, and the paths that use Go to) resolves its transition and hands the spec to the transition driver before the scene is applied: a missing transition or an unknown type is a cut; otherwise the CMP-014 spec has the same style, duration and curve.
- **SCN-007-R6**: Resolution: Reduce Motion makes any transition a cut (CMP-014-R10). Otherwise, with Reduce flashing on, a cut or a transition shorter than 0.5 s becomes 0.5 s long (a cut becomes a linear crossfade; other styles keep style and curve). Stored values are never changed by resolution.
- **SCN-007-R7**: The CMP-014 spec and clock accept an optional curve that shapes the clock's progress; with no curve, encoding and behaviour are exactly CMP-014's.
- **SCN-007-R8**: Transition edits save the show at once and never apply a scene, move the position or change cue order. Duplicate Scene gives the new cue its source cue's transition.
- **SCN-007-R9**: Settings → Show offers a Transition sheet per cue (swipe, context menu, VoiceOver action) with a type picker, an ACC-005 duration slider (0…10 s, 0.1 s steps; disabled for a cut), an easing picker (Linear, Ease In, Ease Out, Ease In-Out, and Custom for any other stored curve; disabled for a cut) and Use Default; the cue row shows a "Transition: …" line and VoiceOver reads ", transition Crossfade 1.5 seconds". Layout works at AX sizes (ACC-006).
- **SCN-007-R10**: FILE-005's full backup and exact restore carry transitions; merge restore and import keep existing cues' transitions.
- **SCN-007-R11**: No networking and no new settings keys; data stays in the app's local show folder.

### Key Entities

- **Cue transition**: type, duration in seconds, easing curve; part of a cue.
- **Transition driver**: what receives the resolved spec when a cue applies (the bus, a recorder, or a test spy).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SCN-007-S1**: After a reload from disk, 100% of the cues' transitions in the acceptance test are equal (types, bit-identical durations, curves), and applying each cue drives exactly that transition.
- **SCN-007-S2**: A show file without transitions decodes and re-encodes byte for byte.
- **SCN-007-S3**: 100% of the invalid transitions in the tests are refused (editing) or dropped with a warning (reading); unknown types are kept.
- **SCN-007-S4**: A backup round trip preserves every transition and the show bytes.
- **SCN-007-S5**: With an injected frame clock, the transition's eased progress equals the cue's curve at every frame.
- **SCN-007-S6**: On the simulator a user sets a cue's transition, relaunches and sees the same values, in a UI test under 30 seconds.

## Assumptions

- The live renderer does not run the CMP-014 bus yet; this row stores the settings and drives a transition driver. Showing the blend on screen needs the bus in the visualizer (a later row).
- Simulator and Mac results are not device evidence; no device-only check is needed for this row.
