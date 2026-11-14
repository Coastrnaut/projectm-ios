# Research: UIX-005 Performance Control Layout

- **UIX-005-D1 Arrangement from the space, not the orientation.** Decision: wider than tall → side
  columns; otherwise a bottom bar. Rationale: iPad split views and Stage Manager windows can be
  portrait-shaped on a landscape device. Alternative rejected: `UIDevice.orientation` (wrong for
  windows, and reads face-up/face-down).
- **UIX-005-D2 Target size.** Decision: 60 pt, 72 pt when both size classes are regular. Apple's HIG
  minimum is 44 pt; performers need targets they hit without looking. 72 pt (1.2×) on iPad keeps the
  physical size closer to the phone's on a larger screen. A narrow bar (one row does not fit:
  4 × side + 3 × spacing + 2 × margin > width) wraps to two rows of two.
- **UIX-005-D3 Reserved insets.** Decision: the pad reports the edge space it uses (columns: column
  width each side; bar: measured height + 8 pt bottom) and the status stack is padded by it. Rationale:
  the controls and badges must never sit under a target; the visual stays full screen.
- **UIX-005-D4 Accessibility sizes.** Decision: fixed target sizes filled by symbols, no captions,
  readouts (`footnote`) two lines then tail truncation with no size cap, Large Content Viewer on every
  target (`accessibilityShowsLargeContentViewer`), the iOS answer for fixed-size controls at large
  text sizes. Tried and dropped in implementation (2026-11-14, audit runs): a `caption2` caption
  under each symbol (contrast finding without an element, then clipped text at the audit's larger
  sizes as `caption`), and a `...accessibility2` cap on the readouts ("Dynamic Type partially
  unsupported"). The audit passes without them.
- **UIX-005-D8 Type-check budget.** The pad takes `ShowCoordinator`, `TempoCoordinator` and
  `ExternalDisplayCoordinator`, not `AppCoordinator`: the first member lookup on AppCoordinator in a
  new file measured 220-263 ms of type-checking (budget 200 ms).
- **UIX-005-D5 Blackout ownership.** Decision: the pad's target follows `OutputBlackout.Phase`:
  `offersEmergencyBlackout` → Black out (B key), `offersRestore` → Restore (B key stays on the badge),
  `restoreWaiting` → disabled. SHOW-014's corner button is hidden while the pad shows, so one B owner
  exists in every phase.
- **UIX-005-D6 No pop-up controls.** Pad actions call `show.next()`/`previous()` and `tempo.tap()`
  directly (the key-command path), not the controls' wrappers that call `showControls()`.
- **UIX-005-D7 Safe-area probe for tests.** XCUITest has no safe-area API; with `-uitestDiagnostics`
  the pad layer exposes a probe `performanceSafeArea` whose value is the safe-area frame in window
  coordinates ("x,y,w,h"). Tests compare target frames against it.
