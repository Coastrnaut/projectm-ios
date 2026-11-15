// TessellationLattice.swift — VIS-018's tilings: settings, the lattice placement, the per-point tile classification, the
// colouring, and the same operations as Metal text (specs/307-vis-018-geometric-tessellation; research VIS-018-D2 to D6;
// contract C1, C3).
//
// One definition of the tiling, used by the CPU mirror (alignment proof, flash estimate) and repeated operation for
// operation in `TessellationShader`. Work is in tile units: q = (pixel − frame centre) / s + o, with s = shorter side / N
// and o the frame centre's place in the lattice (squares: a tile centre when N is odd, a vertex when N is even; every
// other tiling: its most symmetric point at the lattice origin). The lattice therefore depends only on the output size,
// the tiling and N: never on time, audio, symmetry or palette (spec Clarifications Q2, A1–A6). Square: unit squares.
// Triangular lattice a1 = (1, 0), a2 = (½, √3/2) in skew coordinates v = y / (√3/2), u = x − v/2 for triangles,
// hexagons (nearest lattice point, the Voronoi cell: inradius ½), trihexagonal (barycentrics in the lattice triangle:
// > ½ is the hexagon at that vertex, else the medial triangle) and truncated square (octagon of inradius ½ at the
// nearest integer point, else the 45° square at the cell corner). Ties go one fixed way (floor, strict comparisons), the
// same in Swift and MSL. Colouring: symmetry order k and mirror act through smooth functions of kθ of the tile centre
// about the frame centre, so rotated (and mirrored) tiles look identical with no wedge seams. No allocation, no wall
// clock. Plain Swift; builds on Linux.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// The tilings (VIS-018-R2); stored by the app as the raw value.
public enum TessellationTiling: String, CaseIterable, Sendable {
    case triangle
    case square
    case hexagon
    case trihexagonal
    case truncatedSquare

    public static let defaultTiling = TessellationTiling.hexagon

    /// The shader's index.
    public var index: Int {
        switch self {
        case .triangle: 0
        case .square: 1
        case .hexagon: 2
        case .trihexagonal: 3
        case .truncatedSquare: 4
        }
    }

    public var title: String {
        switch self {
        case .triangle: "Triangles"
        case .square: "Squares"
        case .hexagon: "Hexagons"
        case .trihexagonal: "Trihexagonal"
        case .truncatedSquare: "Octagons"
        }
    }

    /// How many tile shapes (shape indices 0..<count).
    public var shapeCount: Int {
        switch self {
        case .triangle: 2
        case .square, .hexagon: 1
        case .trihexagonal: 3
        case .truncatedSquare: 2
        }
    }
}

/// The tessellation's own palette choice (VIS-018-R6): VIS-001's built-in palettes.
public enum TessellationPalette: String, CaseIterable, Sendable {
    case spectrum
    case ice
    case mono

    public static let defaultPalette = TessellationPalette.spectrum

    public var visualPalette: VisualPalette {
        switch self {
        case .spectrum: .spectrum
        case .ice: .ice
        case .mono: .mono
        }
    }

    public var title: String {
        switch self {
        case .spectrum: "Spectrum"
        case .ice: "Ice"
        case .mono: "Mono"
        }
    }

    /// The palette drawn: this choice, unless the shared palette is not Spectrum (colour-blind-safe or custom wins).
    public func resolved(over shared: VisualPalette) -> VisualPalette {
        shared == .spectrum ? visualPalette : shared
    }
}

/// The mode's settings in `NoiseFieldConfiguration.tessellation` (nil there: the mode is off).
public struct TessellationSettings: Sendable, Equatable {
    public static let tileRange: ClosedRange<Int> = 2...16
    public static let defaultTiles = 6
    public static let symmetries: [Int] = [1, 2, 3, 4, 6]
    public static let defaultSymmetry = 6
    public static let `default` = TessellationSettings()

