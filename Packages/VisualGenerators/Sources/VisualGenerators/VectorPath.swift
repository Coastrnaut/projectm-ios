// VectorPath.swift — a closed, simple polygon in the unit square, valid by construction (SHD-008-R1, R2, R7;
// specs/279-shd-008-vector-path-editor, contracts/vector-path.md P1, P4; research SHD-008-D2 to D4).
//
// 3…32 points, each coordinate in 0…1 (y down, as on screen), implicitly closed (the last point joins the first).
// `validate` checks, in order: the count, the range, duplicate consecutive points (≤ 1e-6 apart, wrapping),
// self-intersection (two non-adjacent edges that cross or touch, or two adjacent edges that overlap collinearly: a
// spike that doubles back) and the area (|area| ≤ 1e-4 is too small; a symmetric bow-tie has area 0, so crossing is
// checked first and reported). For every path that passes, even-odd and
// non-zero fill agree. The path is triangulated once (ear clipping) when it is made, so `sample` picks a uniform
// point inside with three numbers and no allocation (Constitution VII). Numbers only: nothing here is executable
// (SHD-011). Pure Swift (every platform). Every intermediate is a named, typed value (Xcode 26 type-check budget).

/// One path point in the unit square (y down).
public struct VectorPoint: Sendable, Hashable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Why a list of points is not a valid path (the first rule that fails, contract P1).
public enum VectorPathIssue: Error, Sendable, Equatable {
    case tooFewPoints(Int)
    case tooManyPoints(Int)
    /// The point at this index is non-finite or outside 0…1.
    case outOfRange(Int)
    /// The point at this index equals the next one (the last point's next is the first).
    case duplicatePoint(Int)
    case tooSmall
    /// Edges `first` and `second` (edge i joins point i to point i + 1) cross, touch or overlap.
    case crossesItself(Int, Int)

    /// The editor's inline text.
    public var message: String {
        switch self {
        case .tooFewPoints: "A path needs at least \(VectorPath.minimumPoints) points."
        case .tooManyPoints: "A path can have at most \(VectorPath.maximumPoints) points."
        case let .outOfRange(i): "Point \(i + 1) is outside the frame."
        case let .duplicatePoint(i): "Point \(i + 1) repeats the next point."
        case .tooSmall: "The path is too small."
        case .crossesItself: "The path crosses itself."
        }
    }
}

public struct VectorPath: Sendable, Hashable, Codable {
    public static let minimumPoints = 3
    /// CMP-007's polygon cap (one fixed shader block), so a path mask needs no shader change.
    public static let maximumPoints = 32
    /// Absolute area (unit square²) at or below this is refused.
    public static let minimumArea = 1e-4
    /// Consecutive points this close or closer are duplicates.
    public static let duplicateDistance = 1e-6
    /// Cross products this small or smaller count as collinear.
    public static let collinearTolerance = 1e-12

    /// The default: a diamond touching the middle of each side.
    public static let `default`: VectorPath = {
        let corners: [VectorPoint] = [VectorPoint(x: 0.5, y: 0), VectorPoint(x: 1, y: 0.5),
                                      VectorPoint(x: 0.5, y: 1), VectorPoint(x: 0, y: 0.5)]
        // swiftlint:disable:next force_try
        return try! VectorPath(corners)
    }()

    public let points: [VectorPoint]
    /// Flat index triples of the triangulation.
    private let triangles: [Int]
    /// Running sum of the triangles' areas (the last is the polygon's area).
    private let cumulativeAreas: [Double]

    public init(_ points: [VectorPoint]) throws(VectorPathIssue) {
        if let issue = Self.validate(points) { throw issue }
        self.points = points
        let made: [Int] = Self.triangulate(points)
        triangles = made
        var running: Double = 0
        var sums: [Double] = []
        sums.reserveCapacity(made.count / 3)
        var k = 0
        while k + 2 < made.count {
            let a: VectorPoint = points[made[k]]
            let b: VectorPoint = points[made[k + 1]]
            let c: VectorPoint = points[made[k + 2]]
            running += abs(Self.cross(a, b, c)) / 2
            sums.append(running)
            k += 3
        }
        cumulativeAreas = sums
    }

    public static func == (lhs: VectorPath, rhs: VectorPath) -> Bool { lhs.points == rhs.points }
    public func hash(into hasher: inout Hasher) { hasher.combine(points) }

    /// Signed shoelace area (positive when the points turn clockwise on screen, y down).
    public var area: Double { Self.signedArea(points) }

    /// Number of triangles in the triangulation (n − 2 for a valid path).
    public var triangleCount: Int { triangles.count / 3 }

