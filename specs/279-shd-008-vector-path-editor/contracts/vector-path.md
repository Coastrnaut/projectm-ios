# Contract: SHD-008 Vector Path

## P1 Validation (`VectorPath.validate`)
Checked in order; the first failure is the result:
1. count < 3 → `tooFewPoints`; count > 32 → `tooManyPoints`.
2. any coordinate non-finite or outside 0…1 → `outOfRange(i)`.
3. |pᵢ − pᵢ₊₁| ≤ 1e-6 (wrapping) → `duplicatePoint(i)`.
4. |area| ≤ 1e-4 → `tooSmall`.
5. any non-adjacent edge pair intersecting or touching, or any adjacent pair overlapping collinearly →
   `crossesItself`.

## P2 Scene form (`composite.mask`)
`{"shape": "path", "points": [{"x", "y"}…], "feather", "inverted", "transform"}`; every field written;
decode → encode byte-identical. On decode, `points` missing → malformed; count outside 3…32 or any
P1 failure → mask dropped, `droppedField` warning "…has an unusable path (<reason>); the mask was
dropped." Points are not clamped (an out-of-range point is a P1 failure). Format version stays 1.

## P3 Emitter form (`settings.particleFountain.emitter` → `settings.path`)
`"path": {"points": [...]}`, always written; missing or invalid → `VectorPath.default`.
`"shape": "path"` selects it.

## P4 Spawn
Three seeded draws: r₁ picks the triangle by cumulative area, r₂, r₃ the barycentric point (reflected when
r₂ + r₃ > 1); then direction, speed, lifetime as SHD-007. Spawn counts unchanged.

## P5 Editor (UI identifiers)
`vectorPathCanvas`, `vectorPathPoint.<n>` (1-based; actions Move left/right/up/down, Delete point),
`vectorPathMessage`, `vectorPathClose`, `vectorPathDelete`, `vectorPathStartOver`,
`vectorPathNudge.<left|right|up|down>`; links `layerControl.maskPathEdit`, `particleEmitterPathEdit`.