    public var tiling: TessellationTiling
    /// Tiles (lattice periods) across the shorter side, 2…16.
    public var tiles: Int
    /// Rotational order of the colouring: 1 (none), 2, 3, 4 or 6.
    public var symmetry: Int
    public var mirror: Bool
    public var palette: TessellationPalette

    public init(tiling: TessellationTiling = .defaultTiling, tiles: Int = TessellationSettings.defaultTiles,
                symmetry: Int = TessellationSettings.defaultSymmetry, mirror: Bool = false,
                palette: TessellationPalette = .defaultPalette) {
        self.tiling = tiling
        self.tiles = tiles
        self.symmetry = symmetry
        self.mirror = mirror
        self.palette = palette
        self = clamped()
    }

    /// Out-of-range values take their defaults.
    public func clamped() -> TessellationSettings {
        var c = self
        if !Self.tileRange.contains(c.tiles) { c.tiles = Self.defaultTiles }
        if !Self.symmetries.contains(c.symmetry) { c.symmetry = Self.defaultSymmetry }
        return c
    }

    /// "6-fold symmetry", "mirrored 6-fold symmetry", "no symmetry", "mirror symmetry" (order 1 mirrored).
    public var symmetryDescription: String {
        if symmetry <= 1 { return mirror ? "mirror symmetry" : "no symmetry" }
        return mirror ? "mirrored \(symmetry)-fold symmetry" : "\(symmetry)-fold symmetry"
    }
}

/// One tile: integer lattice coordinates, its shape, its centre and a point's distance to its edge (tile units).
public struct TessellationCell: Sendable, Equatable {
    public var i: Int
    public var j: Int
    /// Shape index (data-model.md): 0 the main shape; triangles 1 = down; trihexagonal 1/2 = up/down triangle;
    /// truncated square 1 = small square.
    public var shape: Int
    /// The tile's centre (tile units, lattice coordinates).
    public var centre: SIMD2<Float>
    /// The classified point's distance to the tile's edge (tile units, ≥ 0 inside).
    public var edge: Float

    public init(i: Int, j: Int, shape: Int, centre: SIMD2<Float>, edge: Float) {
        self.i = i
        self.j = j
        self.shape = shape
        self.centre = centre
        self.edge = edge
    }

    /// Same tile (coordinates and shape).
    public func sameTile(_ other: TessellationCell) -> Bool { i == other.i && j == other.j && shape == other.shape }
}

/// Where the lattice sits in a `width × height` output with `tiles` periods across the shorter side.
public struct TessellationPlacement: Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var tiles: Int
    public var tiling: TessellationTiling

    public init(width: Int, height: Int, tiles: Int, tiling: TessellationTiling) {
        self.width = max(width, 1)
        self.height = max(height, 1)
        self.tiles = TessellationSettings.tileRange.contains(tiles) ? tiles : TessellationSettings.defaultTiles
        self.tiling = tiling
    }

    /// Pixels per tile unit: shorter side / N.
    public var tileSize: Float { Float(min(width, height)) / Float(tiles) }

    /// The frame centre in pixels.
    public var centre: SIMD2<Float> { SIMD2<Float>(Float(width), Float(height)) * 0.5 }

    /// The frame centre's place in the lattice (tile units).
    public var origin: SIMD2<Float> { TessellationLattice.origin(tiling: tiling, tiles: tiles) }

    /// A pixel position (pixel units, rows top first) in tile units, exactly as the shader.
    public func unit(pixel: SIMD2<Float>) -> SIMD2<Float> {
        TessellationLattice.unit(pixel: pixel, size: SIMD2<Float>(Float(width), Float(height)), tiles: Float(tiles), origin: origin)
    }

    /// The tile at a pixel position.
    public func cell(pixel: SIMD2<Float>) -> TessellationCell { TessellationLattice.classify(unit(pixel: pixel), tiling: tiling) }

    /// A lattice point (tile units) in pixels.
    public func pixel(unit: SIMD2<Float>) -> SIMD2<Float> { (unit - origin) * tileSize + centre }
}

