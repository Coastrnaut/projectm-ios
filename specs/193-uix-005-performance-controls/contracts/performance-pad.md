# Contract: the performance pad (UIX-005)

## C1 Accessibility identifiers and labels

| Identifier | Element | Label | Value |
|---|---|---|---|
| `performanceLayout` | button in the controls | "Performance layout" / "Standard layout" | — |
| `performancePad` | container | "Performance controls" | — |
| `perfPreviousCue` | button | "Previous cue" | — |
| `perfNextCue` | button | "Next cue" | — |
| `perfTapTempo` | button | "Tap tempo" | SHOW-011 tap value ("Tap 1 of 4", "120 BPM, manual") |
| `perfBlackout` | button | "Black out output" / "Restore output" / "Restoring output" | OUT-010 phase value |
| `perfCueReadout` | static text | "Show" | cue position ("Cue 2 of 5, Build", "No cues") |
| `perfTempoReadout` | static text | "Tempo" | SHOW-011 spoken readout |
| `performanceSafeArea` | probe (`-uitestDiagnostics` only) | — | "x,y,w,h" safe-area frame |

## C2 Geometry

Every target ≥ 60 × 60 pt (72 × 72 when both size classes are regular), inside the safe area, in
portrait, landscape and at AX5. The status stack is inset by the pad's reserved edges.

## C3 Behavior

Next/Previous: `show.next()`/`previous()`; Tap: `tempo.tap()`; none shows the controls. Blackout
follows data-model "Blackout target". SHOW-014's emergency button is hidden while the pad shows.

## C4 Launch flags

`-uitestPerformanceLayout` (DEBUG): start with the layout on.
