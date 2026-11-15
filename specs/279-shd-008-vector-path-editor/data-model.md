# Data Model: SHD-008 Vector Path Editor

## VectorPoint
`x`, `y`: Double in 0…1 (y down). Codable `{"x", "y"}`.

## VectorPath (valid by construction)
- `points: [VectorPoint]` (3…32, implicitly closed). Equality and hashing on points only.
- `triangles` (index triples) and `cumulativeAreas` — derived in `init`, not stored.
- `init(_:) throws(VectorPathIssue)`; `static func validate(_:) -> VectorPathIssue?`.
- `area` (signed shoelace), `contains(_:)` (even-odd), `sample(_ r1, _ r2, _ r3) -> VectorPoint`.
- `static let default` = diamond (0.5,0) (1,0.5) (0.5,1) (0,0.5).
- Codable: `{"points": [...]}`; decoding throws on an invalid path (callers decide the outcome).

## VectorPathIssue (one reason)
`tooFewPoints(Int)`, `tooManyPoints(Int)`, `outOfRange(index)`, `duplicatePoint(index)`, `tooSmall`,
`crossesItself(edgeA, edgeB)`; each has a user `message`.

## VectorPathDraft (editor state)
`points`, `isClosed`, `selected: Int?`, `committed: VectorPath?`, `message: String?`.
Transitions: open → (add/move/delete/undo) → `close()` → closed → (move/nudge/delete: refused if
invalid) → `startOver()` → open (committed path kept until the next close).

## Uses
- `LayerMaskShape.path(VectorPath)`, kind name `"path"`, geometry kind 3 with local = (p − 0.5)·scale.
- `ParticleEmitterSettings.Shape.path` + `path: VectorPath` (default `.default`); spawn position
  x = (px − 0.5)·shapeWidth, y = (0.5 − py)·shapeHeight.