/// The CPU mirror of the tiling (`TessellationShader`).
public enum TessellationLattice {
    /// √3/2: the triangular lattice's row height.
    public static let rowHeight: Float = 0.8660254
    /// 1/√2.
    public static let halfRoot2: Float = 0.70710678
    /// The truncated square's small-square half-diagonal: 1 − 1/√2.
    public static let cornerSquare: Float = 0.29289322
    /// Trihexagonal hexagon inradius √3/4.
    public static let kagomeHexInradius: Float = 0.4330127

    /// The frame centre's lattice position (tile units).
    public static func origin(tiling: TessellationTiling, tiles: Int) -> SIMD2<Float> {
        tiling == .square && tiles % 2 == 1 ? SIMD2<Float>(0.5, 0.5) : SIMD2<Float>(0, 0)
    }

    /// The shader's mapping: (pixel − size/2) / (shorter / tiles) + origin.
    public static func unit(pixel: SIMD2<Float>, size: SIMD2<Float>, tiles: Float, origin: SIMD2<Float>) -> SIMD2<Float> {
        let s: Float = min(size.x, size.y) / max(tiles, 1)
        return (pixel - 0.5 * size) / s + origin
    }

    /// The inradius of `shape` (tile units).
    public static func inradius(tiling: TessellationTiling, shape: Int) -> Float {
        switch tiling {
        case .square, .hexagon: return 0.5
        case .triangle: return rowHeight / 3   // 1/(2√3)
        case .trihexagonal: return shape == 0 ? kagomeHexInradius : rowHeight / 6
        case .truncatedSquare: return shape == 0 ? 0.5 : cornerSquare * halfRoot2
        }
    }

    /// Skew (u, v) → cartesian.
    @inlinable
    static func cartesian(_ u: Float, _ v: Float) -> SIMD2<Float> { SIMD2<Float>(u + 0.5 * v, v * rowHeight) }

    /// The tile containing `q` (tile units). Non-finite input classifies as the origin's point.
    public static func classify(_ raw: SIMD2<Float>, tiling: TessellationTiling) -> TessellationCell {
        let q = SIMD2<Float>(raw.x.isFinite ? raw.x : 0, raw.y.isFinite ? raw.y : 0)
        switch tiling {
        case .square: return square(q)
        case .triangle: return triangle(q)
        case .hexagon: return hexagon(q)
        case .trihexagonal: return trihexagonal(q)
        case .truncatedSquare: return truncatedSquare(q)
        }
    }

    static func square(_ q: SIMD2<Float>) -> TessellationCell {
        let fi: Float = q.x.rounded(.down), fj: Float = q.y.rounded(.down)
        let fx: Float = q.x - fi, fy: Float = q.y - fj
        let edge: Float = min(min(fx, 1 - fx), min(fy, 1 - fy))
        return TessellationCell(i: Int(fi), j: Int(fj), shape: 0, centre: SIMD2<Float>(fi + 0.5, fj + 0.5), edge: edge)
    }

    /// Skew coordinates of `q`: the rhombus corner (i, j) and the fractions (fu, fv).
    @inlinable
    static func skew(_ q: SIMD2<Float>) -> (i: Float, j: Float, fu: Float, fv: Float) {
        let v: Float = q.y / rowHeight
        let u: Float = q.x - 0.5 * v
        let i: Float = u.rounded(.down), j: Float = v.rounded(.down)
        return (i, j, u - i, v - j)
    }

