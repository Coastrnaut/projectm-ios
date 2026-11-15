// GridWarp.swift — OUT-008 (spec specs/309-out-008-grid-warp, contract C1; research OUT-008-D2, D3, D4, D8): the
// external output's grid warp, its smooth surface, its validator and its stored form. Pure Swift, no UIKit.
//
// * A grid warp is columns × rows control points (each 3…9) in picture-relative coordinates (0…1 across and down the
//   visual's picture, y down), row by row. The identity places them evenly (c / (columns − 1), r / (rows − 1)).
// * The surface between the points is uniform Catmull-Rom in u and v with linear end extrapolation (phantom points
//   P₋₁ = 2P₀ − P₁, Pₙ = 2Pₙ₋₁ − Pₙ₋₂): it passes through every point and reproduces affine grids exactly, so the
//   identity maps every point to itself.
// * It is drawn as `subdivisions` × `subdivisions` quads (two triangles each) per control cell. Lattice vertex (i, j)
//   lies in cell min(i / 16, cells − 1) at t = (i − 16·cell) / 16 — the same integer steps as the GPU passes
//   (GridWarpPass, CFlashLimiter), so the triangles validated here are the triangles drawn.
// * Valid (no fold) only when, in this order: the size is 3…9 × 3…9 with columns × rows points; every coordinate is
//   finite and within −0.5…1.5; every control cell is a strictly convex quad with the identity's orientation and no
//   turn below ≈ 2° (sine 0.035); every drawn triangle keeps the identity's orientation with a positive area; the drawn
//   outline never crosses itself; the drawn area is at least 5 % of the picture. A triangulated disk whose triangles
//   all keep their orientation and whose outline is a simple curve is mapped one-to-one: nothing overlaps.
// * Edits clamp the moved point to the range; an invalid result is refused with its reason (the mesh stays).

/// A control point in picture-relative coordinates.
public struct GridWarpPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Why a mesh is not accepted (the first failing rule), or `.valid`.
public enum GridWarpValidity: Equatable, Sendable {
    case valid
    case badSize
    case nonFinite
    case outOfRange
    case cellFolded(row: Int, column: Int)
    case cellDegenerate(row: Int, column: Int)
    case surfaceFolds
    case outlineCrosses
    case tooSmall
}

/// The result of an edit: the new mesh, or the reason it was refused (the caller keeps the old one).
public enum GridWarpEdit: Equatable, Sendable {
    case applied(GridWarp)
    case refused(GridWarpValidity)
}

public struct GridWarp: Equatable, Sendable {
    public let columns: Int
    public let rows: Int
    /// Row by row, `columns × rows`.
    public let points: [GridWarpPoint]

    public static let sizeRange: ClosedRange<Int> = 3...9
    public static let range: ClosedRange<Double> = -0.5...1.5
    public static let minimumTurnSine = 0.035
    public static let minimumArea = 0.05
    /// Drawn quads per control cell and axis (research OUT-008-D3).
    public static let subdivisions = 16
    public static let nudgeStep = 0.005
    /// The sizes the editor offers (any 3…9 per axis is valid).
    public static let editorSizes: [Int] = [3, 5, 9]
    /// Twice a drawn triangle's area must exceed this (in picture units²).
    static let minimumTriangleCross = 1e-10

    private init(unchecked columns: Int, _ rows: Int, _ points: [GridWarpPoint]) {
        self.columns = columns
        self.rows = rows
        self.points = points
    }

    /// The evenly spaced grid of that size (sizes clamped to 3…9).
    public static func identity(columns: Int, rows: Int) -> GridWarp {
        let c: Int = min(max(columns, sizeRange.lowerBound), sizeRange.upperBound)
        let r: Int = min(max(rows, sizeRange.lowerBound), sizeRange.upperBound)
        var points: [GridWarpPoint] = []
        points.reserveCapacity(c * r)
        for row in 0..<r {
            for column in 0..<c {
                points.append(GridWarpPoint(x: Double(column) / Double(c - 1), y: Double(row) / Double(r - 1)))
            }
        }
        return GridWarp(unchecked: c, r, points)
    }

