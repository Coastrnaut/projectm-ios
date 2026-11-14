# Research: PRE-010 Preset Quick Audition

Decisions taken under owner rules 4 and 9 (conservative, local-first).

## PRE-010-D1: the preview is a separate state, not a selection

- **Decision**: `current` stays the committed preset during a preview; an in-memory `audition`
  holds the original, the preset on screen, a loading preset, the list scope and a notice. `onScreen`
  is `audition.showing ?? current`.
- **Rationale**: Every persistent effect of a selection (`lastPresetID`, scope, PRE-006 dwell,
  warm-up, PRE-012 proving) hangs off `select` and `current`. Not going through them is how R2 is
  met by construction instead of by undoing writes afterwards (an undo of a write is never
  byte-identical for every store, and PRE-006's dwell timer would already be scheduled).
- **Alternatives**: snapshot and restore stored values on Cancel (rejected: races with the dwell
  timer and with other writers; Keep would still need special casing); a second renderer for the
  preview (rejected: memory, and a preview should look exactly like the real thing).

## PRE-010-D2: Keep commits without a second load

- **Decision**: The post-load bookkeeping of `select` moves into `didSelect(_:)`; Keep calls
  `setScope(listScope)` and `didSelect(shown)`.
- **Rationale**: Loading the same preset again restarts it with a visible projectM blend from
  itself. Keep must look like nothing happened on screen.

## PRE-010-D3: generation counter for in-flight loads

- **Decision**: Each preview, Keep, Cancel and a committed selection bumps a counter; a preview load
  that returns under an older counter changes no state. Keep is disabled while a preview is loading.
- **Rationale**: Loads are async. Without the counter a slow preview finishing after Cancel would
  re-open the audition. Renderer loads are issued in call order, so the original's reload issued by
  Cancel is the last one the engine sees.

## PRE-010-D4: the imported-preset guard sees previews

- **Decision**: A previewed imported preset is passed through `userGuard.willShow` before the load and
  `failedOnScreen` on failure; `stoppedShowing` when it leaves the screen. `didShow` (proving) runs
  only on Keep, and for the original on Cancel.
- **Rationale**: PRE-012-R18's crash note exists so a preset that crashes the app is quarantined at
  the next launch; a preview can crash the engine just like a selection. Proving requires the
  preset to be `current`, so it starts at Keep.

## PRE-010-D5: where Preview is offered

- **Decision**: An optional `previewScope` on `PresetRow`; the browser's lists pass the scope a tap
  would choose from. Preview appears first in the touch-and-hold menu, as the first leading swipe
  action and as the VoiceOver action "Preview", only when `canPreview` holds (playable, not flagged
  under Reduce flashing, not on screen).
- **Rationale**: A tap's meaning stays unchanged (muscle memory); three entry points cover touch,
  swipe and VoiceOver users. Flagged presets would otherwise bypass ACC-002's warning.

## PRE-010-D6: the bar

- **Decision**: A bottom `safeAreaInset` on the browser's navigation stack, so it shows over every
  list depth without moving it. Cancel carries `.keyboardShortcut(.cancelAction)` (Escape). A failure
  with nothing previewed shows only the notice and an OK button that clears it.
- **Rationale**: The list, navigation path and scroll position are never touched, so returning to
  them is exact without storing offsets.
