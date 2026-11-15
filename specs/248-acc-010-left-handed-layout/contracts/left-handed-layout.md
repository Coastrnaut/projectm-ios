# Contract: ACC-010 Left-Handed Layout

## C1 — Placement (ShowControl, pure)

- `ControlsSide.resolve(oneHanded:leftHanded:)` as in the data model.
- `PerformanceLayout.placement(_ side: ControlsSide) -> PadPlacement`.
  - Right: bar `[previousCue, nextCue, tapTempo, blackout]`; grid `[[previousCue, nextCue], [tapTempo, blackout]]`; leading column `[previousCue, nextCue]`, trailing `[tapTempo, blackout]`; cue readout leading.
  - Left: each row reversed, then the cue pair re-ordered Previous first; columns swapped; cue readout trailing.
- `PerformanceLayout.targetFrames(width:height:side:readoutHeight:) -> [PadTarget: OneHandedLayout.Rect]`.
- Invariants (tested): for every arrangement, `left[t]` equals the horizontal mirror of `right[t]` (`x' = width − maxX`, `y` equal) within 1 pt for `tapTempo` and `blackout`; the union of the cue pair mirrors likewise and Previous cue stays left of (bar, grid) or above (columns) Next cue; the key sets are equal.

## C2 — Views (app)

- Settings → Performance: section `leftHanded` (for `-uitestSettingsSection`), switch `leftHandedToggle`, title "Left-handed controls", footer as in the spec's Clarifications.
- `PerformancePadLayer(side:)` draws bar, grid and columns from `placement(side)`; identifiers, labels, values, hints and the B key unchanged.
- The emergency Black out button (`emergencyBlackout`) sits at the bottom trailing corner for `right`, bottom leading for `left`.
- The visual slot, the external display and recordings receive no new modifier.

## C3 — Tests

- ShowControl `HandedPlacementTests`: C1 invariants at three sizes per arrangement; side resolution.
- App `LeftHandedAppTests`: preference default, storage, side derivation; external display snapshot byte-identical with the real pad right- and left-handed on the device window; device visual untransformed.
- UI `LeftHandedUITests`: (a) portrait: emergency button and bar frames before and after switching the setting in Settings are mirrored within 1 pt, identifiers identical; (b) landscape with the setting on: Tap tempo and Black out in the leading column, cue targets trailing, columns mirrored within 1 pt.