    // MARK: - Validation (contract P1)

    /// nil when `points` form a valid path; otherwise the first rule that fails.
    public static func validate(_ points: [VectorPoint]) -> VectorPathIssue? {
        let n: Int = points.count
        if n < minimumPoints { return .tooFewPoints(n) }
        if n > maximumPoints { return .tooManyPoints(n) }
        for i in 0..<n {
            let p: VectorPoint = points[i]
            let inX: Bool = p.x.isFinite && p.x >= 0 && p.x <= 1
            let inY: Bool = p.y.isFinite && p.y >= 0 && p.y <= 1
            if !(inX && inY) { return .outOfRange(i) }
        }
        for i in 0..<n {
            let a: VectorPoint = points[i]
            let b: VectorPoint = points[(i + 1) % n]
            let dx: Double = b.x - a.x
            let dy: Double = b.y - a.y
            let distance: Double = (dx * dx + dy * dy).squareRoot()
            if distance <= duplicateDistance { return .duplicatePoint(i) }
        }
        if let pair = firstIntersection(points) { return .crossesItself(pair.0, pair.1) }
        if abs(signedArea(points)) <= minimumArea { return .tooSmall }
        return nil
    }

    static func signedArea(_ points: [VectorPoint]) -> Double {
        var twice: Double = 0
        for i in points.indices {
            let a: VectorPoint = points[i]
            let b: VectorPoint = points[(i + 1) % points.count]
            let term: Double = a.x * b.y - b.x * a.y
            twice += term
        }
        return twice / 2
    }

    /// (b − a) × (c − a).
    static func cross(_ a: VectorPoint, _ b: VectorPoint, _ c: VectorPoint) -> Double {
        let abx: Double = b.x - a.x
        let aby: Double = b.y - a.y
        let acx: Double = c.x - a.x
        let acy: Double = c.y - a.y
        return abx * acy - aby * acx
    }

    /// −1, 0 or 1, with |cross| ≤ the tolerance as 0 (collinear).
    static func orientation(_ a: VectorPoint, _ b: VectorPoint, _ c: VectorPoint) -> Int {
        let value: Double = cross(a, b, c)
        if abs(value) <= collinearTolerance { return 0 }
        return value > 0 ? 1 : -1
    }

    /// `c` lies within the bounding box of segment ab (used once a, b, c are known to be collinear).
    static func withinBox(_ a: VectorPoint, _ b: VectorPoint, _ c: VectorPoint) -> Bool {
        let t: Double = collinearTolerance
        let inX: Bool = c.x >= min(a.x, b.x) - t && c.x <= max(a.x, b.x) + t
        let inY: Bool = c.y >= min(a.y, b.y) - t && c.y <= max(a.y, b.y) + t
        return inX && inY
    }

    /// Segments ab and cd cross or touch (a shared point counts).
    static func segmentsMeet(_ a: VectorPoint, _ b: VectorPoint, _ c: VectorPoint, _ d: VectorPoint) -> Bool {
        let o1: Int = orientation(a, b, c)
        let o2: Int = orientation(a, b, d)
        let o3: Int = orientation(c, d, a)
        let o4: Int = orientation(c, d, b)
        if o1 * o2 < 0 && o3 * o4 < 0 { return true }
        if o1 == 0 && withinBox(a, b, c) { return true }
        if o2 == 0 && withinBox(a, b, d) { return true }
        if o3 == 0 && withinBox(c, d, a) { return true }
        if o4 == 0 && withinBox(c, d, b) { return true }
        return false
    }

    /// Adjacent edges (from → shared) and (shared → to) overlap: collinear and doubling back.
    static func adjacentOverlap(_ from: VectorPoint, _ shared: VectorPoint, _ to: VectorPoint) -> Bool {
        guard orientation(from, shared, to) == 0 else { return false }
        let ux: Double = from.x - shared.x
        let uy: Double = from.y - shared.y
        let vx: Double = to.x - shared.x
        let vy: Double = to.y - shared.y
        let dot: Double = ux * vx + uy * vy
        return dot > 0
    }

    /// The first pair of edges (i < j) that breaks simplicity, or nil.
    static func firstIntersection(_ p: [VectorPoint]) -> (Int, Int)? {
        let n: Int = p.count
        for i in 0..<n {
            for j in (i + 1)..<n {
                let a: VectorPoint = p[i]
                let b: VectorPoint = p[(i + 1) % n]
                let c: VectorPoint = p[j]
                let d: VectorPoint = p[(j + 1) % n]
                let follows: Bool = j == i + 1
                let wraps: Bool = i == 0 && j == n - 1
                if follows {
                    if adjacentOverlap(a, b, d) { return (i, j) }
                } else if wraps {
                    if adjacentOverlap(c, a, b) { return (i, j) }
                } else if segmentsMeet(a, b, c, d) {
                    return (i, j)
                }
            }
        }
        return nil
    }