    public static let identity = GridWarp.identity(columns: 3, rows: 3)

    /// Nil unless the points form a valid mesh.
    public init?(columns: Int, rows: Int, points: [GridWarpPoint]) {
        let candidate = GridWarp(unchecked: columns, rows, points)
        guard candidate.isValid else { return nil }
        self = candidate
    }

    /// Any mesh, valid or not (tests of the rules, import checks).
    public static func candidate(columns: Int, rows: Int, points: [GridWarpPoint]) -> GridWarp {
        GridWarp(unchecked: columns, rows, points)
    }

    public func point(row: Int, column: Int) -> GridWarpPoint { points[row * columns + column] }

    public var isIdentity: Bool { self == GridWarp.identity(columns: columns, rows: rows) }
    public var isValid: Bool { validity == .valid }

    // MARK: - Surface (research OUT-008-D2)

    /// A point with linear extrapolation outside the grid (the Catmull-Rom phantom points).
    func extended(row: Int, column: Int) -> GridWarpPoint {
        if row < 0 { return Self.extrapolate(extended(row: 0, column: column), extended(row: 1, column: column)) }
        if row >= rows { return Self.extrapolate(extended(row: rows - 1, column: column), extended(row: rows - 2, column: column)) }
        if column < 0 { return Self.extrapolate(point(row: row, column: 0), point(row: row, column: 1)) }
        if column >= columns { return Self.extrapolate(point(row: row, column: columns - 1), point(row: row, column: columns - 2)) }
        return point(row: row, column: column)
    }

    /// 2a − b.
    private static func extrapolate(_ a: GridWarpPoint, _ b: GridWarpPoint) -> GridWarpPoint {
        GridWarpPoint(x: 2 * a.x - b.x, y: 2 * a.y - b.y)
    }

    /// Catmull-Rom weights at t (0…1): (0, 1, 0, 0) at 0, (0, 0, 1, 0) at 1.
    public static func weights(_ t: Double) -> (Double, Double, Double, Double) {
        let t2: Double = t * t, t3: Double = t2 * t
        let w0: Double = 0.5 * (-t3 + 2 * t2 - t)
        let w1: Double = 0.5 * (3 * t3 - 5 * t2 + 2)
        let w2: Double = 0.5 * (-3 * t3 + 4 * t2 + t)
        let w3: Double = 0.5 * (t3 - t2)
        return (w0, w1, w2, w3)
    }

    /// The surface in cell (`cellColumn`, `cellRow`) at (`tx`, `ty`).
    public func surface(cellColumn: Int, tx: Double, cellRow: Int, ty: Double) -> GridWarpPoint {
        let wx = Self.weights(tx), wy = Self.weights(ty)
        let ax: [Double] = [wx.0, wx.1, wx.2, wx.3], ay: [Double] = [wy.0, wy.1, wy.2, wy.3]
        var x = 0.0, y = 0.0
        for j in 0..<4 {
            var rx = 0.0, ry = 0.0
            for i in 0..<4 {
                let p: GridWarpPoint = extended(row: cellRow - 1 + j, column: cellColumn - 1 + i)
                rx += ax[i] * p.x
                ry += ax[i] * p.y
            }
            x += ay[j] * rx
            y += ay[j] * ry
        }
        return GridWarpPoint(x: x, y: y)
    }

    /// The surface at picture point (u, v) in 0…1.
    public func map(u: Double, v: Double) -> GridWarpPoint {
        let cx: Int = columns - 1, cy: Int = rows - 1
        let su: Double = min(max(u, 0), 1) * Double(cx), sv: Double = min(max(v, 0), 1) * Double(cy)
        let c: Int = min(Int(su.rounded(.down)), cx - 1), r: Int = min(Int(sv.rounded(.down)), cy - 1)
        return surface(cellColumn: c, tx: su - Double(c), cellRow: r, ty: sv - Double(r))
    }

    /// Lattice vertices along one axis (cells × subdivisions + 1).
    public var latticeColumns: Int { (columns - 1) * Self.subdivisions + 1 }
    public var latticeRows: Int { (rows - 1) * Self.subdivisions + 1 }

