# Feature Specification: SHOW-006 Cue Rehearsal Mode

**Feature Branch**: `feature/show-006` (spec directory `237-show-006-cue-rehearsal`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: Roadmap row SHOW-006 (P1, size L, depends on SHOW-001, integrated). Observable behavior, verbatim: "Preview
upcoming cue without sending it to live output." Acceptance, verbatim: "Preview changes do not alter currently
presented frame."

Identifiers carry the roadmap ID: requirements `SHOW-006-R1…`, success criteria `SHOW-006-S1…`, tasks
`SHOW-006-T01…`, research decisions `SHOW-006-D1…`. Other features are cited by their own IDs: SHOW-001 (show, cues,
one step path), SHOW-002 to SHOW-005 (dwell, quantized steps, transition override, hold and skip), SCN-001 (scene
documents), SCN-006 (stored scene previews), SCN-009 (A/B compare), SCN-010 (scene history), SCN-002 (autosave),
SCN-015 (scene lock), REC-001/REC-003 (Save Frame, recording), REC-002 (offscreen still renderer), OUT-001/OUT-010/
OUT-012 (external output, blackout, display rehearsal), UIX-013 (device-only HUD), ACC-004 (announcer lanes).

## Baseline (audit of 2026-11-14, commit `c035898f`)

| Area | What exists | Gap for this row |
|---|---|---|
| Show steps (SHOW-001…005) | `ShowCoordinator.perform` is the one step path: it reads the cue's stored scene, validates it and hands it to `applyScene` (the live settings). Next passes over skipped cues (SHOW-005). | Nothing reads a cue's scene without applying it. |
| "Rehearsal" today (OUT-012) | Settings › External Display › "Rehearse output…": a stand-in test card that previews crop and mapping; it never draws the visual. | It is about display geometry, not cues; reused only as a pattern (session only, no stored keys). |
| Offscreen render (REC-002) | `SnapshotStillRenderer` renders a native visual's style with given values (bars, orientation, spacing, glow) offscreen, deterministically, with synthetic audio; never touches the screen, the live host or a setting. | Used only for image batches. |
| Scene pictures (SCN-006) | Each stored scene may have a 192 × 108 picture taken from the live output when it was saved or applied. | Not shown next to the running show. |
| Device-only overlays (UIX-013) | The HUD sits in the device's SwiftUI status stack; tests prove the external display, recording and Save Frame are byte-identical with it on and off. | The proof pattern is reused for the rehearsal panel. |
| SCN-009 compare | Applies A/B states to the live output without writing files. | It changes the live output by design, so it is not a preview path. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the conservative,
local-first option.

- Q: Where does the preview appear? → A: In a small panel (picture-in-picture) in the device's own overlay layer, next to the running visual: never in the live output (main visual, external display, recording, Save Frame). The live visual keeps running unchanged.
- Q: Which cue does it preview? → A: The cue Next would reach (SHOW-005: skipped cues passed over); at Standby the first such cue. The performer can step the rehearsal target forward and back through every cue (skipped ones included, as Go to Cue reaches them) without moving the show. When the show steps, a target that was "the next cue" follows the show; a target the performer picked stays picked.
- Q: How is the picture made? → A: For cues whose scene is a native visual the offscreen renderer can draw (Circular and Linear spectrum), a still rendered offscreen with the cue's values and fixed synthetic audio, so it is deterministic and never reads or writes the live output. For every other cue (projectM, Photo, Video, Text), the scene's stored SCN-006 picture, labelled "Stored picture"; without one, "No picture yet". A second projectM engine is not started: a background engine competes with the live show for the GPU (PERF lesson: warm-up renders cut the frame rate from 43 to 29 fps) and PRE-009 owns that path.
- Q: What can be edited in rehearsal? → A: The cue scene's values the app holds (SHOW-001's seven: bar count, linear orientation and spacing, glow on, intensity, radius, threshold) in a sandbox draft. Edits re-render the preview only; they never touch the live settings, the live scene, the autosave or scene history.
- Q: How does an edit leave the sandbox? → A: Only by "Save to Cue": it writes the draft values into the cue's stored scene file (an edit: refused while the scene is locked) and nothing else. It never applies the scene to the live output, even when the rehearsed cue is the active cue; the change shows the next time the cue runs. "Revert" drops the draft. Closing rehearsal with unsaved edits drops them (rehearsal is a sandbox).
- Q: Is anything stored? → A: No new settings key: rehearsal is session only (off at launch), like OUT-012's rehearsal and SHOW-005's Hold.
- Q: What are the bounds? → A: The preview renders at most 320 × 180 pixels, only when its input changes, at most one render at a time and at most 10 renders per second; nothing renders while rehearsal is off or the app is in the background.

