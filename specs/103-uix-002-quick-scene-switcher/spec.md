# Feature Specification: UIX-002 Quick Scene Switcher

**Feature Branch**: `feature/uix-002` (spec directory `103-uix-002-quick-scene-switcher`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement UIX-002 (Quick scene switcher) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Search and recall local scenes
from a compact overlay." Acceptance, verbatim: "Scene opens within defined latency and search keeps
focus state." Depends on SCN-001 (integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `UIX-002-R1…`, success criteria `UIX-002-S1…`, tasks `UIX-002-T01…`.

## Baseline: where local scenes live today (audit of 2026-11-14, commit `7a4e26e`)

The row's gap status is "Gap candidate". The audit confirms the gap: there is no way to search
scenes, and the only way to reach a scene is to step cue by cue or to open Settings › Show.

| Area | Today | Relevance |
|---|---|---|
| SCN-001 scene documents | The scene format (`SceneDocument`: name, layers, parameters, bindings, assets) and its validation (`liveState`). | The unit a switcher opens. |
| SCN-002 autosave | One "current scene" file, committed while the user edits; restored at launch, or offered through PERF-010's Reopen. | A single unnamed working scene, not a collection: nothing to search. |
| SHOW-001 show cues | `ShowStore` keeps the cue list and one scene file per scene (`Show/Scenes/<id>.scene.json`). Each cue has a label and points at a scene; several cues may show one scene. Going to a cue reads, validates and applies its scene (`ShowCoordinator.go(to:)` → `AppCoordinator.applyShowScene`). | **The only collection of named local scenes.** |
| SCN-003 duplicate and rename | Duplicate stores a copy under a new scene ID with a new cue; Rename renames the scene (all cues showing it), so a scene name can differ from a cue label. | A search must match both the cue label and the scene name. |
| SCN-010 undo | Applying a cue restarts the edit history (a cue is not an edit). | The switcher must apply through the same path. |
| FILE-001/002 archives | Scene archives can be exported; import has no screen yet (SCN-014). | Not a scene collection; out of scope. |
| SCN-012 repair report | A cue's scene with problems shows the repair report before anything is applied; a scene that cannot be opened shows "Cannot open". | Must still appear when a scene is chosen from the switcher. |
| SCN-013 migration | Older scene files are migrated on read. | Already inside the cue path. |
| Keyboard | Arrows and Page Up/Down step cues; B is blackout; ⌘Z/⇧⌘Z undo and redo. | ⌘K is free. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: What does the switcher list: show scenes, cues, or both? → A: **Cues** of the current show, in show order, each showing its cue label, its number, and its scene name when that differs from the label (UIX-002-R2). Choosing an entry goes to that cue. A cue is how a scene is recalled today (position, notices, the repair report, save of the position), so the switcher reuses that path exactly; a scene shown by two cues appears twice, once per cue, which is what the cue list shows too. Rejected: a separate scene library (none exists; inventing one is SCN-014/UIX-008 territory) and a deduplicated scene list (choosing a scene would need a made-up rule for which cue becomes active).
- Q: Where is the switcher opened from? → A: A "Scenes" button in the show row of the controls (shown only when the show has at least one cue), and ⌘K on a hardware keyboard, with or without the controls shown (UIX-002-R1).
- Q: What does "compact overlay" mean? → A: A card over the visualization (not a full-screen sheet), at most 480 points wide, with a search field, a result count and a scrolling list; the visualization keeps running behind a light dim; a tap outside the card closes it (UIX-002-R1).

### Session 2026-11-14 (speckit-clarify)

Five questions, each answered by Claude with the recommended option (owner rule 4).

- Q: Where does the latency measurement end: at the applied settings, or at the first frame drawn with the new scene? → A: **At the applied state** (UIX-002-R8): the cue's scene has been validated and set on the live settings and the visual refresh has been requested, or the repair report has been requested. That end point is deterministic and observable on the simulator; the first drawn frame depends on the GPU, the visual kind and the display refresh, and simulator frame times are never evidence. The overlay's own closing animation is not part of the measurement. A device first-frame measurement is left to a later device pass. Rejected: the first frame (not reliably observable in UI tests without new render instrumentation).
- Q: Which announcement lane carries the result count? → A: **A new `search` kind** of the shared announcer (UIX-002-R9), so a burst of keystrokes is coalesced to one count per second and can never swallow a cue notice or a blackout announcement. The scene announcement after a choice uses the existing `cue` kind, like a cue step. Rejected: the `cue` lane for both (a pending count could replace a cue failure notice).
- Q: Is the switcher shown on an external display or in recordings? → A: **No.** It is device UI like the controls and sheets (OUT-001): the external display, saved frames and recordings show only the visual (UIX-002-R1).
- Q: Does the switcher close by itself after a while, like the controls? → A: **No.** It stays until the user chooses, presses Escape, taps Close or taps outside (UIX-002-R1); the controls' auto-hide continues underneath and does not affect it. A performer reading a long list must not lose it mid-search.
- Q: How large can the list be, and must it stay fast? → A: Up to the show's limit of 256 cues; filtering all 256 entries must take well under one frame, so the list updates on every keystroke without debouncing (UIX-002-S6). Rows are built lazily.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Find and recall a scene by typing (Priority: P1)

A performer with a show of many cues wants the "Drop" scene now. They press ⌘K (or tap Scenes),
type "dr", see "Drop" highlighted, and press Return (or tap it). The overlay closes and the
visualization shows the Drop scene at once.

**Why this priority**: It is the row's behavior and half its acceptance criterion ("scene opens
within defined latency").

**Independent Test**: With a seeded five-cue show, open the switcher, type a fragment, choose the
match, and read back the applied scene and the measured latency.

**Acceptance Scenarios**:

1. **Given** a show with cues, **When** the user opens the switcher, **Then** the search field has keyboard focus and every cue is listed in show order with the active one marked.
2. **Given** the switcher is open, **When** the user types "DRO" or "dro", **Then** only entries whose label or scene name contains "dro" (ignoring case and accents) are listed.
3. **Given** a filtered list, **When** the user taps an entry or presses Return on the highlighted one, **Then** the switcher closes, the cue becomes active, its scene is applied, and the time from the choice to the applied scene is within the budget.
4. **Given** a hardware keyboard, **When** the user presses Down or Up Arrow in the field, **Then** the highlight moves through the results without leaving the field.

---

### User Story 2 - Search keeps its focus state (Priority: P1)

While the user types, the list narrows on every keystroke; the field never loses focus, the text
is never reset, and the highlighted entry stays the same as long as it still matches.

**Why this priority**: It is the second half of the acceptance criterion.

**Independent Test**: Type character by character, then delete a character; after every change
the field still has focus, holds exactly the typed text, and the highlight is where the rules say.

**Acceptance Scenarios**:

1. **Given** the user has typed "b", **When** they type "r" (list narrows), **Then** the field still has focus and reads "br".
2. **Given** an entry is highlighted, **When** the query changes and the entry still matches, **Then** it stays highlighted; when it no longer matches, the first result is highlighted.
3. **Given** the user closed the switcher without choosing, **When** they reopen it, **Then** the last query and its highlight are restored with the field focused; after a scene was chosen, the switcher reopens empty.
4. **Given** no entry matches, **Then** "No matching scenes" is shown, Return does nothing, and the text stays.

---

### User Story 3 - Problem scenes still show the repair report (Priority: P1)

A scene that needs review (missing media, invalid mappings, newer format) chosen from the switcher
shows SCN-012's repair report before anything is applied, exactly as stepping to that cue does.

**Why this priority**: Safety of the existing repair rule.

**Independent Test**: With the repair seed, choose "Broken" in the switcher: the report appears and
the output stays on the previous scene until the user opens it.

**Acceptance Scenarios**:

1. **Given** the repair seed, **When** the user chooses "Broken", **Then** the switcher closes, the repair report appears, and nothing is applied until "Open with repairs".

---

### User Story 4 - Accessible switcher (Priority: P2)

VoiceOver users hear the result count after typing (not on every keystroke), each entry's label,
number and state, and which entry is highlighted; at the largest text sizes the card still fits and
scrolls; with Reduce Motion the card appears without animation.

**Acceptance Scenarios**:

1. **Given** VoiceOver, **When** the result count changes, **Then** "3 scenes" (or "No matching scenes") is announced through the app's rate-limited announcer.
2. **Given** accessibility text sizes, **Then** entries wrap instead of truncating and every control stays reachable.

### Edge Cases

- The show has no cues: no Scenes button, ⌘K does nothing.
- The active cue is chosen: its scene is applied again (SHOW-001 "Go to" semantics).
- A cue whose scene file cannot be read ("Scene missing") is listed with that state; choosing it follows the cue path (repair report or notice).
- Settings is open: ⌘K does nothing (Settings owns the keyboard, as for the cue keys).
- While the switcher is open, the arrow keys move the highlight instead of stepping cues, and ⌘Z goes to the text field, not scene undo.
- Blackout is on: choosing a scene changes the look behind the black cover, as a cue step does.
- A query of only spaces counts as empty.

## Requirements *(mandatory)*

### Functional Requirements

- **UIX-002-R1**: The switcher is a compact card over the visualization on the device only (never on an external display, in saved frames or recordings), opened by a "Scenes" button in the controls' show row and by ⌘K (when the show has cues and Settings is closed); it closes only with Escape, a Close button, a tap outside the card, or a choice (no auto-hide).
- **UIX-002-R2**: It lists the current show's cues in show order: label, "Cue N", the scene name when it differs from the label, "Current" for the active cue, "Scene missing" for an unreadable scene.
- **UIX-002-R3**: Filtering: an entry matches when its label or scene name contains the trimmed query, ignoring case, accents and width. An empty query lists every cue. Order: entries where the query starts the label, the scene name or a word of either come first; within each group show order is kept.
- **UIX-002-R4**: The search field is focused when the switcher opens and keeps focus while typing and while the list updates; Up and Down Arrow move the highlight; Return chooses the highlighted entry.
- **UIX-002-R5**: Highlight rules: on open, the active cue if it is listed, else the first result; after a query change, the same entry if it still matches, else the first result; none when nothing matches.
- **UIX-002-R6**: Reopening after closing without a choice restores the last query and highlight; after a choice the switcher reopens with an empty query. The query is kept in memory only (never stored; cleared at relaunch).
- **UIX-002-R7**: Choosing an entry closes the switcher and goes to that cue through the same path as a cue step: same validation, SCN-012 repair report, notices, undo restart and saved position; the audio source is never touched.
- **UIX-002-R8**: Latency is defined as the time from the choice (tap or Return) to the moment the cue's scene is applied to the live settings (visual refresh requested), or the repair report is requested, excluding the overlay's closing animation, measured on a monotonic clock inside the app. Budget: ≤ 250 ms on the iOS Simulator. Each choice records one measurement (outcome, cue, milliseconds) readable by tests in debug builds.
- **UIX-002-R9**: After a choice the scene's name is announced ("Scene: Drop", announcer kind `cue`); while typing, the result count is announced through the shared rate-limited announcer under its own kind `search`; entries carry labels, values and the Selected trait for the highlight.
- **UIX-002-R10**: The card works at every Dynamic Type size (entries wrap; the list scrolls; the card never exceeds the screen); its appearance animation goes through the app's Reduce Motion policy.
- **UIX-002-R11**: Closing without a choice shows the controls again so focus returns to the Scenes button; while the switcher is open the cue keys and scene undo keys are inactive.
- **UIX-002-R12**: Nothing is written to disk by searching; no network use.

### Key Entities

- **Switcher entry**: a cue of the show as listed: cue ID, number, label, scene name, active, missing.
- **Switcher state**: open or closed, query, highlighted cue, last abandoned query.
- **Switch measurement**: outcome (applied, repair shown, failed), cue, milliseconds.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **UIX-002-S1**: A seeded scene is found and applied from the switcher with 4 key presses or fewer after opening it (type two characters, Return).
- **UIX-002-S2**: On the iOS Simulator the measured time from choice to applied scene is ≤ 250 ms in every UI test run.
- **UIX-002-S3**: Across every keystroke of a typed query, the field keeps focus and its text equals what was typed (0 resets).
- **UIX-002-S4**: Filtering is correct for case, accents, empty query and ordering in 100 % of the unit cases.
- **UIX-002-S5**: A problem scene chosen from the switcher shows the repair report and applies nothing until the user opens it.
- **UIX-002-S6**: Filtering a 256-cue show takes under 5 ms per keystroke on the Mac host (unit test, monotonic clock, generous ceiling).

## Assumptions

- Device latency is not measured by this feature (owner rule: simulator results are never device evidence); a device pass can be added later.
- "Recall" means opening the stored scene of a cue; live edits since the cue was applied are replaced, as with SHOW-001's Go to.
- iPhone and iPad, portrait and landscape; the hardware keyboard paths are verified on the simulator's keyboard events.
