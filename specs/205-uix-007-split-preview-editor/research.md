# Research: UIX-007 Split Preview/Editor

- **UIX-007-D1 Scale the visual, never re-lay it out.** Decision: the visual view keeps the full
  window size and is uniformly scaled (`scaleEffect`, anchor top-leading) and offset into the output
  rect. Rationale: the aspect is preserved by construction; the renderer's drawable, recordings
  (REC-003), frame captures (REC-001) and OUT-004's device shape (derived from the device slot's
  bounds) are unchanged, so resizing costs no GPU re-allocation and cannot disturb a recording.
  Rejected: framing the slot at the output rect's size (re-allocates drawables on every drag step,
  resizes recordings mid-take, and pixel rounding of the frame would perturb the reported device
  shape).
- **UIX-007-D2 Output aspect = the full window's aspect.** The visual fills the window today, so the
  window's width ÷ height is the shape the user sees outside the split. Rotation or a window resize
  changes the aspect the same way it does without the split.
- **UIX-007-D3 Bounds and snaps.** Editor 320–560 pt (Settings' list reads well from 320 pt, the
  iPhone width class); output pane ≥ 320 pt; divider hit area 24 pt (visible 1 pt line and a grip).
  Snaps 320 / 400 / 480 (Narrow, Standard, Wide); snap radius 24 pt. On a 13-inch iPad in portrait
  (1032 pt) the maximum editor is 560 (1032 − 24 − 320 = 688 ≥ 560); on an 11-inch iPad in portrait
  (834 pt) 834 − 24 − 320 = 490 pt. The split fits when the window is at least 320 + 24 + 320 = 664 pt.
- **UIX-007-D4 Presentation through a trailing safe-area inset.** `safeAreaInset(edge: .trailing)`
  puts the divider and editor beside the layers, so everything that respects the safe area (status
  stack, controls, UIX-005 pad, overlays) lays out in the output pane at its real size, while views
  that ignore the safe area (black background, tap target) extend under the editor, which covers
  them. Implementation (2026-11-14): the black background and the visual are a separate *backdrop*
  that the host lays out at the full window size outside the inset, with the visual only drawn
  scaled (`scaleEffect` and `offset`, render-only). Three attempts that kept the visual inside the
  inset content failed the UI test's probe: the visual's own `.ignoresSafeArea()` does not reach past
  a `safeAreaInset` (it was laid out at the pane's width), and an explicit full-window frame either
  set the layers' size (pushing the editor off screen) or leaked the inset into the width (1376 × 714
  on screen for a 1376 × 1032 window).
- **UIX-007-D5 Stored width.** One Double (points) under `settings.splitEditor.width`. FILE-005
  excluded (depends on the device's screen), so FILE-011's Settings erase covers it; `ALLOWED_KEYS`
  lists it; `-uitestResetNotice` removes it. Invalid (non-finite, ≤ 0) → 400.
- **UIX-007-D6 Probe from UIKit.** XCUITest frames of a scaled representable are not guaranteed to
  reflect `scaleEffect`; the DEBUG probe reads the device `VisualSlotView`'s
  `convert(bounds, to: nil)` (which applies ancestor layer transforms) and the window size, so the
  test checks what is on screen, not the computed layout.
- **UIX-007-D7 Accessibility of the divider.** One element, label "Editor width", value "400 points,
  Standard" (snap name only at a snap point), trait adjustable via `accessibilityAdjustableAction`;
  increment/decrement go to the next/previous snap point (or the bound beyond the last one). Hover
  effect `.highlight` for pointers.
- **UIX-007-D8 Done in the editor.** `SettingsView` uses `@Environment(\.dismiss)`, which does nothing
  outside a presentation. An environment closure `splitEditorClose` (nil by default) is called
  instead when set; it sets `showSettings = false`, so SCN-010 and autosave run as for the sheet.