### Session 2026-11-14 (speckit-clarify)

Five questions, each answered with the recommended option (owner rules 4 and 9).

- Q: Does the panel hide with the controls? → A: No. While rehearsal is on the panel stays (like UIX-013's HUD and SCN-009's compare bar), at the top of the device's status stack, at most 240 pt wide with a 16:9 picture; its own close button ends rehearsal. The Rehearse toggle itself is in the cue row (hidden with the controls). Rejected: hiding it with the controls (the performer would lose the preview exactly while watching the show).
- Q: After Save to Cue on the active cue, is it re-applied? → A: No. Nothing reaches the live output until the cue runs again (the acceptance: preview changes do not alter the presented frame). The panel says "Saved. Shows when the cue runs."
- Q: What happens to the scene's stored SCN-006 picture after Save to Cue? → A: The file change is reported like Rename Scene does (`sceneFilesChanged`), so the old picture is dropped and a new one is taken when the cue next applies.
- Q: Can a projectM, Photo, Video or Text cue's values be edited in rehearsal? → A: Yes (the glow and spectrum values are part of every scene), but the picture stays the stored one with the note "Edits show when the cue runs"; Save to Cue works the same.
- Q: Is the rehearsal panel in the iPad split editor, on the external display or in the performance pad? → A: Only in the device's visualizer status stack (in the split editor's output pane on iPad, as the HUD). Never on the external display; the performance pad does not get a rehearsal control in this feature.

### Session 2026-11-14 (speckit-analyze)

- Consistency pass: R1 → T09, T15; R2 → T03, T04, T09, T10; R3 → T05, T07, T09, T10; R4 → T14; R5 → T12, T14; R6 → T11, T13; R7 → T06, T07, T10; R8 → T07, T09, T10; R9 → T16; R10 → T09, T15. S1-S2 → T14; S3 → T04, T10, T13; S4 → T15. No constitution conflict. Fixes applied: R10 (panel stays with the controls hidden) and R8's announcements had no test (added to T15 and T10); R7's "never in the background" is met by rendering only on load and edit (nothing loads or edits in the background; SHOW-002 holds steps there), tested as "no render while off".

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See the next cue before it goes live (Priority: P1) — MVP

A VJ runs a show on a projector. Before pressing Next they turn on Rehearse in the cue row: a small panel shows
"Next: Drop" with a picture of that cue's look. The projector, the recording and the phone's main visual do not
change.

**Why this priority**: It is the row's observable behavior.

**Independent Test**: Show with three cues, active cue 1; turn rehearsal on: the panel names cue 2 and shows its
picture; the live settings, the shown visual and the external output are unchanged.

**Acceptance Scenarios**:

1. **Given** cue 1 is active and cue 2 is a Linear spectrum scene, **When** rehearsal turns on, **Then** the panel shows "Cue 2 · Drop" with an offscreen picture of the Linear spectrum, and the live visual stays cue 1's.
2. **Given** cue 2 is skipped, **When** rehearsal turns on, **Then** the panel shows cue 3 (the cue Next would reach).
3. **Given** rehearsal is on, **When** the show steps to cue 2, **Then** the panel follows to cue 3.
4. **Given** a projectM cue with a stored picture, **When** it is rehearsed, **Then** the panel shows the stored picture labelled "Stored picture"; without one, "No picture yet".
5. **Given** rehearsal is on, **When** the performer taps the panel's forward/back arrows, **Then** the target changes and the show's position does not.

### User Story 2 - Tweak the cue in a sandbox (Priority: P1)

The VJ thinks the next cue's glow is too strong. In the panel they open Edit, drag Glow intensity down and watch
the preview change. The live output does not change. They tap Save to Cue; when the show reaches that cue it uses
the new glow.

**Acceptance Scenarios**:

