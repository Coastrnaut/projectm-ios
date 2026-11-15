# Data Model: OUT-008 Grid Warp

## GridWarp (PresentationLifecycle, value type)

| Field | Type | Rule |
|---|---|---|
| `columns` | Int | 3…9 (`sizeRange`) |
| `rows` | Int | 3…9 |
| `points` | [GridWarpPoint] (x, y Double) | row-major, `columns × rows`; picture-relative, y down |

- `identity(columns:rows:)`: point (c, r) = (c / (columns − 1), r / (rows − 1)); `.identity` = 3 × 3.
- `isIdentity`: equal to `identity(columns:rows:)` of its own size.
- `validity: GridWarpValidity` — `.valid` or the first failing rule: `badSize`, `nonFinite`, `outOfRange`,
  `cellFolded(row, column)`, `cellDegenerate(row, column)`, `surfaceFolds`, `outlineCrosses`, `tooSmall`
  (research OUT-008-D4). Constants: `range` −0.5…1.5, `minimumTurnSine` 0.035, `minimumArea` 0.05,
  `subdivisions` 16, `nudgeStep` 0.005.
- `init?(columns:rows:points:)` (valid only), `candidate(...)` (any, for tests and import checks).
- `map(u:v:) -> GridWarpPoint`: the Catmull-Rom surface (research OUT-008-D2).
- `moving(row:column:to:) -> GridWarpEdit` / `nudging(...)`: the moved point is clamped to the range; the result is
  `.applied(GridWarp)` or `.refused(GridWarpValidity)` (the caller keeps the old mesh).
- `resampled(columns:rows:) -> GridWarp`: the surface sampled at the new lattice when valid, else the identity of that
  size.
- `stored: String` / `init?(stored:)`: "CxR:x,y;x,y;…" (six decimals); nil when malformed or invalid.

## OutputWarpMesh (Compositor, render description)

| Field | Type | Rule |
|---|---|---|
| `columns`, `rows` | Int | 0 = none; else 2…9 (the pass does not validate — it draws what it is given) |
| `points` | [SIMD2<Float>] | row-major, picture-relative, y down |
| `showsGuides` | Bool | draw guide lines along the control grid |

- `.none`: no pass. `isActive`: columns ≥ 2 and rows ≥ 2 and the count matches.
- `OutputWarpReceiver` (protocol, @MainActor): `outputWarp: OutputWarpMesh { get set }`, `acceptsOutputWarp: Bool`.

## Bridge (app)

- `GridWarp.outputMesh(showsGuides:)`: `.none` for the identity without guides; else the points as floats.

## State

- `ExternalOutputSetting.gridWarp` (stored key `settings.externalDisplay.gridWarp`) → `ExternalDisplayCoordinator.gridWarp`
  and `isEditingGridWarp` → every external `VisualSlotView.outputWarp` → the held receiver.