    /// The drawn vertex at lattice (i, j), with the GPU's integer cell steps.
    public func latticePoint(i: Int, j: Int) -> GridWarpPoint {
        let n: Int = Self.subdivisions
        let c: Int = min(i / n, columns - 2), r: Int = min(j / n, rows - 2)
        return surface(cellColumn: c, tx: Double(i - c * n) / Double(n), cellRow: r, ty: Double(j - r * n) / Double(n))
    }

    /// Every drawn vertex, row by row (`latticeColumns × latticeRows`); the same values as `latticePoint`, computed
    /// with the padded grid and the 17 weight sets precomputed (the editor validates on every drag).
    public var lattice: [GridWarpPoint] {
        let n: Int = Self.subdivisions
        let pw: Int = columns + 2
        var padded: [GridWarpPoint] = []
        padded.reserveCapacity(pw * (rows + 2))
        for r in -1...rows {
            for c in -1...columns { padded.append(extended(row: r, column: c)) }
        }
        let table: [(Double, Double, Double, Double)] = (0...n).map { (k: Int) -> (Double, Double, Double, Double) in
            Self.weights(Double(k) / Double(n))
        }
        var out: [GridWarpPoint] = []
        out.reserveCapacity(latticeColumns * latticeRows)
        for j in 0..<latticeRows {
            let r: Int = min(j / n, rows - 2)
            let wy = table[j - r * n]
            for i in 0..<latticeColumns {
                let c: Int = min(i / n, columns - 2)
                let wx = table[i - c * n]
                out.append(Self.blend(padded, pw, c, r, wx, wy))
            }
        }
        return out
    }

    /// Σ wy[j] · Σ wx[i] · P(r − 1 + j, c − 1 + i) over the padded grid (row r − 1 is padded row r).
    private static func blend(_ padded: [GridWarpPoint], _ pw: Int, _ c: Int, _ r: Int,
                              _ wx: (Double, Double, Double, Double), _ wy: (Double, Double, Double, Double)) -> GridWarpPoint {
        var x = 0.0, y = 0.0
        for j in 0..<4 {
            let base: Int = (r + j) * pw + c
            let p0: GridWarpPoint = padded[base], p1: GridWarpPoint = padded[base + 1]
            let p2: GridWarpPoint = padded[base + 2], p3: GridWarpPoint = padded[base + 3]
            let rx: Double = wx.0 * p0.x + wx.1 * p1.x + wx.2 * p2.x + wx.3 * p3.x
            let ry: Double = wx.0 * p0.y + wx.1 * p1.y + wx.2 * p2.y + wx.3 * p3.y
            let w: Double = j == 0 ? wy.0 : (j == 1 ? wy.1 : (j == 2 ? wy.2 : wy.3))
            x += w * rx
            y += w * ry
        }
        return GridWarpPoint(x: x, y: y)
    }

    // MARK: - Validity (research OUT-008-D4)

    public var validity: GridWarpValidity {
        guard Self.sizeRange.contains(columns), Self.sizeRange.contains(rows), points.count == columns * rows else { return .badSize }
        for p in points where !p.x.isFinite || !p.y.isFinite { return .nonFinite }
        for p in points where !Self.range.contains(p.x) || !Self.range.contains(p.y) { return .outOfRange }
        if let cell = cellFailure() { return cell }
        let drawn: [GridWarpPoint] = lattice
        if !trianglesKeepOrientation(drawn) { return .surfaceFolds }
        let outline: [GridWarpPoint] = Self.outline(drawn, columns: latticeColumns, rows: latticeRows)
        if Self.crosses(outline) { return .outlineCrosses }
        return Self.area(outline) < Self.minimumArea ? .tooSmall : .valid
    }

    /// A folded cell first (anywhere), then a degenerate one.
    private func cellFailure() -> GridWarpValidity? {
        var degenerate: GridWarpValidity?
        for r in 0..<(rows - 1) {
            for c in 0..<(columns - 1) {
                let quad: [GridWarpPoint] = [point(row: r, column: c), point(row: r, column: c + 1),
                                             point(row: r + 1, column: c + 1), point(row: r + 1, column: c)]
                switch Self.quadTurns(quad) {
                case .folded: return .cellFolded(row: r, column: c)
                case .degenerate: if degenerate == nil { degenerate = .cellDegenerate(row: r, column: c) }
                case .fine: break
                }
            }
        }
        return degenerate
    }