1. **Given** rehearsal on with a draft edit, **When** the value changes, **Then** the preview re-renders and the live output's frames, the live settings, the autosave and scene history are unchanged.
2. **Given** a draft, **When** Save to Cue is tapped, **Then** the cue's stored scene carries the new values, the live output is unchanged, and stepping to the cue applies them.
3. **Given** a draft, **When** Revert is tapped or rehearsal is closed, **Then** the draft is dropped and nothing is written.
4. **Given** the scene is locked, **When** Save to Cue is tapped, **Then** it is refused with the lock message and nothing is written.

### Edge Cases

- Empty show: Rehearse is not offered (the cue row is not shown).
- No next cue (at the last cue, or every later cue skipped): the panel says "End of show" with no picture; the arrows still pick any cue.
- The target cue's scene is missing or unreadable: "The scene could not be read." and no edit controls.
- The target cue is removed or the show replaced while rehearsing: the target falls back to the next cue.
- Blackout (OUT-010): the live output stays black; the device panel still previews.
- A draft exists and the show steps: a picked target keeps its draft; a "next cue" target that moves to a new cue drops its draft (it belongs to the cue it was made for).
- A projectM, Photo, Video or Text cue: values can be edited and saved; the picture stays the stored one with "Edits show when the cue runs".
- Reduce flashing and the safety clamp apply to the preview exactly as to the screen.
- The app goes to the background: rendering stops and resumes on return.

## Requirements *(mandatory)*

### Functional Requirements

- **SHOW-006-R1**: The app MUST offer a session-only Rehearse toggle in the visualizer's cue row (with VoiceOver) that shows a rehearsal panel in the device's overlay layer only.
- **SHOW-006-R2**: The rehearsal target MUST default to the cue Next would reach (skipped cues passed over) and follow the show; the performer MUST be able to pick any cue with forward/back controls without moving the show.
- **SHOW-006-R3**: The panel MUST show the target's position and label and a picture: an offscreen render for Circular and Linear spectrum cues, otherwise the scene's stored picture or "No picture yet"; "End of show" when there is no target; an unreadable scene's message when it cannot be read.
- **SHOW-006-R4**: The preview MUST NOT write to or draw into the live output: the main visual, external display, recording and Save Frame frames MUST be identical with rehearsal on or off and while drafts change.
- **SHOW-006-R5**: Draft edits (the seven app-held values) MUST stay in a sandbox: they MUST NOT change live settings, the active scene, the autosave or scene history.
- **SHOW-006-R6**: Save to Cue MUST write the draft into the target cue's stored scene only (refused while locked; the scene preview cache is told the file changed) and MUST NOT apply anything to the live output, even for the active cue; Revert and closing MUST drop the draft.
- **SHOW-006-R10**: While rehearsal is on, the panel MUST stay visible with or without the controls and MUST offer its own close control.
- **SHOW-006-R7**: The preview MUST be bounded: at most 320 × 180 pixels, rendered only on change, one render at a time, at most 10 renders per second, never while off or in the background; with Reduce flashing and the safety clamp as on screen.
- **SHOW-006-R8**: Turning rehearsal on and off, and Save to Cue results, MUST be announced on the cue lane; the panel's picture MUST have a VoiceOver label naming the cue.
- **SHOW-006-R9**: No network access, no new stored settings key, no wall-clock assertions in tests.

### Key Entities

- **Rehearsal target**: the cue being previewed (follow-next or picked).
- **Rehearsal draft**: the sandbox copy of the target scene's seven app-held values.
- **Rehearsal picture**: rendered still, stored picture, or a message.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SHOW-006-S1**: With a deterministic visual, the external display picture, the main visual's captured frame and every recorded frame are byte-identical with rehearsal off, on, and while at least three draft edits are made (0 differing frames).
- **SHOW-006-S2**: After rehearsal with draft edits, the live settings, the active scene ID, the autosave's edit revision and scene history are unchanged.
- **SHOW-006-S3**: The target is correct in every tested case (next, skipped, end, picked, follow after a step), and Save to Cue changes only the cue's scene file.
- **SHOW-006-S4**: A UI test (under 30 s) turns rehearsal on, sees the panel name the next cue, and the cue row's status is unchanged.

## Assumptions

- Simulator results prove behavior only; a `{device}` task checks the panel and the projector output on D1.
- projectM, Photo, Video and Text cues are not rendered live in rehearsal (stored picture only) in this feature.
- MIDI, OSC and keyboard shortcuts for rehearsal are out of scope.
