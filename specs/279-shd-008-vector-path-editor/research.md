# Research: SHD-008 Vector Path Editor

- **SHD-008-D1 Model home.** Decision: `VectorPath` in VisualGenerators. Rationale: Compositor and
  SceneFormat already depend on it, and the emitter lives there. Alternatives: Compositor (the emitter
  could not reach it), a new package (CI group churn for one file).
- **SHD-008-D2 Polygon only, 3…32 points, unit square.** See spec Clarifications. The mask maps
  local = p − 0.5 so the CMP-007 polygon geometry (kind 3, even-odd distance) draws it unchanged.
- **SHD-008-D3 Intersection test.** Decision: orientation-based segment test with tolerance 1e-12 on the
  cross product (coordinates are ≤ 1, so 1e-12 is far below any meaningful edit, 1e-6 duplicate rule).
  Non-adjacent pairs: any intersection or touch rejects. Adjacent pairs (sharing vertex i): reject when
  collinear and pointing back over each other (overlap), i.e. the cross is ~0 and the dot of the two edge
  directions from the shared vertex is > 0. For a triangle every pair is adjacent, so only overlap matters.
  Alternatives: Bentley–Ottmann (needless for n ≤ 32).
- **SHD-008-D4 Uniform area sampling.** Decision: ear-clipping triangulation computed in `init` (O(n³)
  worst case, n ≤ 32, once per edit), cumulative areas, draw r₁ → triangle by linear scan of ≤ 30
  cumulative areas (no allocation), r₂, r₃ → barycentric (reflected if r₂ + r₃ > 1). Always three draws.
- **SHD-008-D5 Invalid saved data.** Scene: drop with `droppedField` (CMP-007 precedent). Emitter: default
  path (SHD-007 lenient-decode precedent).
- **SHD-008-D6 Editor model.** Decision: a pure `VectorPathDraft` value (points, closed flag, last
  committed valid path, message). Before closing, adds and moves are accepted when the coordinates are in
  range and not a duplicate of a neighbour; `closeIssue` reports why the draft cannot close yet; `close()`
  succeeds only for a valid path. After closing, every edit builds the candidate path and is refused
  (state unchanged, message set) when invalid. Mirrors `CornerPin.moving` (OUT-007).
- **SHD-008-D7 Undo.** Mask: each committed path is one `LayerInspectorCoordinator.set` (scene history
  records it). Emitter: settings are saved at once, as every SHD-007 control.
- **SHD-008-D8 Editor presentation.** A pushed screen: canvas (square, unit square fitted), handles with
  44 pt targets, VoiceOver per point (Move left/right/up/down, Delete), selected-point nudge row, buttons
  Close path, Delete point, Start over; inline message `vectorPathMessage`. Tap on empty canvas adds a
  point while drawing, or inserts nothing once closed (closed paths are edited by drag, nudge, delete,
  or "Start over").