    private enum QuadTurns { case fine, degenerate, folded }

    /// The four turns of a quad (y down; the identity's orientation is positive).
    private static func quadTurns(_ q: [GridWarpPoint]) -> QuadTurns {
        var result = QuadTurns.fine
        for i in 0..<4 {
            let a: GridWarpPoint = q[i], b: GridWarpPoint = q[(i + 1) % 4], c: GridWarpPoint = q[(i + 2) % 4]
            let e1x: Double = b.x - a.x, e1y: Double = b.y - a.y
            let e2x: Double = c.x - b.x, e2y: Double = c.y - b.y
            let lengths: Double = (e1x * e1x + e1y * e1y).squareRoot() * (e2x * e2x + e2y * e2y).squareRoot()
            if lengths == 0 { result = .degenerate; continue }
            let sine: Double = (e1x * e2y - e1y * e2x) / lengths
            if sine <= -minimumTurnSine { return .folded }
            if sine < minimumTurnSine { result = .degenerate }
        }
        return result
    }

    private func trianglesKeepOrientation(_ v: [GridWarpPoint]) -> Bool {
        let w: Int = latticeColumns
        for j in 0..<(latticeRows - 1) {
            for i in 0..<(w - 1) {
                let a: GridWarpPoint = v[j * w + i], b: GridWarpPoint = v[j * w + i + 1]
                let c: GridWarpPoint = v[(j + 1) * w + i + 1], d: GridWarpPoint = v[(j + 1) * w + i]
                if Self.cross(a, b, d) <= Self.minimumTriangleCross || Self.cross(b, c, d) <= Self.minimumTriangleCross { return false }
            }
        }
        return true
    }

    /// (b − a) × (c − a).
    static func cross(_ a: GridWarpPoint, _ b: GridWarpPoint, _ c: GridWarpPoint) -> Double {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    /// The drawn outline, clockwise on screen: top row, right column, bottom row back, left column up (no repeats).
    static func outline(_ v: [GridWarpPoint], columns w: Int, rows h: Int) -> [GridWarpPoint] {
        var out: [GridWarpPoint] = []
        for i in 0..<(w - 1) { out.append(v[i]) }
        for j in 0..<(h - 1) { out.append(v[j * w + w - 1]) }
        for i in stride(from: w - 1, to: 0, by: -1) { out.append(v[(h - 1) * w + i]) }
        for j in stride(from: h - 1, to: 0, by: -1) { out.append(v[j * w]) }
        return out
    }

    /// True when two non-adjacent edges of the closed polygon touch or cross.
    static func crosses(_ polygon: [GridWarpPoint]) -> Bool {
        let n: Int = polygon.count
        for i in 0..<n {
            let a: GridWarpPoint = polygon[i], b: GridWarpPoint = polygon[(i + 1) % n]
            let minX: Double = min(a.x, b.x), maxX: Double = max(a.x, b.x)
            let minY: Double = min(a.y, b.y), maxY: Double = max(a.y, b.y)
            for k in stride(from: i + 2, to: n, by: 1) where !(i == 0 && k == n - 1) {
                let c: GridWarpPoint = polygon[k], d: GridWarpPoint = polygon[(k + 1) % n]
                if max(c.x, d.x) < minX || min(c.x, d.x) > maxX || max(c.y, d.y) < minY || min(c.y, d.y) > maxY { continue }
                if segmentsTouch(a, b, c, d) { return true }
            }
        }
        return false
    }

    private static func segmentsTouch(_ a: GridWarpPoint, _ b: GridWarpPoint, _ c: GridWarpPoint, _ d: GridWarpPoint) -> Bool {
        let d1: Double = cross(c, d, a), d2: Double = cross(c, d, b)
        let d3: Double = cross(a, b, c), d4: Double = cross(a, b, d)
        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) { return true }
        return (d1 == 0 && onSegment(c, d, a)) || (d2 == 0 && onSegment(c, d, b))
            || (d3 == 0 && onSegment(a, b, c)) || (d4 == 0 && onSegment(a, b, d))
    }

