# Feature Specification: PRE-010 Preset Quick Audition

**Feature Branch**: `feature/pre-010` (spec directory `168-pre-010-quick-audition`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: Roadmap row PRE-010 (P1, size M, extension of the existing preset browser). Observable
behavior, verbatim: "Temporarily preview selection and return to active preset on cancel." Acceptance,
verbatim: "Cancel restores original preset and its navigation scope."

Identifiers carry the roadmap ID: requirements `PRE-010-R1…`, success criteria `PRE-010-S1…`, tasks
`PRE-010-T01…`. Other features are cited by their own IDs: feature 001 FR-045 (a failed load keeps the
running preset), feature 002 FR-116 (choosing from a list sets the scope), FR-118 (failed presets leave
the session's scopes), PRE-001 (thumbnails), PRE-003 (tags and the tagged scope), PRE-006 (recent
history, 3 s dwell), PRE-007 (collections), PRE-012 (imported presets' on-screen guard), ACC-002
(Reduce flashing preset policy), ACC-004 (announcements and row labels), SCN-002 (scene autosave),
SCN-010 (scene undo).

## Baseline: what exists today (audit of 2026-11-14, commit `b4fe9515`)

| Area | Today |
|---|---|
| Browser | `PresetBrowserView` (sheet): library home, folders, Favorites, search, tag chips (PRE-003), collections (PRE-007), My Presets (PRE-012), Recently Played (PRE-006). Tapping a row calls `AppCoordinator.choose` → `PresetCoordinator.choose(_:from:)` and closes the browser. Rows offer a context menu (touch and hold), swipe actions and VoiceOver actions. |
| Selection | `PresetCoordinator.select(_:in:)`: sets the scope (`settings.presetScope`, announced), loads through `PresetLoading`, then sets `current`, clears the failure, writes `lastPresetID`, tells PRE-006's `recent.shown` (3 s dwell), plans and prewarms the next picks (`PresetPrewarmer`), and runs PRE-012's user guard. A failed load keeps the running preset, shows "Preset could not be loaded" and excludes the preset for the session. |
| Engine | `RendererPresetLoader.load` → `renderer.setPreset`: projectM blends from the running preset to the new one. Loading the preset already on screen again restarts it (a visible blend). |
| Undo and autosave | SCN-010 undo and SCN-002 autosave observe `SceneInputs` (visual, spectra, glow, text, media, layers, effects). The projectM preset and its scope are not scene inputs. |
| Thumbnails | PRE-001/PRE-002: rendered off screen by the thumbnail model; independent of the preset on screen. |
| Flash safety | ACC-002: with Reduce flashing on, a flagged preset chosen by name waits for "Load Anyway"; FX-019's envelope limits every frame either way. |
| Gap | No way to look at a preset without making it the selection: every choice writes `lastPresetID`, may change the scope, and (when on) feeds the recent history. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the
conservative, local-first option that delivers the roadmap row.

- Q: How does the user start a preview? → A: A "Preview" action on every playable preset row, in three places so it is discoverable and accessible: the row's touch-and-hold menu (first item), a leading swipe action, and a VoiceOver custom action "Preview". A plain tap keeps its meaning (choose and close).
- Q: What does the browser do during a preview? → A: It stays open where it is (same list, same navigation depth, same scroll position) and shows an audition bar at the bottom: "Previewing <name>" with **Keep** and **Cancel**. Because the browser never moves, restoring the navigation position needs no stored scroll offset.
- Q: What persists while previewing? → A: Nothing. No `lastPresetID` write, no scope change (`settings.presetScope` untouched), no recent-history entry (PRE-006), no undo step and no autosave change (the preset is not a scene input, and the preview touches no scene input), no favorites, tags or collections change. The preview is in memory only.
- Q: What do Cancel, Escape and closing the browser do? → A: The same thing: the original (committed) preset is loaded again and the audition bar goes away. Escape is Cancel's keyboard shortcut while the bar is shown; closing the browser (Done, swipe down) cancels a preview in progress.
- Q: What does Keep do? → A: Commits the previewed preset as a normal selection from the list it was previewed in: the scope becomes that list (FR-116), `lastPresetID` is written, the recent-history dwell starts (PRE-006), the next picks are planned and warmed, and the browser closes, exactly as a tap would, but without loading the preset a second time.
- Q: Several previews in a row? → A: Previewing another preset replaces the one being previewed; the original stays the one Cancel returns to, however many presets were previewed.
- Q: A preview that fails to load? → A: What was on screen stays on screen (FR-045): the original if this was the first preview, else the previous preview. The bar shows "<name> could not be previewed." and the preset is left out of the session's scopes like any failed preset (FR-118, in memory). The original stays the Cancel target.
- Q: Announcements? → A: On the shared announcer's library lane: "Previewing <name>." / "Kept <name>." / "Preview cancelled. <original> is back." / "<name> could not be previewed."

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: What do the controls and the visualizer's preset name show during a preview? → A: The committed preset (the original). The preview is a look, not a selection; the audition bar in the browser names what is playing. This keeps Next, Previous and Random walking from the original and keeps every "current" consumer (row checkmark, imported-preset proving) unchanged.
- Q: Does Cancel keep the browser open? → A: Yes. Cancel only ends the preview; the user may keep browsing or preview another preset. Keep closes the browser like a tap.
- Q: Is the 3 s recent-history dwell counted for a preview the user then keeps? → A: From the moment of Keep (the commit), not from the start of the preview: history records selections, and a preview is not one until kept.
- Q: Is the warm-up (`PresetPrewarmer`) run for previews? → A: No. The warm-up is planned from the committed preset; a preview neither plans nor warms. Keep plans and warms as any selection does.
- Q: Does the failure notice outlive the bar? → A: It stays in the bar area until the next preview, Keep, Cancel or the browser closing; the visualizer's "Preset could not be loaded" banner is not used for previews (the committed preset did not fail).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - I peek at presets and go back (Priority: P1) — MVP

A VJ is playing preset A from the "Tagged: Calm" list. They open the browser, preview B and then C
while the browser stays open, decide neither fits, and tap Cancel: A is back on screen, the scope line
still says "Tagged: Calm", and nothing about the session changed.

**Why this priority**: It is the row's behavior and acceptance.

**Independent Test**: Select A in a tagged scope, preview B then C, cancel; A is current and on screen,
the scope is unchanged, every stored value is byte-identical, there is no recent-history entry and no
undo step.

**Acceptance Scenarios**:

1. **Given** A was chosen from "Tagged: Calm", **When** the user previews B, then C, then cancels, **Then** A is loaded again and current, and the scope is "Tagged: Calm".
2. **Given** the same, **When** it completes, **Then** `lastPresetID` and the stored scope are byte-identical to before the first preview, the recent history has no B or C entry (even with history on and more than 3 s per preview), the undo history has no new step, and the autosaved scene is unchanged.
3. **Given** a preview in progress, **When** the user closes the browser or presses Escape, **Then** the result is the same as Cancel.
4. **Given** a preview in progress, **When** it is shown, **Then** the browser stays on the same list at the same position and shows "Previewing <name>" with Keep and Cancel.

---

### User Story 2 - I keep the one I like (Priority: P1)

**Independent Test**: Preview B from a collection, Keep; B is current, the scope is that collection,
`lastPresetID` is B, and B was loaded once.

**Acceptance Scenarios**:

1. **Given** a preview of B from collection "Friday", **When** the user taps Keep, **Then** B becomes the selection exactly as a tap would make it (scope "Friday", `lastPresetID` B, history dwell starts) and the browser closes, with no second load of B.
2. **Given** a preview of B, **When** the user taps another row instead, **Then** that row is chosen normally and the preview ends.

---

### User Story 3 - A preview that fails changes nothing (Priority: P2)

**Acceptance Scenarios**:

1. **Given** A is current, **When** a preview of a broken preset fails, **Then** A stays on screen and current, no preview is in progress, the bar area says "<name> could not be previewed." and nothing is stored.
2. **Given** a preview of B, **When** a preview of a broken preset fails, **Then** B stays on screen as the preview and Cancel still returns to A.

### Edge Cases

- Locked presets offer no Preview (a tap still opens the purchase sheet, FR-106).
- With Reduce flashing on, flagged presets offer no Preview: a preview must not bypass ACC-002's warning; choosing them by name still warns first.
- A preset that failed this session offers no Preview.
- Previewing the current preset is not offered (it is already on screen).
- An imported preset (PRE-012) previewed is guarded on screen like a chosen one (noted before the engine sees it, quarantined if it fails), so a crash during a preview is still caught on the next launch.
- A committed change from elsewhere during a preview (Next, Random, MIDI, OSC, a cue choosing a preset) ends the preview without a restore: the new selection wins.
- Cancel while a preview is still loading: the preview is abandoned and the original is restored.
- Thumbnails (PRE-001) are unaffected: they are drawn off screen.

## Requirements *(mandatory)*

### Functional Requirements

- **PRE-010-R1**: Every playable preset row that is not the current preset MUST offer "Preview" in its touch-and-hold menu, as a leading swipe action and as a VoiceOver action. Locked, failed-this-session and (with Reduce flashing on) flagged presets MUST NOT offer it.
- **PRE-010-R2**: Previewing MUST load the preset on screen without changing `lastPresetID`, the scope or its stored value, the recent history, favorites, tags, collections, any scene input or the undo history; the committed preset (the "original") MUST stay the one the controls name.
- **PRE-010-R3**: While a preview is in progress the browser MUST stay open on the same list and show an audition bar with the previewed name, Keep and Cancel; the previewed row MUST be marked ("previewing" in its accessibility label).
- **PRE-010-R4**: Cancel, Escape and closing the browser MUST load the original preset again and end the preview; the scope and navigation position MUST be what they were before the first preview.
- **PRE-010-R5**: Keep MUST commit the previewed preset as a normal selection from the list it was previewed in (scope, `lastPresetID`, recent-history dwell, warm-up, imported-preset guard), without loading it again, and close the browser.
- **PRE-010-R6**: Previewing several presets in a row MUST keep the first original as Cancel's target.
- **PRE-010-R7**: A failed preview MUST leave on screen what was there, keep the original as Cancel's target, show "<name> could not be previewed." and exclude the preset for the session (FR-118); nothing is stored.
- **PRE-010-R8**: A committed selection from any path during a preview MUST end the preview without restoring the original.
- **PRE-010-R9**: Starting a preview, Keep, Cancel and a failed preview MUST be announced on the shared announcer's library lane; the bar's controls MUST have accessible labels and follow Dynamic Type.
- **PRE-010-R10**: No new stored keys or files, no networking.

### Key Entities

- **Audition** (in memory only): the original preset, the preset being previewed (if any loaded), the list it was previewed in, and a notice.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PRE-010-S1**: After select A in "Tagged: Calm", preview B, preview C, Cancel: A is current and the last preset loaded, the scope is "Tagged: Calm", every stored value (`lastPresetID`, scope, history) is byte-identical, there is no recent-history entry and no undo step, and the autosaved scene is unchanged (acceptance test).
- **PRE-010-S2**: Keep after a preview gives the same stored state as tapping that preset, with exactly one load of it.
- **PRE-010-S3**: A failed preview leaves the on-screen preset and every stored value unchanged.
- **PRE-010-S4**: A UI test previews a preset, cancels, and sees the original preset's name, in under 30 s.

## Assumptions

- The browser sheet hides the visualizer on iPhone; on iPad the preview is visible beside or behind the sheet. Either way the audition bar names what is playing.
- Simulator results are not device evidence; this row needs no device-only check.
- Auto-revert after a timeout, previewing from the controls (outside the browser) and a split-screen side-by-side comparison are out of scope.

## Analysis (speckit-analyze, 2026-11-14)

No critical findings; every requirement and success criterion maps to at least one task (R1 → T05,
T09; R2 → T03, T06; R3 → T02, T04; R4 → T03, T04, T06, T10; R5 → T07, T08; R6 → T06; R7 → T09;
R8 → T02, T08; R9 → T03, T04, T06; R10 → T11; S1 → T06; S2 → T08; S3 → T09; S4 → T10). Applied
fixes: T06 also asserts the library-lane announcements (R9 had no test); Escape (R4) is a keyboard
shortcut on Cancel and is covered by the same code path as Cancel, which the unit and UI tests drive
(a hardware Escape key is not simulated).
