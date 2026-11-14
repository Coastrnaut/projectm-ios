# Feature Specification: UIX-005 Performance Control Layout

**Feature Branch**: `feature/uix-005` (spec directory `193-uix-005-performance-controls`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement UIX-005 (performance control layout) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Expose large touch targets for
cue, blackout and tempo." Acceptance, verbatim: "Critical controls remain accessible in portrait and
landscape." P1, effort M, depends on SHOW-014 (integrated)."

Identifiers carry the roadmap ID: requirements `UIX-005-R1…`, success criteria `UIX-005-S1…`, tasks
`UIX-005-T01…`, research decisions `UIX-005-D1…`. Other features are cited by their own IDs: SHOW-001
(cue list), SHOW-011 (tap tempo), SHOW-014 (emergency blackout), OUT-010 (output blackout), ACC-004
(VoiceOver audit), ACC-006 (Dynamic Type), ACC-008 (overlay surface), UIX-004 (parameter shelf),
FR-042 (tap toggles the controls), FR-065 (what the app stores), FR-070 (accessibility).

## Baseline: what exists today (audit of 2026-11-14, commit `0cad6578`)

| Area | Today |
|---|---|
| Cue | SHOW-001 `ShowCueRow` inside the auto-hiding controls: Previous cue, "Cue 2 of 5 · Intro", Next cue, Scenes; `.title2` icons (about 28 pt targets). Keys: Right Arrow/Page Down, Left Arrow/Page Up (`ShowKeyCommands`), ⌘K. A step from the row shows the controls. |
| Blackout | OUT-010 "Black out output"/"Restore output" in the controls' button grid (36 pt high in compact width); SHOW-014's emergency button (44 × 44 pt, bottom trailing, shown while live or fading in, with or without the controls; B key) and the persistent badge with Restore (B key while blacked out). |
| Tempo | SHOW-011 `TempoControls`: readout ("120 BPM"/"Manual"), Tap (`.bordered`, 36 pt icon in compact width), Reset tempo; inside the auto-hiding controls only. |
| Shelf | UIX-004 parameter shelf inside the controls (no change needed). |
| Accessibility | ACC-004 audit suite (`AccessibilityScreensUITests`), ACC-006 Dynamic Type inspector (AX3/AX5), ACC-008 overlay surfaces, Large Content Viewer not used yet. QA-009 (accessibility suite) is being built in parallel. |
| "Performance mode" | None. The only "performance" UI is the FR-048 performance *overlay* (a metrics readout, Settings toggle). |

Gap confirmed: no large-target layout; cue and tempo exist only in auto-hiding controls at 28-36 pt.

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the
conservative, local-first option.

- Q: Is the performance layout a mode the user turns on, or automatic when a show is loaded? → A: A mode the user turns on and off with a "Performance layout" button in the visualizer controls (and its VoiceOver action). Not automatic: a layout that appears when a show loads would move controls under the performer's fingers unexpectedly, and the pad is also useful without a show (blackout, tempo). Rejected: automatic on show load.
- Q: Is the choice remembered? → A: No. It lasts for the session (until the app quits) and starts off; no new stored key (FR-065). Rejected: a stored preference (a new key in three places for one tap per gig).
- Q: Does the pad hide with the controls? → A: No. While the layout is on, the pad stays on the visualizer with or without the controls, so the critical controls are always one tap away. The ordinary controls keep their auto-hide unchanged.
- Q: What does the pad hold? → A: Previous cue, Next cue, Tap tempo and Blackout as targets of at least 60 × 60 pt, plus two readouts: the cue position ("Cue 2 of 5 · Intro", "Standby, 5 cues" or "No cues") and the tempo ("120 BPM" over its state word).
- Q: How big are the targets? → A: 60 × 60 pt on iPhone and in compact size classes, 72 × 72 pt when both size classes are regular (iPad full screen or a large split). Larger than Apple's 44 pt minimum on purpose: a performer hits them without looking, in the dark, while moving.
- Q: Where does the pad sit? → A: Portrait (taller than wide): a bottom bar in one row (Previous, Next, Tap, Blackout, Blackout trailing as SHOW-014 placed it), readouts above it; in a width too narrow for one row it wraps to two rows of two. Landscape (wider than tall): two side columns, cue (readout, Previous, Next) on the leading side and tempo and blackout (readout, Tap, Blackout) on the trailing side, vertically centred, so the visual centre stays clear. Always inside the safe area; the status stack and the controls are inset so they never sit under the pad.
- Q: What does the pad's Blackout do? → A: It toggles: "Black out output" while the output is live or fading in (OUT-010's blackout, the same call as SHOW-014's emergency button), "Restore output" while blacked out, and disabled "Restoring output" while a restore waits. Unlike SHOW-014's small corner button (which only blacks out to avoid an accidental reveal), the pad is a deliberate surface the performer chose, and restoring from the same large target is what a performer expects of a blackout key. The badge's Restore stays as well.
- Q: What happens to SHOW-014's 44 pt emergency button while the pad is shown? → A: It is not shown; the pad's Blackout replaces it (same action, larger). The B key moves with it: on the pad's Blackout while live or fading in, on the badge's Restore while blacked out, exactly one owner at a time.
- Q: Do pad taps show the controls? → A: No. A cue step, a tap or a blackout from the pad leaves the controls as they are, so they never pop up over the visual mid-show (the row in the controls still shows them, as before).
- Q: How does the pad behave at accessibility text sizes (up to AX5)? → A: Targets keep their size and stay reachable; the readouts' text scales and may wrap to two lines, then truncate; the small captions under the icons are dropped at accessibility sizes and every target offers the Large Content Viewer (long press shows the label large).
- Q: Keyboard shortcuts? → A: All existing shortcuts keep working unchanged (arrows and Page keys for cues, ⌘K, B). No new shortcut (⌘P means Print by convention).
- Q: External display? → A: The pad is drawn on the device only; the external display shows the visual slot alone as before (OUT-001-R1).

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: What decides "portrait" and "landscape" for the pad: the device orientation or the space? → A: The space the visualizer has (wider than tall → side columns), so iPad split views and Stage Manager windows get the right arrangement too; the device orientation is not read.
- Q: Which size class gets the 72 pt targets? → A: Only when both horizontal and vertical size classes are regular (iPad full screen or a large split). An iPhone in landscape (compact height) and iPad Slide Over (compact width) get 60 pt.
- Q: How much space is reserved for the side columns, and do the controls narrow? → A: Each column is the target plus 8 pt on each side; the status stack (badges, notices, the controls) is inset by that width on both sides, so nothing sits under a column. The visual itself is not resized (it stays full screen behind).
- Q: How is the bottom bar's space reserved in portrait? → A: The bar's measured height plus 8 pt is inset from the bottom of the status stack, so the controls and the source indicator sit above it.
- Q: Does the pad take part in VoiceOver order? → A: Yes, as one container "Performance controls" after the status stack and before the debug probes; its targets read in visual order (Previous, Next, Tap, Blackout in the bar; leading column then trailing column).
- Q: Does the "Performance layout" button keep the controls up? → A: Yes, like every control it restarts the 5 s auto-hide.
- Q: Is the pad shown while the scene switcher (UIX-002) is open? → A: Yes, behind it; the switcher is above every layer, as before.
- Q: Test hook? → A: A DEBUG-only launch argument `-uitestPerformanceLayout` starts with the layout on, so the landscape, AX5 and audit tests skip the toggle; the portrait test turns it on through the controls. Release ignores it.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Step cues, black out and tap tempo with large targets (Priority: P1)

A performer running a show turns on the performance layout. Large Previous, Next, Tap and Blackout
targets stay on screen while the controls hide; one tap on Next goes to the next cue, one tap on
Blackout makes the output black and another restores it, taps on Tap set the tempo.

**Why this priority**: It is the roadmap row's behavior.

**Independent Test**: With the show seed, turn the layout on; each target exists, is hittable, is at
least 60 × 60 pt, lies in the safe area; Next advances the applied cue; Blackout toggles the output
probe; Tap reads "Tap 1 of 4".

**Acceptance Scenarios**:

1. **Given** the visualizer with a show on cue 1, **When** the user taps "Performance layout" in the controls, **Then** the pad appears with Previous cue, Next cue, Tap tempo and Blackout, each at least 60 × 60 pt, and the readouts show the cue and tempo.
2. **Given** the pad, **When** the controls auto-hide, **Then** the pad stays.
3. **Given** the pad, **When** the user taps Next cue, **Then** cue 2 is applied and the controls stay hidden.
4. **Given** the pad, **When** the user taps Blackout, **Then** the output is black; **When** they tap it again, **Then** the output restores.
5. **Given** the pad, **When** the user taps Tap tempo once, **Then** its value reads "Tap 1 of 4".
6. **Given** the pad is on, **When** the user taps "Standard layout" in the controls, **Then** the pad goes away and SHOW-014's emergency button returns.

---

### User Story 2 - Critical controls stay reachable in every orientation and size (Priority: P1)

The performer rotates the device or uses the largest accessibility text size; the pad rearranges
(bottom bar in portrait, side columns in landscape) and every target stays on screen, inside the
safe area, at full size.

**Why this priority**: It is the row's acceptance ("portrait and landscape").

**Independent Test**: The same checks in portrait, in landscape, and at AX5.

**Acceptance Scenarios**:

1. **Given** portrait, **Then** the targets sit in a bottom bar inside the safe area.
2. **Given** landscape, **Then** the targets sit in two side columns inside the safe area, clear of the centre.
3. **Given** AX5, **Then** every target is still at least 60 × 60 pt, hittable and inside the safe area.

---

### User Story 3 - VoiceOver, keyboard and audits (Priority: P2)

A VoiceOver user hears "Next cue", "Tap tempo, Tap 1 of 4", "Black out output, Live"; a keyboard user
keeps arrows, Page keys, ⌘K and B; the system accessibility audit passes on the performance layout.

**Independent Test**: `performAccessibilityAudit` with the pad shown; labels and values asserted.

**Acceptance Scenarios**:

1. **Given** the pad, **When** the system audit runs (element description, hit region, contrast, Dynamic Type, traits), **Then** it reports no issue on the pad.
2. **Given** the pad with the output live, **When** the user presses B, **Then** the output blacks out.

### Edge Cases

- No show or no cues: Previous and Next are shown disabled; the readout says "No cues".
- First or last cue: the button that would do nothing is disabled (as in SHOW-001's row).
- Blackout restore waiting: the pad's Blackout is disabled and reads "Restoring output".
- A narrow window (iPad Slide Over, split view): bottom bar wraps to two rows of two.
- The controls shown in portrait: they sit above the bar; at accessibility sizes they scroll (ACC-006-R2) and the bar keeps its size.
- Sheets (Settings, preset browser) cover the pad as they cover the controls; the layout is still on after they close.
- Reduce Motion: the pad appears and disappears with the controls' policy (no extra animation).

## Requirements *(mandatory)*

### Functional Requirements

- **UIX-005-R1**: The visualizer controls offer a "Performance layout" button (VoiceOver label the same; "Standard layout" while on) that turns the performance layout on and off for the session; it starts off at every launch and is not stored.
- **UIX-005-R2**: While on, the visualizer shows the performance pad with or without the controls; the controls' auto-hide is unchanged.
- **UIX-005-R3**: The pad holds Previous cue, Next cue, Tap tempo and Blackout targets, each at least 60 × 60 pt (72 × 72 pt when both size classes are regular), and a cue readout and a tempo readout.
- **UIX-005-R4**: When the layout area is taller than wide the pad is a bottom bar (one row; two rows of two when one row does not fit); when it is wider than tall the pad is two side columns (cue leading; tempo and blackout trailing), vertically centred. The pad lies inside the safe area, and the status stack and the controls are inset so they do not sit under it.
- **UIX-005-R5**: Previous and Next step the show exactly as the cue row does (SHOW-001), disabled when they would do nothing, without showing the controls.
- **UIX-005-R6**: Tap tempo records a tap exactly as SHOW-011's Tap does, without showing the controls; its accessibility value is the tap progress or the tempo.
- **UIX-005-R7**: Blackout reads "Black out output" while the output is live or fading in and blacks it out (OUT-010, the same call as SHOW-014); "Restore output" while blacked out and restores; disabled "Restoring output" while a restore waits. Its accessibility value is the output state.
- **UIX-005-R8**: While the pad is shown, SHOW-014's emergency button is not shown, and the B key belongs to the pad's Blackout while live or fading in (the badge's Restore keeps it while blacked out). All other keyboard shortcuts are unchanged.
- **UIX-005-R9**: At accessibility text sizes (up to AX5) the targets keep their size and stay inside the safe area; readouts may wrap to two lines then truncate; captions under icons are dropped; every target offers the Large Content Viewer.
- **UIX-005-R10**: Every target has a VoiceOver label equal to its meaning and a value where it has a state; the pad is one container ("Performance controls").
- **UIX-005-R11**: The pad is drawn on the device only; the external display, the blackout cover and the controls' auto-hide behave as before.

### Key Entities

- **Performance layout** (session state): on or off.
- **Pad geometry**: arrangement (bottom bar, two-row bar, side columns), target size, spacing and the insets reserved for the rest of the visualizer, derived from the area's size and the size classes.

## Success Criteria *(mandatory)*

- **UIX-005-S1**: In portrait and in landscape (UI tests), each of the four targets exists, is hittable, measures at least 60 × 60 pt and lies inside the safe area; Next applies the next cue, Blackout blacks out and restores, Tap records one tap.
- **UIX-005-S2**: At AX5 (UI test, one orientation) the same geometry checks pass.
- **UIX-005-S3**: The system accessibility audit reports no unfiltered issue on the performance layout.
- **UIX-005-S4**: Unit tests cover the geometry per size class: iPhone portrait and landscape, iPad regular, and a narrow width.
- **UIX-005-S5**: Existing suites for the cue row, tap tempo, emergency blackout and output blackout still pass.

## Assumptions

- The show seed (`-uitestShowSeed`, five cues) and the tap-interval hook (`-uitestTapInterval`) are reused for tests.
- Simulator results are never device evidence; a device pass with a performer is `{device}`.