    // MARK: - Inside test and sampling (contract P4)

    /// Even-odd inside test (points exactly on an edge may read either way).
    public func contains(_ q: VectorPoint) -> Bool {
        var inside = false
        var j: Int = points.count - 1
        for i in points.indices {
            let pi: VectorPoint = points[i]
            let pj: VectorPoint = points[j]
            let straddles: Bool = (pi.y > q.y) != (pj.y > q.y)
            if straddles {
                let t: Double = (q.y - pi.y) / (pj.y - pi.y)
                let xCross: Double = pi.x + t * (pj.x - pi.x)
                if q.x < xCross { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// A point uniformly distributed inside the path for uniform r1, r2, r3 in 0…1: r1 picks a triangle by area,
    /// r2 and r3 a point in it (reflected when r2 + r3 > 1). No allocation.
    public func sample(_ r1: Double, _ r2: Double, _ r3: Double) -> VectorPoint {
        let total: Double = cumulativeAreas.last ?? 0
        let target: Double = min(max(r1, 0), 1) * total
        var k = 0
        while k < cumulativeAreas.count - 1 && cumulativeAreas[k] <= target { k += 1 }
        var u: Double = min(max(r2, 0), 1)
        var v: Double = min(max(r3, 0), 1)
        if u + v > 1 {
            u = 1 - u
            v = 1 - v
        }
        let a: VectorPoint = points[triangles[3 * k]]
        let b: VectorPoint = points[triangles[3 * k + 1]]
        let c: VectorPoint = points[triangles[3 * k + 2]]
        let x: Double = a.x + u * (b.x - a.x) + v * (c.x - a.x)
        let y: Double = a.y + u * (b.y - a.y) + v * (c.y - a.y)
        return VectorPoint(x: x, y: y)
    }

    /// Ear clipping of a simple polygon: n − 2 triangles as flat index triples.
    static func triangulate(_ p: [VectorPoint]) -> [Int] {
        let orientationSign: Double = signedArea(p) > 0 ? 1 : -1
        var remaining: [Int] = Array(p.indices)
        var result: [Int] = []
        result.reserveCapacity(3 * (p.count - 2))
        var guardCount: Int = 0
        while remaining.count > 3 && guardCount < 4 * p.count * p.count {
            guardCount += 1
            let m: Int = remaining.count
            var clipped = false
            for k in 0..<m {
                let ia: Int = remaining[(k + m - 1) % m]
                let ib: Int = remaining[k]
                let ic: Int = remaining[(k + 1) % m]
                if isEar(p, remaining, ia, ib, ic, orientationSign) {
                    result.append(contentsOf: [ia, ib, ic])
                    remaining.remove(at: k)
                    clipped = true
                    break
                }
            }
            if !clipped {   // numerically stuck (not expected for a valid path): fan the rest
                for k in 1..<(remaining.count - 1) { result.append(contentsOf: [remaining[0], remaining[k], remaining[k + 1]]) }
                return result
            }
        }
        if remaining.count == 3 { result.append(contentsOf: remaining) }
        return result
    }

    private static func isEar(_ p: [VectorPoint], _ remaining: [Int], _ ia: Int, _ ib: Int, _ ic: Int,
                              _ sign: Double) -> Bool {
        let a: VectorPoint = p[ia]
        let b: VectorPoint = p[ib]
        let c: VectorPoint = p[ic]
        let turn: Double = cross(a, b, c) * sign
        guard turn > collinearTolerance else { return false }
        for index in remaining where index != ia && index != ib && index != ic {
            let q: VectorPoint = p[index]
            let s1: Double = cross(a, b, q) * sign
            let s2: Double = cross(b, c, q) * sign
            let s3: Double = cross(c, a, q) * sign
            if s1 >= 0 && s2 >= 0 && s3 >= 0 { return false }
        }
        return true
    }

    // MARK: - Coding: {"points": [{"x", "y"}…]}; an invalid list fails to decode (the caller decides)

    private enum CodingKeys: String, CodingKey { case points }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let list: [VectorPoint] = try c.decode([VectorPoint].self, forKey: .points)
        do {
            try self.init(list)
        } catch {
            throw DecodingError.dataCorruptedError(forKey: .points, in: c, debugDescription: error.message)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(points, forKey: .points)
    }
}
