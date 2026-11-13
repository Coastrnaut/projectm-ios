# Contract: ACC-004 accessibility tree and announcements

## C1 — Announcement texts (kind → text)

| Kind | Trigger | Text |
|---|---|---|
| preset | Previous / Next / Random / browser choice changed the shown preset | `Preset: <name>` |
| cue | a show step (existing SHOW-001 message) | unchanged SHOW-001 text |
| playback | Pause / Resume control | `Visualization paused` / `Visualization resumed` |
| output | blackout requested / released (any user path: control, emergency button, B key, badge) | `Output blacked out` / `Output restored` |
| recording | recording state becomes recording / leaves it; a refusal notice | `Recording started` / `Recording stopped` / the notice text |
| favorite | star or rotor action | `Added to favorites: <name>` / `Removed from favorites: <name>` |

Rate rule: data-model.md (1.0 s window per kind, 2.0 s identical repeat).
Not announced: automatic preset changes (failure replacement, launch restore, reopen/recovery, OSC).

## C2 — Declared primary controls (UI suite `AccessibilityScreensUITests`)

| Screen | Identifier | Type | Notes |
|---|---|---|---|
| Controls (compact) | `stop`, `pauseResume`, `blackout`, `saveFrame`, `record`, `previous`, `next`, `random`, `presets`, `settings` | button | |
| Controls | `showPreviousCue`, `showNextCue` | button | with `-uitestShowSeed` |
| Controls | `showCueStatus` | static text | label `Show`, value `Cue n of 5, …` |
| Controls | `emergencyBlackout` | button | |
| Preset browser | `favoritesFilter` | segmented control | |
| Preset browser | `node:collections`, `node:myPresets` | button (navigation) | |
| Preset browser | first pack `node:*` | button | |
| Pack folder | first `preset:*` row and its `star:*` | button | preset label non-empty |
| Collections | `newCollection` | button | |
| My Presets | `importUserPreset` (or the screen's import control) | button | |
| Settings | `showEditorLink`, `storageLink`, `licensesLink`, `visual.projectM` | button | |
| Show editor | `showAddCurrentScene` | button | |
| Show editor | `showCue1` … `showCue5` | element | label = cue label, value starts `Cue n of 5`; cue 1 selected |

Each: exists, label non-empty, hittable after reveal.

## C3 — Audit filters

Audit types: `.sufficientElementDescription`, `.hitRegion`, `.contrast`, `.dynamicType`, `.trait`.
A filter entry = (screen, audit type, element identifier or label, reason). The list and its
outcome are kept in `AccessibilityScreensUITests.swift` (`AuditFilter.entries`) and summarised in
the feature's status line; whole types or screens are never ignored.
