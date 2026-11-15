# Contract: OUT-008 Grid Warp

## C1 — `GridWarp` (PresentationLifecycle)

See data-model.md. Pure Swift, builds on Linux. Every accepted value satisfies all rules of research OUT-008-D4;
`init?(stored:)`, `init?(columns:rows:points:)`, edits and resampling never produce an invalid value.

## C2 — Compositor

- `public struct OutputWarpMesh: Sendable, Equatable` and `@MainActor public protocol OutputWarpReceiver`.
- `Compositor.outputWarp: OutputWarpMesh` (default `.none`): while active, `composite(into:)`'s screen pass is drawn
  into a pooled picture of the output's format and size and then through the mesh into `output` (uncovered pixels
  opaque black). `encodeOutput`, captures and `encodeScene` never warp. `.none`: the exact pre-OUT-008 pass.
- `Compositor.warpedFrames: Int`, `holdsWarpPicture: Bool` (tests).
- Identity exactness: with an explicit identity mesh (guides off) the output bytes equal the `.none` output bytes.

## C3 — FX-019 output step (CFlashLimiter, ANGLE)

- `void PMFlashLimiterSetWarp(PMFlashLimiter *, int columns, int rows, const float *points, int guides)`: columns or
  rows < 2 (or NULL points) turns it off; at most 9 × 9 points copied (x, y pairs, picture-relative, y down).
- The output step of `PMFlashLimiterFinish` draws through the mesh while set; `PMFlashLimiterDrawOutput(…, display)`
  applies calibration and warp only when `display` is non-zero.
- `ANGLERenderer`'s view is an `OutputWarpReceiver`; the renderer passes the view's mesh every frame; a REC-001 capture
  is the unwarped content.

## C4 — App

- `VisualSlotView.outputWarp` (external slots only; the device slot and a leaving visual get `.none`), `warpState`
  ("yes", "no", "unsupported", nil).
- `ExternalDisplayCoordinator.gridWarp`, `beginGridWarpEditing()`, `endGridWarpEditing()`, `gridWarpSummary`
  ("warp=<identity|custom> grid=<C>x<R> guides=<on|off> applied=<yes|no|unsupported|none>").
- `ExternalOutputSetting.gridWarp` with key `settings.externalDisplay.gridWarp`; Settings › External Display ›
  "Grid warp…" (`externalGridWarpButton`) opens `GridWarpEditorView` (identifiers `gridWarpProbe`, `gridWarpDone`,
  `gridWarpReset`, `gridWarpSize`, `gridWarpNudge.<dir>`, `gridWarpHandle.<r>.<c>`, `gridWarpReason`).
- DEBUG probe `externalGridWarp` (the coordinator's `gridWarpSummary`).

## C5 — OUT-014 profile

- Optional `settings.gridWarp` object `{"columns": Int, "rows": Int, "points": [{"x": Double, "y": Double}]}`; absent
  = identity; written only when not the identity; any invalid content → `invalidValue("settings.gridWarp")`.
