# Feature Specification: ACC-002 Reduced Flash Preset Policy

**Feature Branch**: `feature/acc-002` (spec directory `030-acc-002-reduced-flash-preset-policy`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement ACC-002 (Reduced flash preset policy) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Warn or filter scenes exceeding
user flash-safety preference." Acceptance, verbatim: "Known high-flash fixture is flagged before
scene load." Depends on FX-019 (integrated: Packages/FlashSafety, ADR-0011)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `ACC-002-R1…`, success criteria `ACC-002-S1…`, tasks `ACC-002-T01…`. Spec 001's
photosensitivity notice and Reduce flashing setting (FR-071, FR-072) and FX-019's strobe safety
envelope (`specs/022-fx-019-strobe-safety-envelope`, ADR-0011) stay in force unchanged; this
feature adds a layer in front of them and replaces neither.

## Baseline: what exists today (audit of 2026-11-13, commit `11329d5`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| Flash safety while rendering | FX-019's envelope dims every projectM and native frame so flashes stay within the limit: 2 flashes per second with Reduce flashing on, 3 with it off. | None for rendering. It acts only after a scene is on screen and only by dimming. |
| Knowing a scene may flash | Nothing. The 12,847-preset library carries name, author, pack, folder and hash per preset; nothing says whether a preset is built to strobe. | No way to know, before a scene loads, that it is likely to flash. |
| Choosing scenes | Next, Previous and Random walk the current scope's playable presets; choosing in the browser loads at once. There is no timed auto-advance. | Reduce flashing does not change which scenes are chosen. |
| Browser | Rows show name, author, favorite and lock state. | No sign that a preset may flash. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- (filled by /speckit-clarify)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Flash-prone scenes are skipped automatically (Priority: P1)

A viewer who turned on Reduce flashing taps Next, Previous or Random. The app never picks a scene
that is known to be built to flash; it moves on to the next scene that is not.

**Why this priority**: It is the "filter" half of the row, and it protects the viewer without any
action on their part.

**Independent Test**: In a scope holding a flagged preset between two calm ones, with Reduce
flashing on, Next from the first calm preset lands on the second; with Reduce flashing off it lands
on the flagged one. Random over many picks never returns the flagged one with the setting on.

**Acceptance Scenarios**:

1. **Given** Reduce flashing is on and the next preset in the scope is flagged, **When** the user
   taps Next (or Previous), **Then** the flagged preset is skipped and the following unflagged one
   loads.
2. **Given** Reduce flashing is on, **When** the user taps Random, **Then** the pick is never a
   flagged preset, and the scene warmed up in advance is never a flagged one.
3. **Given** Reduce flashing is off, **When** the user taps Next, Previous or Random, **Then**
   the choice is exactly what it was before this feature.
4. **Given** Reduce flashing is on and every playable preset in the scope is flagged, **When** the
   user taps Next, Previous or Random, **Then** nothing loads and a message says that every preset
   here may flash.

---

### User Story 2 - A flash-prone scene the user picks is flagged before it loads (Priority: P1)

The viewer, with Reduce flashing on, picks a flagged preset by name in the browser. Before
anything loads, the app warns that this preset may flash and offers Load Anyway or Cancel.

**Why this priority**: It is the "warn" half of the row and the acceptance criterion itself.

**Independent Test**: With the checked-in high-flash fixture in the library and Reduce flashing
on, choosing it shows the warning while the previous scene stays on screen; Cancel keeps that
scene; Load Anyway loads the fixture.

**Acceptance Scenarios**:

1. **Given** Reduce flashing is on, **When** the user chooses a flagged preset, **Then** a warning
   naming the preset appears and the scene on screen does not change.
2. **Given** the warning, **When** the user chooses Cancel, **Then** nothing loads and the previous
   scene keeps playing.
3. **Given** the warning, **When** the user chooses Load Anyway, **Then** the preset loads, and
   the runtime flash limit still applies to it.
4. **Given** Reduce flashing is off, **When** the user chooses a flagged preset, **Then** it loads
   at once with no warning.

---

### User Story 3 - The browser shows which scenes may flash (Priority: P2)

With Reduce flashing on, every flagged preset in every list carries a "May flash" mark that does
not rely on color, and VoiceOver reads it as part of the row.

**Independent Test**: The fixture's row shows the mark and its accessibility label ends with
"May flash"; a calm preset's row has neither.

**Acceptance Scenarios**:

1. **Given** Reduce flashing is on, **When** a list shows a flagged preset, **Then** the row shows
   a warning symbol with the words "May flash", and its accessibility label includes "May flash".
2. **Given** Reduce flashing is off, **When** a list shows a flagged preset, **Then** the row looks
   exactly as before.

---

### User Story 4 - Every preset is screened, including imported ones (Priority: P2)

The bundled library is screened when the app is built; presets the user imports or edits are
screened when they join the library, by the same rules.

**Independent Test**: The same fixture files give the same verdict from the build-time screen and
from the in-app screen; an imported copy of the high-flash fixture is flagged in My Presets.

**Acceptance Scenarios**:

1. **Given** the high-flash fixture, **When** it is screened at build time or in the app, **Then**
   both flag it with the same reasons; the calm fixture is flagged by neither.
2. **Given** an imported preset whose text is built to flash, **When** it becomes playable,
   **Then** it is flagged like a bundled one.

### Edge Cases

- The preset on screen is flagged when the user turns Reduce flashing on: it keeps playing (the
  runtime limit already applies); the policy acts on the next choice.
- The last preset of a previous launch is flagged and Reduce flashing is on: the app starts with
  the scope's first unflagged preset instead.
- A flagged preset is a favorite or in a collection: it stays listed (with the mark); Next and
  Random skip it like any other flagged preset.
- A locked flagged preset: the purchase offer comes first, as today; after the purchase the
  warning applies before it loads.
- A preset that the screen does not flag can still flash (the screen reads the text, it does not
  watch the picture): the runtime limit is the guarantee; the screen only lowers how often the
  limit has to act.
- An older index without screening data: every preset counts as unflagged and the app works as
  before.

## Requirements *(mandatory)*

### Functional Requirements

- **ACC-002-R1**: Every bundled preset MUST be screened for flash risk before the app ships, by
  deterministic rules on its text, and the result MUST travel with the library's index.
- **ACC-002-R2**: The screen MUST flag a preset whose per-frame equations drive a whole-picture
  toggle (invert, solarize, brighten, darken) from audio or from a flicker source, flip such a
  toggle from its own value, or drive a whole-picture level (gamma, decay, echo alpha, border
  alphas) from an undamped flicker source. Flicker sources and damping are defined in the
  research's decision ACC-002-D2.
- **ACC-002-R3**: The screen MUST report which rules flagged a preset, and the same rules MUST give
  the same result at build time and in the app for every checked-in fixture.
- **ACC-002-R4**: Imported and edited user presets MUST be screened by the same rules when they
  join the library.
- **ACC-002-R5**: With Reduce flashing on, Next, Previous and Random MUST skip flagged presets, and
  the presets warmed up in advance MUST exclude them.
- **ACC-002-R6**: With Reduce flashing on, choosing a flagged preset explicitly MUST show a warning
  before anything loads, offering Load Anyway and Cancel; nothing loads until the user decides, and
  Cancel loads nothing.
- **ACC-002-R7**: With Reduce flashing on, every list row of a flagged preset MUST show a mark that
  does not rely on color (a symbol plus the words "May flash") and include "May flash" in its
  accessibility label.
- **ACC-002-R8**: With Reduce flashing off, choosing, stepping, Random, warm-up and rows MUST behave
  exactly as before this feature.
- **ACC-002-R9**: When every playable preset of the scope is flagged and Reduce flashing is on,
  Next, Previous and Random MUST load nothing and show "Every preset here may flash.".
- **ACC-002-R10**: With Reduce flashing on, the preset chosen at launch MUST NOT be a flagged one.
- **ACC-002-R11**: The FX-019 runtime limit MUST keep applying to every preset, flagged or not,
  whichever the user's choice.
- **ACC-002-R12**: Nothing about a warning or a choice made in it MUST be stored; the warning
  appears every time.
- **ACC-002-R13**: The library index MUST stay readable by the current app and index readers: the
  flag is optional and absent means unflagged.
- **ACC-002-R14**: The warning MUST be announced by VoiceOver as an alert, its buttons MUST have
  labels, and its text MUST scale with Dynamic Type.

### Key Entities

- **Flash risk verdict**: for one preset text, the list of rules that flag it (empty = not
  flagged).
- **Flagged preset**: a library entry whose verdict is not empty.
- **Flash warning**: the pending explicit choice of a flagged preset, until Load Anyway or Cancel.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ACC-002-S1**: The checked-in high-flash fixture is flagged, and the calm fixture is not, by both
  the build-time and the in-app screen, in 100% of runs.
- **ACC-002-S2**: In the app, choosing the high-flash fixture with Reduce flashing on shows the
  warning while the previous scene stays on screen, in one UI test of under 30 s.
- **ACC-002-S3**: With Reduce flashing on, 0 of 200 Random picks and 0 Next/Previous steps in the
  test scopes land on a flagged preset; with it off, behavior matches the pre-feature results.
- **ACC-002-S4**: Screening the full bundled library adds under 30 s to a clean build on the build
  Mac, and loading the library in the app is not measurably slower (one optional field).
- **ACC-002-S5**: Each unit test runs in about a second or less; each package suite in under a
  minute (owner rule 7).

## Assumptions

- The screen is a text heuristic, not a measurement: it has false positives and false negatives,
  listed honestly in research.md; FX-019's runtime limit remains the safety guarantee.
- There is no timed auto-advance today; any later one (for example a SHOW row) uses the same
  scope walk and therefore the same skip.
- The mark and warning are shown only while Reduce flashing is on: that setting is the user's
  flash-safety preference.
- No network, no rendering of presets at build time, nothing new stored on disk.
