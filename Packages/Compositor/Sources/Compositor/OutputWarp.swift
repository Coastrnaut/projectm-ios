// OutputWarp.swift — OUT-008 (specs/309-out-008-grid-warp, contract C2; research OUT-008-D1, D3): the render description
// of an external display's grid warp and the protocol of a visual's view that can draw it in its final pass. CPU only,
// builds on Linux. The mesh is validated before it gets here (PresentationLifecycle's `GridWarp`); the passes draw
// whatever they are given and only check that it is well formed.
//
// Points are picture-relative (0…1 across and down the visual's picture, y down), row by row. The passes draw
// `subdivisions` × `subdivisions` quads per control cell, each vertex placed on the uniform Catmull-Rom surface through
// the points (linear end extrapolation), sampling the picture at the vertex's own lattice position.

/// The grid warp a final pass draws through (OUT-008-R2), or `.none`.
public struct OutputWarpMesh: Sendable, Equatable {
    public let columns: Int
    public let rows: Int
    /// Row by row, `columns × rows`.
    public let points: [SIMD2<Float>]
    /// OUT-008-D7: white guide lines along the control grid (the editor is open).
    public let showsGuides: Bool

    public static let maximumSide = 9
    public static let subdivisions = 16
    public static let none = OutputWarpMesh(columns: 0, rows: 0, points: [], showsGuides: false)

    public init(columns: Int, rows: Int, points: [SIMD2<Float>], showsGuides: Bool) {
        self.columns = columns
        self.rows = rows
        self.points = points
        self.showsGuides = showsGuides
    }

    /// The evenly spaced grid (every point where it is): exact pass-through when drawn (OUT-008-R7).
    public static func identity(columns: Int, rows: Int, showsGuides: Bool = false) -> OutputWarpMesh {
        var points: [SIMD2<Float>] = []
        for r in 0..<max(rows, 0) {
            for c in 0..<max(columns, 0) {
                points.append(SIMD2<Float>(Float(c) / Float(max(columns - 1, 1)), Float(r) / Float(max(rows - 1, 1))))
            }
        }
        return OutputWarpMesh(columns: columns, rows: rows, points: points, showsGuides: showsGuides)
    }

    /// A well-formed mesh (2…9 per side, the right count, finite points): the passes draw it. Anything else (`.none`
    /// included) is drawn as before OUT-008.
    public var isActive: Bool {
        let sides: ClosedRange<Int> = 2...Self.maximumSide
        guard sides.contains(columns), sides.contains(rows), points.count == columns * rows else { return false }
        return points.allSatisfy { (p: SIMD2<Float>) -> Bool in p.x.isFinite && p.y.isFinite }
    }

    /// Vertices the passes draw (two triangles per quad).
    public var vertexCount: Int {
        isActive ? (columns - 1) * (rows - 1) * Self.subdivisions * Self.subdivisions * 6 : 0
    }

    /// The points as interleaved floats (x, y, …).
    public var flattened: [Float] {
        points.flatMap { (p: SIMD2<Float>) -> [Float] in [p.x, p.y] }
    }
}

/// OUT-008 (contract C2): a visual's view whose renderer can draw its final pass through a grid warp. `VisualSlotView`
/// sets the mesh on external slots and `.none` on the device slot.
@MainActor
public protocol OutputWarpReceiver: AnyObject {
    var outputWarp: OutputWarpMesh { get set }
    /// False when the visual shown by this view has no pass that draws it (OUT-008-R8: not covered).
    var acceptsOutputWarp: Bool { get }
}