    static func triangle(_ q: SIMD2<Float>) -> TessellationCell {
        let s: (i: Float, j: Float, fu: Float, fv: Float) = skew(q)
        if s.fu + s.fv < 1 {
            let edge: Float = min(min(s.fu, s.fv), 1 - s.fu - s.fv) * rowHeight
            return TessellationCell(i: Int(s.i), j: Int(s.j), shape: 0, centre: cartesian(s.i + 1 / 3, s.j + 1 / 3), edge: edge)
        }
        let edge: Float = min(min(1 - s.fu, 1 - s.fv), s.fu + s.fv - 1) * rowHeight
        return TessellationCell(i: Int(s.i), j: Int(s.j), shape: 1, centre: cartesian(s.i + 2 / 3, s.j + 2 / 3), edge: edge)
    }

    /// Distance from the centre of a pointy-top hexagon (inradius ½) to its edge along the worst side normal.
    @inlinable
    static func hexagonEdge(_ d: SIMD2<Float>) -> Float {
        let a: Float = abs(d.x)
        let b: Float = abs(0.5 * d.x + rowHeight * d.y)
        let c: Float = abs(-0.5 * d.x + rowHeight * d.y)
        return 0.5 - max(a, max(b, c))
    }

    static func hexagon(_ q: SIMD2<Float>) -> TessellationCell {
        let s: (i: Float, j: Float, fu: Float, fv: Float) = skew(q)
        var bestI: Float = s.i, bestJ: Float = s.j
        var bestCentre: SIMD2<Float> = cartesian(s.i, s.j)
        var bestD: Float = ((q - bestCentre) * (q - bestCentre)).sum()
        for k in 1..<4 {
            let ci: Float = s.i + Float(k & 1), cj: Float = s.j + Float(k >> 1)
            let c: SIMD2<Float> = cartesian(ci, cj)
            let d: Float = ((q - c) * (q - c)).sum()
            if d < bestD { bestD = d; bestI = ci; bestJ = cj; bestCentre = c }
        }
        return TessellationCell(i: Int(bestI), j: Int(bestJ), shape: 0, centre: bestCentre, edge: hexagonEdge(q - bestCentre))
    }

    /// Distance to the edge of a flat-top hexagon of inradius √3/4.
    @inlinable
    static func kagomeHexEdge(_ d: SIMD2<Float>) -> Float {
        let a: Float = abs(rowHeight * d.x + 0.5 * d.y)
        let b: Float = abs(d.y)
        let c: Float = abs(-rowHeight * d.x + 0.5 * d.y)
        return kagomeHexInradius - max(a, max(b, c))
    }

    static func trihexagonal(_ q: SIMD2<Float>) -> TessellationCell {
        let s: (i: Float, j: Float, fu: Float, fv: Float) = skew(q)
        let up: Bool = s.fu + s.fv < 1
        // Barycentrics and their vertices (skew): up (i,j) (i+1,j) (i,j+1); down (i+1,j) (i,j+1) (i+1,j+1).
        let l0: Float = up ? 1 - s.fu - s.fv : 1 - s.fv
        let l1: Float = up ? s.fu : 1 - s.fu
        let l2: Float = up ? s.fv : s.fu + s.fv - 1
        let v0: SIMD2<Float> = up ? SIMD2<Float>(s.i, s.j) : SIMD2<Float>(s.i + 1, s.j)
        let v1: SIMD2<Float> = up ? SIMD2<Float>(s.i + 1, s.j) : SIMD2<Float>(s.i, s.j + 1)
        let v2: SIMD2<Float> = up ? SIMD2<Float>(s.i, s.j + 1) : SIMD2<Float>(s.i + 1, s.j + 1)
        var vertex: SIMD2<Float>?
        if l0 > 0.5 { vertex = v0 } else if l1 > 0.5 { vertex = v1 } else if l2 > 0.5 { vertex = v2 }
        if let v = vertex {
            let c: SIMD2<Float> = cartesian(v.x, v.y)
            return TessellationCell(i: Int(v.x), j: Int(v.y), shape: 0, centre: c, edge: kagomeHexEdge(q - c))
        }
        let edge: Float = min(min(0.5 - l0, 0.5 - l1), 0.5 - l2) * rowHeight
        let centre: SIMD2<Float> = up ? cartesian(s.i + 1 / 3, s.j + 1 / 3) : cartesian(s.i + 2 / 3, s.j + 2 / 3)
        return TessellationCell(i: Int(s.i), j: Int(s.j), shape: up ? 1 : 2, centre: centre, edge: edge)
    }

