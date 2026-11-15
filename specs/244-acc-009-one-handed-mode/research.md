# Research: ACC-009 One-Handed Performance Mode

## ACC-009-D1 Thumb zone

- **Decision**: portrait-shaped safe area: bottom 40 % of the height × 75 % of the width from the chosen edge; landscape-shaped: 40 % of the width from the chosen edge × bottom 75 % of the height.
- **Rationale**: one-handed thumb-reach studies place the comfortable area in the lower third to half of the screen on the holding side; in landscape a one-handed grip holds the phone's end, so the reach is a band along that side. Fixed fractions make the rule testable on every size.
- **Alternatives**: absolute reach radius in points (depends on hand size, untestable); full bottom width (the far corner is out of reach on a Pro Max).

## ACC-009-D2 Feasibility on the smallest phone

- **Decision**: rows of up to as many targets as fit the zone's width (8 pt margin, 8 pt spacing); the pad group first, then the main group; main targets shrink in 4 pt steps to 44 pt when needed.
- **Rationale**: worst case is the 375 × 667 pt iPhone SE in landscape with the pad and a show at an accessibility size: zone 266.8 × 281 pt; pad 3 + 1 at 60 pt (128 pt), main 4 + 3 at 56 pt (120 pt), total 272 pt with margins: fits. Portrait SE: zone 281 × 259 pt; pad row 280 pt wide fits; total 204 pt.
- **Alternatives**: a scrolling cluster (hides actions); a fan/arc layout (harder to test and to hit).

## ACC-009-D3 Where the code goes

- **Decision**: the geometry and the critical-action catalogue in ShowControl (`OneHandedLayout.swift`); the app's `OneHandedControlsLayer` draws the main group (and the pad group when the pad is off) and reports the reserved band through the same `performanceInsets` state the pad uses; `PerformancePadLayer` draws its four targets at the layout's frames when one-handed (so its readouts, Hold action and B key stay its own).
- **Rationale**: reuses UIX-005's tested inset path; keeps VisualizerView edits to a few lines; the layer takes the coordinator's sub-objects to stay in the type-check budget.
- **Alternatives**: a new arrangement inside ControlsOverlay (the card scrolls at AX sizes, so targets could leave the zone); one layer drawing the pad too (duplicates the pad's readout logic).

## ACC-009-D4 Identifiers

- **Decision**: cluster targets keep the standard identifiers (`stop`, `pauseResume`, `previous`, `next`, `random`, `presets`, `settings`, `blackout`, `tapTempo`, `showPreviousCue`, `showNextCue`), and the pad's targets keep `perf*`; the card leaves those buttons out while one-handed, so each identifier exists once.
- **Rationale**: the acceptance compares the same identifiers across the switch; QA-009 can reuse the controls' list.

## ACC-009-D5 Dynamic Type

- **Decision**: base side = the text-scaled 44 pt (`relativeTo: .title3`) clamped to 44…56 pt; symbols only, Large Content Viewer on every target (UIX-005-D4's audit lesson: captions clipped at large sizes).