    private static func onSegment(_ a: GridWarpPoint, _ b: GridWarpPoint, _ p: GridWarpPoint) -> Bool {
        p.x >= min(a.x, b.x) && p.x <= max(a.x, b.x) && p.y >= min(a.y, b.y) && p.y <= max(a.y, b.y)
    }

    /// The shoelace area (positive for the identity's orientation, y down).
    static func area(_ polygon: [GridWarpPoint]) -> Double {
        var sum = 0.0
        let n: Int = polygon.count
        for i in 0..<n {
            let a: GridWarpPoint = polygon[i], b: GridWarpPoint = polygon[(i + 1) % n]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    // MARK: - Edits

    /// The point moved to `target` (clamped to the range), or the reason it was refused.
    public func moving(row: Int, column: Int, to target: GridWarpPoint) -> GridWarpEdit {
        guard row >= 0, row < rows, column >= 0, column < columns else { return .refused(.badSize) }
        let clamped = GridWarpPoint(x: Self.clamp(target.x), y: Self.clamp(target.y))
        var next: [GridWarpPoint] = points
        next[row * columns + column] = clamped
        let candidate = GridWarp(unchecked: columns, rows, next)
        let v: GridWarpValidity = candidate.validity
        return v == .valid ? .applied(candidate) : .refused(v)
    }

    public func nudging(row: Int, column: Int, dx: Double, dy: Double) -> GridWarpEdit {
        guard row >= 0, row < rows, column >= 0, column < columns else { return .refused(.badSize) }
        let p: GridWarpPoint = point(row: row, column: column)
        return moving(row: row, column: column, to: GridWarpPoint(x: p.x + dx, y: p.y + dy))
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return value }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// This surface sampled at a grid of the new size when that mesh is valid, else the identity of that size.
    public func resampled(columns newColumns: Int, rows newRows: Int) -> GridWarp {
        if newColumns == columns, newRows == rows { return self }
        let fallback: GridWarp = .identity(columns: newColumns, rows: newRows)
        guard isValid, !isIdentity, fallback.columns == newColumns, fallback.rows == newRows else { return fallback }
        var next: [GridWarpPoint] = []
        for r in 0..<newRows {
            for c in 0..<newColumns {
                next.append(map(u: Double(c) / Double(newColumns - 1), v: Double(r) / Double(newRows - 1)))
            }
        }
        return GridWarp(columns: newColumns, rows: newRows, points: next) ?? fallback
    }

    // MARK: - Stored value (research OUT-008-D8)

    /// "CxR:x,y;x,y;…" row by row, six decimals.
    public var stored: String {
        let body: String = points.map { (p: GridWarpPoint) -> String in Self.format(p.x) + "," + Self.format(p.y) }
            .joined(separator: ";")
        return String(columns) + "x" + String(rows) + ":" + body
    }

    /// Nil for a malformed or invalid value.
    public init?(stored: String) {
        let halves: [Substring] = stored.split(separator: ":", omittingEmptySubsequences: false)
        guard halves.count == 2 else { return nil }
        let size: [Substring] = halves[0].split(separator: "x", omittingEmptySubsequences: false)
        guard size.count == 2, let c = Int(String(size[0])), let r = Int(String(size[1])),
              Self.sizeRange.contains(c), Self.sizeRange.contains(r) else { return nil }
        let parts: [Substring] = halves[1].split(separator: ";", omittingEmptySubsequences: false)
        guard parts.count == c * r else { return nil }
        var values: [GridWarpPoint] = []
        for part in parts {
            let fields: [Substring] = part.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count == 2, let x = Double(String(fields[0])), let y = Double(String(fields[1])),
                  x.isFinite, y.isFinite else { return nil }
            values.append(GridWarpPoint(x: x, y: y))
        }
        self.init(columns: c, rows: r, points: values)
    }

    private static func format(_ value: Double) -> String {
        let scaled: Double = (value * 1_000_000).rounded() / 1_000_000
        if scaled == scaled.rounded() { return String(Int(scaled)) }
        return String(scaled)
    }
}