    static func truncatedSquare(_ q: SIMD2<Float>) -> TessellationCell {
        let ri: Float = (q.x + 0.5).rounded(.down), rj: Float = (q.y + 0.5).rounded(.down)
        let ax: Float = abs(q.x - ri), ay: Float = abs(q.y - rj)
        if ax + ay <= halfRoot2 {
            let edge: Float = min(min(0.5 - ax, 0.5 - ay), (halfRoot2 - ax - ay) * halfRoot2)
            return TessellationCell(i: Int(ri), j: Int(rj), shape: 0, centre: SIMD2<Float>(ri, rj), edge: edge)
        }
        let ci: Float = q.x.rounded(.down), cj: Float = q.y.rounded(.down)
        let centre = SIMD2<Float>(ci + 0.5, cj + 0.5)
        let edge: Float = (cornerSquare - abs(q.x - centre.x) - abs(q.y - centre.y)) * halfRoot2
        return TessellationCell(i: Int(ci), j: Int(cj), shape: 1, centre: centre, edge: edge)
    }

    // MARK: colouring

    /// The symmetry value (0…1) of a tile whose centre is `offset` from the frame centre (tile units): k-fold (and
    /// mirror-symmetric when `mirror`) in the offset's angle; ½ at the centre.
    public static func symmetryValue(_ offset: SIMD2<Float>, order: Int, mirror: Bool) -> Float {
        let r: Float = (offset * offset).sum().squareRoot()
        guard r >= 1e-4, r.isFinite else { return 0.5 }
        let k = Float(min(max(order, 1), 6))
        let theta: Float = atan2f(offset.y, offset.x)
        if mirror { return 0.5 + 0.5 * cosf(k * theta) }
        return 0.5 + 0.3 * cosf(k * theta) + 0.2 * sinf(2 * k * theta)
    }

    /// The triangle wave 1 − |1 − 2·fract(x)| (continuous; 0…1).
    @inlinable
    public static func triangleWave(_ x: Float) -> Float {
        let f: Float = x - x.rounded(.down)
        return 1 - abs(1 - 2 * f)
    }

    /// A tile's palette position (0…1) and light factor (0.8…1) for the frame's drift and light phase.
    public static func tileLook(offset: SIMD2<Float>, order: Int, mirror: Bool, drift: Float, light: Float) -> (t: Float, light: Float) {
        let r: Float = min((offset * offset).sum().squareRoot(), 1e4)
        let a: Float = symmetryValue(offset, order: order, mirror: mirror)
        let t: Float = triangleWave(0.5 * a + 0.06 * r + drift)
        let wave: Float = 0.5 + 0.5 * cosf(2 * Float.pi * (light - 0.15 * r))
        let lit: Float = 1 - TessellationDrive.lightDepth * wave
        return (t.isFinite ? min(max(t, 0), 1) : 0, lit.isFinite ? min(max(lit, 0), 1) : 1)
    }
}

/// The GPU side of `TessellationLattice`: Metal Shading Language authored in this module (no external code; SHD-011).
/// Placed after the noise field's body (uses `NoiseOut` and `NoiseUniforms`).
public enum TessellationShader {
    /// Floats of the mode's own uniform block (buffer 1).
    public static let uniformFloats = 12

