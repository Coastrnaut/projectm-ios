# Feature Specification: ACC-004 VoiceOver Scene Browser

**Feature Branch**: `feature/acc-004` (spec directory `082-acc-004-voiceover-scene-browser`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement ACC-004 (VoiceOver scene browser) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md (line 452). Observable behavior, verbatim: "Label scene cards,
actions, controls and state changes." Acceptance, verbatim: "Automated accessibility tree exposes all
primary controls." P0, size M, depends on UIX-001 (integrated). Verification: accessibility unit/UI
tests, then a VoiceOver pass on a device last."

Identifiers in this feature carry the roadmap ID: requirements `ACC-004-R1…`, success criteria
`ACC-004-S1…`, tasks `ACC-004-T01…`. Other features are cited by their own IDs: FR-070 (feature 001
accessibility), FR-114/FR-124 (preset rows and scope announcement), PRE-007 (collections), PRE-012 /
PRE-015 (My Presets), SHOW-001 (show cue list), SCN-003 (scene duplicate and rename), OUT-010 /
SHOW-014 (blackout), REC-003 (recording), ACC-001 (Reduce Motion, done), ACC-011 (captioned status
events, later), QA-009 (accessibility snapshot suite at large type, later; builds on this feature).

## What "scene browser" means today

There is no screen called "scene browser" yet (scene import UI is SCN-014, later). The screens that
browse and act on scenes and presets today are, and this feature treats them as the scene browser:

1. **Visualizer controls** — the overlay over the visualization: source status, Stop, Pause/Resume,
   Black out, Save Frame, Record, Previous, Next, Random, Presets, Settings, tempo, the show cue row
   (Previous cue, position, Next cue), Duplicate to My Presets.
2. **Show editor** (Settings → Show) — the cue list: each cue is a scene card.
3. **Preset browser** — library home, packs and folders, search, Favorites.
4. **Collections** (PRE-007) — the list of collections and one collection.
5. **My Presets** (PRE-012) — imported presets, Import, Quarantine.
6. **Settings** — the screen that leads to the show editor and holds visual settings (its top level
   is covered as the gateway; individual setting editors are ACC-005/ACC-006 territory).

## Baseline: what exists today (audit of 2026-11-13, commit `01c0388`)

FR-070 and later features labelled most controls. A read of every view above finds:

| # | Screen | Element | Today | Gap |
|---|---|---|---|---|
| B1 | Controls | Stop, Pause/Resume, Black out, Save Frame, Record, Previous, Next, Random, Presets, Settings | label = title; Black out and Record carry a value | Previous / Next / Random / Presets say nothing about *what* they act on (presets) — no hint |
| B2 | Controls | Show cue row | labels and value ("Cue 2 of 5, Intro") | none |
| B3 | Controls | Duplicate to My Presets, tempo group, status indicator | labelled | none |
| B4 | Controls | current preset name | plain text | acceptable (read in place; identifiers pinned by other suites) |
| B5 | Show editor | cue row (scene card) | one element: label, value "Cue n of m, active, scene missing, scene X", actions Go to Cue, Rename, Duplicate Scene, Rename Scene | the active cue has no Selected trait; Delete and Move have no VoiceOver action (only Edit mode / swipe) |
| B6 | Preset browser | preset row | label "name, by author, locked, current preset, may flash"; actions Add to Collection, Duplicate / Edit, collection Move Up/Down/Remove, My Presets Information/Remove | the current preset has no Selected trait; no hint that activating plays it; favoriting is a separate star button only |
| B7 | Preset browser | star button | label flips Add/Remove from favorites | the change is not announced |
| B8 | Preset browser | folder, Collections and My Presets rows | combined label with count | none |
| B9 | Collections | collection row | combined label, Move Up/Down actions | Rename and Delete only through swipe / context menu |
| B10 | My Presets | rows | labels and actions (Information, Remove) | none |
| B11 | Settings | rows | labelled controls | none found by reading; the automated audit decides |

State changes and what VoiceOver hears today:

| # | Change | Announced today |
|---|---|---|
| C1 | Source started / stopped / paused / held | yes (FR-070, AUD-014) |
| C2 | Scope change (FR-124) | yes |
| C3 | Show cue applied (SHOW-001) | yes, directly, every step |
| C4 | Preset changed by Previous / Next / Random / the browser | **no** |
| C5 | Visualization paused / resumed (Pause button) | **no** |
| C6 | Output blacked out / restored | **no** (value only) |
| C7 | Recording started / stopped / refused | **no** (badge and notice only) |
| C8 | Favorite added / removed | **no** |
| C9 | OSC listener stopped from the badge | yes ("OSC off"); turned on in Settings by a labelled switch |
| C10 | Scene repair, recovery, camera, photo, video, tempo, route | yes (their features) |

There is no shared announcement path: each feature posts directly, with no protection against bursts
(holding Next on a keyboard, a clicker stepping cues quickly).

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the recommended, conservative option.

- Q: How long is the window in which same-kind announcements are coalesced, and when is a repeat dropped? → A: 1.0 s per kind, leading plus trailing: the first change of a kind is spoken at once; changes inside the following 1.0 s replace one pending text, spoken when the window closes (which opens a new window); a text identical to the last spoken text of its kind within 2.0 s is dropped (`ACC-004-R7`). Rejected: speaking every change (queues of preset names while a key is held); trailing-only (a single Next would wait 1 s for feedback); one global window (a blackout could be swallowed by a preset burst).
- Q: Which preset changes count as caused by the user and are announced? → A: Previous, Next and Random (button or keyboard) and a preset chosen in the browser, announced as "Preset: <name>" once the preset has loaded; a show cue's preset change is covered by the cue's own announcement. Not announced: the app replacing a preset that failed, the preset restored at launch, scene reopen or recovery, OSC commands and any future automatic rotation (`ACC-004-R6`). Rejected: announcing every engine change (spam during automatic rotation, the brief's explicit concern); announcing before the load (a failed load would announce a preset that never showed).
- Q: Which touch-only row actions get new VoiceOver actions? → A: Only those with no other touch-free path: Move Up and Move Down on show cues (today only Edit-mode drag) and Add to / Remove from Favorites on preset rows (today only the separate star). Swipe actions and swipe-to-delete are already exposed by iOS as VoiceOver actions (collections' Rename and Delete, cues' Delete), so they are not duplicated (`ACC-004-R3`). Rejected: duplicating every swipe action by hand (double entries in the actions rotor).
- Q: Which system audit types run, and how may issues be filtered? → A: Element description, hit region, contrast, Dynamic Type and trait on every covered screen, at the default text size. An issue may be filtered only by a per-issue rule naming the audit type and the element (identifier or label) with a written reason, kept in one list in the suite and in the contract; filtering a whole audit type or a whole screen is not allowed (`ACC-004-R8`). Rejected: `.all` (includes text-clipped and parent/child checks that QA-009 owns at large sizes); ignoring contrast entirely because of the moving visualization.
- Q: Do announcements post when VoiceOver is off, and how are they tested? → A: They post regardless (the system drops them when no assistive technology listens, as every existing announcement in the app does); test builds record the last spoken text and kind in a hidden probe for the UI suite, and the rate rule is a pure value tested with a fake clock (`ACC-004-R9`). Rejected: checking whether VoiceOver runs first (untestable in UI tests, and Switch Control users would lose them).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Browse and act on scenes and presets with VoiceOver (Priority: P1)

A blind performer opens the show editor with VoiceOver. Each cue is one element that reads its label,
its position, whether it is the active cue and whether its scene is missing; the actions rotor offers
Go to Cue, Rename, Duplicate Scene, Rename Scene, Move Up, Move Down and Delete. In the preset
browser each preset reads its name, author, lock, current state and flash flag, says it plays the
preset when activated, and offers favoriting and the other row actions from the rotor.

**Why this priority**: It is the row's behavior ("label scene cards, actions").

**Independent Test**: With the DEBUG show seed, walk the show editor and the preset browser's
elements; every row is one element with a non-empty label and the expected traits and actions.

**Acceptance Scenarios**:

1. **Given** the show has five cues and cue 1 is active, **When** VoiceOver focuses cue 1, **Then**
   it reads "Opening, Cue 1 of 5, active" and reports it selected.
2. **Given** a cue row is focused, **When** the user opens the actions rotor, **Then** Go to Cue,
   Rename, Duplicate Scene, Rename Scene, Move Up, Move Down and Delete are offered (Move Up absent
   on the first cue's effect: it does nothing there).
3. **Given** a preset row for the playing preset, **When** focused, **Then** it is reported selected,
   its label ends "current preset", and its hint says activating plays the preset.
4. **Given** a preset row, **When** the user picks the favorite action from the rotor, **Then** the
   preset becomes a favorite and VoiceOver says so.

---

### User Story 2 - Hear state changes the user caused, without spam (Priority: P1)

The performer presses Next three times quickly: VoiceOver says the first new preset's name at once
and the final one shortly after, never a queue of every name. Pausing, blacking out, restoring and
starting or stopping a recording each say what happened. A preset that changes without the user
(the app replacing a preset that failed to load, a session restore, an OSC command) is not announced.

**Why this priority**: It is the row's "state changes"; unbounded announcements would make the app
unusable with VoiceOver.

**Independent Test**: Unit tests drive the announcement rule with a fake clock; a UI test reads a
DEBUG probe of the last announcement after Next, Pause and Black out.

**Acceptance Scenarios**:

1. **Given** VoiceOver is on, **When** the user presses Next once, **Then** "Preset: <name>" is
   announced once.
2. **Given** the user presses Next five times within one second, **When** the burst ends, **Then** at
   most two preset announcements were made: the first immediately and the last one after the burst.
3. **Given** the user presses Pause, **Then** "Visualization paused" is announced; Resume announces
   "Visualization resumed".
4. **Given** the user blacks out the output, **Then** "Output blacked out" is announced; restoring
   announces "Output restored".
5. **Given** a preset changes without a user action, **Then** nothing is announced for it.
6. **Given** a clicker steps show cues rapidly, **Then** cue announcements follow the same burst rule.

---

### User Story 3 - An automated check keeps every primary control labelled (Priority: P1)

A developer adds a button without a label. The accessibility UI suite fails: it walks each primary
screen, runs the system accessibility audit and checks a declared list of primary controls for
presence, a non-empty label and the right trait.

**Why this priority**: It is the row's acceptance criterion ("Automated accessibility tree exposes
all primary controls").

**Independent Test**: Run the suite on a simulator; every screen passes the audit (with each filtered
issue documented) and every declared control is found.

**Acceptance Scenarios**:

1. **Given** each primary screen is on screen, **When** the suite runs the system accessibility audit,
   **Then** no unfiltered issue remains, and every filter names the issue and why it is not the app's.
2. **Given** the declared control list, **When** the suite checks the tree, **Then** every control
   exists, is reachable, has a non-empty label and carries the button trait (or its declared trait).

### Edge Cases

- VoiceOver off: announcements cost nothing visible; labels and traits are the same either way.
- Reduce Motion on: labels, traits and announcements are identical (ACC-001-R8).
- A preset fails to load after Next: the failure message is already shown; no "Preset:" announcement
  for a preset that did not load.
- The same announcement twice in a row (a double event): spoken once.
- Different kinds of announcement in one burst (blackout then a cue): each kind is limited on its
  own, so a safety-relevant one is never swallowed by a preset burst.
- The visualizer controls hide after 5 s: with VoiceOver running they stay until hidden (FR-070),
  so the tree is stable for the user.
- The audit runs over a live visualization: contrast findings on text drawn over moving content are
  judged on the app's own surfaces, not on the visualization.

## Requirements *(mandatory)*

### Functional Requirements

- **ACC-004-R1**: Every primary control on the screens listed in "What 'scene browser' means today"
  MUST be in the accessibility tree with a non-empty label that names its meaning, and the trait of
  its role (button, header, selected, adjustable as applicable).
- **ACC-004-R2**: Each scene card (show cue row) and preset row MUST be a single accessibility element
  whose label and value carry its name and state (position, active / current, missing, locked, may
  flash) and whose active / current state also sets the Selected trait.
- **ACC-004-R3**: Every row action available by touch (swipe, context menu, Edit mode) MUST also be
  reachable from the VoiceOver actions rotor: for cues Go to Cue, Rename, Duplicate Scene, Rename
  Scene, Move Up, Move Down, Delete; for presets Add to Collection, Add to / Remove from Favorites and
  the existing per-list actions; for collections Rename, Delete, Move Up, Move Down. Actions iOS
  already exposes from swipe actions are not duplicated; the app adds cue Move Up / Move Down and the
  preset favorite action.
- **ACC-004-R4**: Controls whose label alone does not say what they act on (Previous, Next, Random,
  Presets, Black out) MUST carry a hint saying it; visible text does not change.
- **ACC-004-R5**: State changes the user causes MUST be announced: preset changed by Previous, Next,
  Random or the browser; visualization paused / resumed; output blacked out / restored; recording
  started / stopped / refused; favorite added / removed; show cue applied (existing).
- **ACC-004-R6**: State changes the user did not cause (automatic preset replacement after a failure,
  restore at launch, remote OSC commands) MUST NOT produce a preset announcement.
- **ACC-004-R7**: Announcements MUST go through one shared path that limits each kind: the first of a
  burst is spoken at once, later ones within the following 1.0 s are coalesced into one announcement
  of the latest state when the window closes, and a text identical to the kind's last spoken text
  within 2.0 s is dropped. Kinds are limited independently. New announcements (R5) and the show cue
  announcement use it; other features' existing one-shot announcements keep their direct path
  (ACC-011 may move them).
- **ACC-004-R8**: An automated UI suite MUST, for each primary screen, run the system accessibility
  audit (element description, hit region, contrast, Dynamic Type, traits) and check the declared list
  of primary controls (presence, non-empty label, trait). Each filtered audit issue MUST be listed with
  the element, the issue type and the reason; no audit type is ignored wholesale.
- **ACC-004-R9**: Test builds MUST expose the last announcement so the UI suite can check R5; shipping
  builds do not contain the probe.
- **ACC-004-R10**: No visible text, identifier or existing announcement text changes, except where a
  test or contract is updated with it.

### Key Entities

- **Announcement**: a short text and its kind (preset, cue, playback, output, recording, favorite).
- **Announcement gate**: per kind, the time of the last spoken announcement, the last text, and a
  pending latest text waiting for the window to close.
- **Primary control list**: per screen, the controls the suite requires, each with its identifier
  and expected trait.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ACC-004-S1**: 100% of the declared primary controls on the covered screens are found with a
  non-empty label and the declared trait.
- **ACC-004-S2**: The system accessibility audit reports zero unfiltered issues on every covered
  screen; every filter is documented with a reason.
- **ACC-004-S3**: For a burst of N same-kind user changes inside one window, at most 2 announcements
  are made, and the last one names the final state (unit tests over bursts of 1, 2 and 5).
- **ACC-004-S4**: Each user-caused change in R5 produces exactly one announcement when isolated;
  automatic preset changes produce zero.
- **ACC-004-S5**: Each accessibility UI test finishes in under 30 s on the project Mac.
- **ACC-004-S6** `{device}`: On D1 with VoiceOver, the owner can reach and operate every primary control
  of the covered screens and hears the R5 announcements without repeats.

## Assumptions

- "Scene browser" = the screens listed above (recorded interpretation); SCN-014's import screen will
  adopt the same rules when it exists.
- The system audit on the simulator is the automated stand-in for a VoiceOver pass; the device pass
  (S6) stays the owner's.
- Large text layouts are QA-009's; this feature runs the Dynamic Type audit at the default size only.
- Simulator results are never device evidence (Constitution).
