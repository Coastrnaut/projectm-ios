# Research: VIS-018 Geometric Tessellation

- **VIS-018-D1 Placement in the generator.** Decision: a noise-field mode (spec Clarifications Q1). Rationale: one
  reviewed compile site, shared palette/Reduce Motion/glow/flash plumbing, in-place switching. Alternatives: own
  generator (new compile site), flat-shape pass (CPU polygons, second rounding path).
- **VIS-018-D2 Lattice geometry.** Decision: work in tile units q = (pixel − centre) / s + o, s = shorter / N, o the
  frame centre's lattice position (squares: (½, ½) when N is odd, else (0, 0); all others (0, 0)). Square: floor.
  Triangular lattice a1 = (1, 0), a2 = (½, √3/2), skew coordinates v = y / (√3/2), u = x − v/2. Hexagons: nearest of the
  4 rhombus corners (Voronoi; Delaunay guarantees the nearest is a corner of the containing triangle); edge distance ½ −
  max |d·nₖ|, nₖ at 0°, 60°, 120°. Triangles: rhombus split by fu + fv < 1; edge distance from the three skew lines ×
  √3/2. Trihexagonal (kagome): triangle classification, then barycentrics λ; λmax > ½ → the hexagon at that vertex
  (inradius √3/4, side normals 30°, 90°, 150°), else the medial triangle (edge distance (½ − λ)·√3/2). Truncated
  square: octagon at round(q) when |qx| + |qy| ≤ 1/√2 (inradius ½), else the 45° square at the nearest corner
  (inradius (1 − 1/√2)/√2). Ties are broken deterministically (floor, strict `<`), the same order in Swift and MSL.
- **VIS-018-D3 Proof strategy.** Decision: the CPU lattice is the oracle for A1–A5 over all 5 × 15 × 6 combinations
  at a 48 × 48 grid of sample points (fast), and per pixel (A3, A4) at quarter-scale sizes for N ∈ {2, 7, 16}; the full
  per-pixel sweep runs with `VIS018_ALIGNMENT_SWEEP=1`. An independent polygon oracle (tile polygon from its centre and
  shape) checks containment and edge distance. The GPU check renders `vis_tess_cells_fragment` into `rgba32Float`
  (exact integers) for every tiling × N ∈ {2, 5, 16} × 6 aspect ratios at small sizes and compares every pixel more than
  0.01 px from a seam with the CPU.
- **VIS-018-D4 Symmetry.** Decision: colouring only, by smooth functions of kθ (Q3). cos kθ is exactly k-fold and
  mirror-symmetric; cos kθ + sin 2kθ is k-fold and chiral. At r < 10⁻⁴ the value is ½ (atan2(0, 0) avoided).
- **VIS-018-D5 Flash estimate.** Decision: each of the 64 samples is the tile at that point at its area mean:
  tile colour × light × brightness × (1 − inset)² (regular polygons are tangential, so an inset by a fraction of the
  inradius scales the area by (1 − f)²). Upper-bounds no point but tracks the area light the envelope measures.
- **VIS-018-D6 Palette.** Decision: reuse `VisualPalette` (Spectrum, Ice, Mono); the effective palette is the
  tessellation's choice unless the shared palette is not Spectrum (colour-blind-safe or custom wins).