    public static let functions = """

    // VIS-018: geometric tessellation (matches TessellationLattice operation for operation).
    struct TessUniforms {
        float tiling;
        float tiles;
        float order;
        float mirror;
        float inset;
        float drift;
        float light;
        float originX;
        float originY;
        float pad0;
        float pad1;
        float pad2;
    };

    // xy: lattice i, j; z: shape; w: edge distance (tile units). centre: the tile's centre (tile units).
    static float4 vis_tess_cell(float2 q, int tiling, thread float2 &centre) {
        const float H = 0.8660254;
        if (tiling == 1) {
            float fi = floor(q.x), fj = floor(q.y);
            float fx = q.x - fi, fy = q.y - fj;
            centre = float2(fi + 0.5, fj + 0.5);
            return float4(fi, fj, 0.0, min(min(fx, 1.0 - fx), min(fy, 1.0 - fy)));
        }
        if (tiling == 4) {
            float ri = floor(q.x + 0.5), rj = floor(q.y + 0.5);
            float ax = abs(q.x - ri), ay = abs(q.y - rj);
            if (ax + ay <= 0.70710678) {
                centre = float2(ri, rj);
                return float4(ri, rj, 0.0, min(min(0.5 - ax, 0.5 - ay), (0.70710678 - ax - ay) * 0.70710678));
            }
            float ci = floor(q.x), cj = floor(q.y);
            centre = float2(ci + 0.5, cj + 0.5);
            return float4(ci, cj, 1.0, (0.29289322 - abs(q.x - centre.x) - abs(q.y - centre.y)) * 0.70710678);
        }
        float v = q.y / H;
        float u = q.x - 0.5 * v;
        float i = floor(u), j = floor(v);
        float fu = u - i, fv = v - j;
        if (tiling == 0) {
            if (fu + fv < 1.0) {
                centre = float2((i + 1.0 / 3.0) + 0.5 * (j + 1.0 / 3.0), (j + 1.0 / 3.0) * H);
                return float4(i, j, 0.0, min(min(fu, fv), 1.0 - fu - fv) * H);
            }
            centre = float2((i + 2.0 / 3.0) + 0.5 * (j + 2.0 / 3.0), (j + 2.0 / 3.0) * H);
            return float4(i, j, 1.0, min(min(1.0 - fu, 1.0 - fv), fu + fv - 1.0) * H);
        }
        if (tiling == 2) {
            float bi = i, bj = j;
            float2 bc = float2(i + 0.5 * j, j * H);
            float bd = dot(q - bc, q - bc);
            for (int k = 1; k < 4; k++) {
                float ci = i + float(k & 1), cj = j + float(k >> 1);
                float2 c = float2(ci + 0.5 * cj, cj * H);
                float d = dot(q - c, q - c);
                if (d < bd) { bd = d; bi = ci; bj = cj; bc = c; }
            }
            centre = bc;
            float2 d = q - bc;
            float e = 0.5 - max(abs(d.x), max(abs(0.5 * d.x + H * d.y), abs(-0.5 * d.x + H * d.y)));
            return float4(bi, bj, 0.0, e);
        }
        // tiling 3: trihexagonal
        bool up = fu + fv < 1.0;
        float l0 = up ? 1.0 - fu - fv : 1.0 - fv;
        float l1 = up ? fu : 1.0 - fu;
        float l2 = up ? fv : fu + fv - 1.0;
        float2 v0 = up ? float2(i, j) : float2(i + 1.0, j);
        float2 v1 = up ? float2(i + 1.0, j) : float2(i, j + 1.0);
        float2 v2 = up ? float2(i, j + 1.0) : float2(i + 1.0, j + 1.0);
        bool hex = true;
        float2 vx = v0;
        if (l0 > 0.5) { vx = v0; } else if (l1 > 0.5) { vx = v1; } else if (l2 > 0.5) { vx = v2; } else { hex = false; }
        if (hex) {
            centre = float2(vx.x + 0.5 * vx.y, vx.y * H);
            float2 d = q - centre;
            float e = 0.4330127 - max(abs(H * d.x + 0.5 * d.y), max(abs(d.y), abs(-H * d.x + 0.5 * d.y)));
            return float4(vx.x, vx.y, 0.0, e);
        }
        centre = up ? float2((i + 1.0 / 3.0) + 0.5 * (j + 1.0 / 3.0), (j + 1.0 / 3.0) * H)
                    : float2((i + 2.0 / 3.0) + 0.5 * (j + 2.0 / 3.0), (j + 2.0 / 3.0) * H);
        return float4(i, j, up ? 1.0 : 2.0, min(min(0.5 - l0, 0.5 - l1), 0.5 - l2) * H);
    }

    static float vis_tess_inradius(int tiling, float shape) {
        if (tiling == 0) { return 0.8660254 / 3.0; }
        if (tiling == 3) { return shape < 0.5 ? 0.4330127 : 0.8660254 / 6.0; }
        if (tiling == 4) { return shape < 0.5 ? 0.5 : 0.29289322 * 0.70710678; }
        return 0.5;
    }

    static float2 vis_tess_unit(float2 position, float2 size, constant TessUniforms &t) {
        float s = min(size.x, size.y) / max(t.tiles, 1.0);
        return (position - 0.5 * size) / s + float2(t.originX, t.originY);
    }

    fragment float4 vis_tess_fragment(NoiseOut in [[stage_in]], constant NoiseUniforms &u [[buffer(0)]],
                                      constant TessUniforms &t [[buffer(1)]]) {
        float2 size = max(u.size, float2(1.0));
        int tiling = clamp(int(t.tiling + 0.5), 0, 4);
        float2 q = vis_tess_unit(in.position.xy, size, t);
        q = select(q, float2(0.0), isnan(q) || isinf(q));
        float2 centre;
        float4 cell = vis_tess_cell(q, tiling, centre);
        float s = min(size.x, size.y) / max(t.tiles, 1.0);
        float inset = clamp(t.inset, 0.0, 1.0) * vis_tess_inradius(tiling, cell.z) * s;
        float cover = clamp(cell.w * s - inset + 0.5, 0.0, 1.0);
        float2 offset = centre - float2(t.originX, t.originY);
        float r = min(length(offset), 10000.0);
        float a = 0.5;
        if (r >= 1e-4) {
            float k = clamp(t.order, 1.0, 6.0);
            float theta = atan2(offset.y, offset.x);
            a = t.mirror > 0.5 ? 0.5 + 0.5 * cos(k * theta) : 0.5 + 0.3 * cos(k * theta) + 0.2 * sin(2.0 * k * theta);
        }
        float x = 0.5 * a + 0.06 * r + t.drift;
        float tt = clamp(1.0 - abs(1.0 - 2.0 * (x - floor(x))), 0.0, 1.0);
        float wave = 0.5 + 0.5 * cos(6.2831853 * (t.light - 0.15 * r));
        float lit = clamp(1.0 - 0.2 * wave, 0.0, 1.0);
        float position = tt * 15.0;
        int i = min(int(position), 14);
        float f = position - float(i);
        float3 c = mix(u.palette[i].rgb, u.palette[i + 1].rgb, f) * lit * u.brightness * cover;
        c = select(c, float3(0.0), isnan(c) || isinf(c));
        return float4(clamp(c, 0.0, 1.0), 1.0);
    }

    // Tests only (VIS-018 contract C3): lattice i, j, shape and the edge distance in pixels.
    fragment float4 vis_tess_cells_fragment(NoiseOut in [[stage_in]], constant NoiseUniforms &u [[buffer(0)]],
                                            constant TessUniforms &t [[buffer(1)]]) {
        float2 size = max(u.size, float2(1.0));
        int tiling = clamp(int(t.tiling + 0.5), 0, 4);
        float2 centre;
        float4 cell = vis_tess_cell(vis_tess_unit(in.position.xy, size, t), tiling, centre);
        float s = min(size.x, size.y) / max(t.tiles, 1.0);
        return float4(cell.x, cell.y, cell.z, cell.w * s);
    }
    """
}
