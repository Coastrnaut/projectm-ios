# Research: UIX-004 Favorite Parameter Shelf

## UIX-004-D1 What is pinnable and available

- Decision: an entry is available when it names a parameter that the MOD-001 registry contains and that
  UIX-003 lists as inspectable (has an `AppSettings` write target). Everything else is unavailable.
- Rationale: a shelf control must write through the Settings path (spec Clarifications); a registered
  parameter without a control could only show a dead control.
- Alternatives: pin any registry parameter and show read-only rows (clutter on a performance strip).

## UIX-004-D2 Storage and corrupt values

- Decision: `[String]` under `settings.parameterShelf.pins`. Decode with `defaults.object(forKey:)`:
  an array keeps each String element; other elements become `String(describing:)`; a non-array value
  becomes one entry of its text form; duplicates keep the first position. The decoded list is written
  back only when the user changes the shelf. Unknown entries are never dropped automatically.
- Rationale: one key, readable by FILE-005's string-list backup; unknown IDs round-trip a downgrade;
  every corrupt shape is counted and removable instead of silently lost.
- Alternatives: JSON Data with a version (heavier; the backup handles string lists already);
  dropping invalid entries at load (loses a newer version's pins after a downgrade).

## UIX-004-D3 Order, limit and editing

- Decision: entries keep stored order; `pinned` is the available entries in that order. Reordering
  works on `pinned` and writes `pinned + missing` (unavailable entries move to the end, keeping their
  relative order). The limit (8) counts available pins only. Editing lives in a Settings section (List
  `onMove`/`onDelete` with an Edit button, plus VoiceOver actions Move up, Move down, Remove from Shelf);
  the overlay strip only shows controls and the note.
- Rationale: List editing is the standard, accessible reorder; the overlay is a performance surface and
  should not enter an edit mode.

## UIX-004-D4 Reaching the shelf from UIX-003 without widening SettingsView

- Decision: an environment value `\.parameterShelf` set once on the Settings sheet in `VisualizerView`; the
  UIX-003 entry modifier and the inspector sheet read it (the sheet re-injects it into its content). The
  sheet's Pin to Shelf button sits in its navigation bar, so it is in reach at every text size.
- Rationale: other agents edit `SettingsView.swift` in parallel; one line instead of a new parameter
  and edits at seven call sites. Set inside `SettingsView.body` it pushed that body's type check towards
  the 200 ms limit, so it moved to the call site.
- VoiceOver: the shelf action is a plain `accessibilityAction(named:)`. An `accessibilityActions` builder
  holding a Button stopped XCTest from dragging the ACC-005 Intensity slider (GlowUITests failed twice;
  passed again with plain named actions, 2026-11-14).

## UIX-004-D5 Shelf placement and visibility

- Decision: inside `ControlsOverlay`'s content, above the button rows, so it shows and hides with the
  controls (auto-hide, Reduce Motion fade policy) and scrolls with them at accessibility sizes. Blackout
  does not hide the controls (OUT-010), so the shelf follows them.
- Alternatives: a separate always-on strip (would cover the visual and break the hide rules).

## UIX-004-D6 Logging

- Decision: `Logger(subsystem: "org.projectmios.ProjectMiOS", category: "parameterShelf")`, one
  message at load when unavailable entries exist: the count public, the entries private.
