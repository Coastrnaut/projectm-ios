# Contract: Split editor (UIX-007)

## C1 Presentation

- Regular horizontal size class and `SplitEditorLayout.fits` → Settings in the trailing pane
  (`splitEditor` container, `splitEditorPane`), no sheet. Otherwise the Settings sheet as before.
- Done (`Settings` navigation bar) closes either presentation; `coordinator.showSettings` is the
  single source of truth.

## C2 Divider (`splitEditorDivider`)

- Drag: the editor width follows (clamped) live; release snaps per `SplitEditorLayout.snapped`, stored.
- Accessibility: label "Editor width"; value "<n> points" plus ", Narrow|Standard|Wide" at a snap
  point; adjustable (increment → `nextSnap`, decrement → `previousSnap`); stored after each step.

## C3 Output

- The visual keeps its full window size; on screen it is scaled by `layout.scale` and placed at
  `layout.outputRect` (aspect = window aspect). The pane is black outside it.

## C4 Probe (DEBUG, `-uitestDiagnostics`)

- `splitOutputFrame` static text, value `"x,y,w,h|W,H"`: the device visual slot's frame in window
  coordinates (from UIKit) and the window size, refreshed every 0.25 s; `"none"` when no slot.

## C5 Launch arguments (DEBUG)

- `-uitestSplitEditorWidth <pt>` sets the stored width at launch (after the reset).
