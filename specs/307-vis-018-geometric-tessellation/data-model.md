# Data Model: VIS-018 Geometric Tessellation

## TessellationTiling (enum, String raw value; stored by the app)
| Case | Shapes (index) | Frame centre | Title |
|---|---|---|---|
| triangle | triangle up 0, down 1 | vertex | Triangles |
| square | square 0 | tile centre (N odd) / vertex (N even) | Squares |
| hexagon (default) | hexagon 0 | hexagon centre | Hexagons |
| trihexagonal | hexagon 0, triangle 1, 2 | hexagon centre | Trihexagonal |
| truncatedSquare | octagon 0, square 1 | octagon centre | Octagons |

## TessellationPalette (enum, String raw value): spectrum (default), ice, mono → `VisualPalette`.

## TessellationSettings (struct, Sendable, Equatable)
- `tiling` (default hexagon), `tiles: Int` 2…16 (default 6), `symmetry: Int` ∈ {1, 2, 3, 4, 6} (default 6),
  `mirror: Bool` (default false), `palette` (default spectrum). `clamped()` maps anything else to the default.
  Stored in `NoiseFieldConfiguration.tessellation` (nil = off; on forces every other mode off).

## TessellationPlacement (struct; from width, height, N, tiling)
- `tileSize` s = min(w, h)/N px; `centre` (w/2, h/2); `origin` o (frame centre in tile units).
  `unit(pixel:)` → tile units; `pixel(unit:)` → pixels.

## TessellationCell (struct, Equatable)
- `i, j: Int32` lattice coordinates, `shape: Int` (index above); `centre: SIMD2<Float>` (tile units); `edge: Float`
  (distance to the tile's edge, tile units, ≥ 0 inside). `inradius` per shape.

## TessellationDrive (struct)
- `swell` 0…1, `drift` [0, 1), `light` [0, 1), drift/light speeds (turns/s), `brightness` 0.45…0.75, last frame
  time; `advance(groups:timeNanoseconds:reduceMotion:)`, `reset()`, `state` → `TessellationFrame` (inset fraction
  0.08…0.25, drift, light, brightness; sanitized).
