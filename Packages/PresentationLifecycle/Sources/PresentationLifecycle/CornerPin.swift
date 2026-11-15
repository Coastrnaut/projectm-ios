// CornerPin.swift — OUT-007 (spec specs/264-out-007-corner-pin, contract C1; research OUT-007-D2, D3, D6):
// the external output's corner pin and its projective mapping. Pure Swift, no UIKit.
//
// * A pin is four target points in output-relative coordinates (0…1 across and down the display, y down),
//   in the unit square's order: top-left (0,0), top-right (1,0), bottom-right (1,1), bottom-left (0,1).
//   The default is the identity.
// * A pin is valid (no foldover) only when every corner lies in −0.5…1.5, every turn between consecutive
//   edges is positive (the unit square's orientation: strictly convex, same winding, not mirrored, not
//   self-intersecting), every turn's sine is at least 0.035 (≈ 2°: no three corners nearly collinear) and
//   the area is at least 5 % of the output. For such a quad the mapping's denominator is positive on the
//   whole square, so its Jacobian determinant is positive everywhere: orientation is preserved.
// * Edits clamp the moved corner to the range; an invalid result is refused (the pin stays as it was).
// * `Homography` is Heckbert's closed-form square-to-quad mapping (8 parameters, i = 1) and can express
//   itself as a Core Animation 4 × 4 matrix (row-vector order) for a layer of a given size and anchor.

/// A corner pin target point in output-relative coordinates.
public struct CornerPinPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct CornerPin: Equatable, Sendable {
    public enum Corner: String, CaseIterable, Sendable {
        case topLeft, topRight, bottomRight, bottomLeft

        public var index: Int {
            switch self {
            case .topLeft: 0
            case .topRight: 1
            case .bottomRight: 2
            case .bottomLeft: 3
            }
        }
    }

    public enum Validity: Equatable, Sendable {
        case valid, outOfRange, notConvex, collinear, tooSmall
    }

    /// Top-left, top-right, bottom-right, bottom-left.
    public private(set) var corners: [CornerPinPoint]

    public static let range: ClosedRange<Double> = -0.5...1.5
    public static let minimumArea = 0.05
    public static let minimumTurnSine = 0.035
    public static let nudgeStep = 0.005

    public static let identity = CornerPin(unchecked: [CornerPinPoint(x: 0, y: 0), CornerPinPoint(x: 1, y: 0),
                                                       CornerPinPoint(x: 1, y: 1), CornerPinPoint(x: 0, y: 1)])

    private init(unchecked corners: [CornerPinPoint]) {
        self.corners = corners
    }

    /// Nil unless the four points form a valid pin.
    public init?(topLeft: CornerPinPoint, topRight: CornerPinPoint, bottomRight: CornerPinPoint, bottomLeft: CornerPinPoint) {
        let candidate = CornerPin(unchecked: [topLeft, topRight, bottomRight, bottomLeft])
        guard candidate.isValid else { return nil }
        self = candidate
    }

    /// Any four points, valid or not (tests of the rules).
    public static func candidate(_ points: [CornerPinPoint]) -> CornerPin {
        precondition(points.count == 4, "a corner pin has four corners")
        return CornerPin(unchecked: points)
    }

    public func point(_ corner: Corner) -> CornerPinPoint { corners[corner.index] }

    public var isIdentity: Bool { self == .identity }
    public var isValid: Bool { validity == .valid }

    public var validity: Validity {
        for p in corners where !Self.range.contains(p.x) || !Self.range.contains(p.y) { return .outOfRange }
        var collinear = false
        for i in 0..<4 {
            let a: CornerPinPoint = corners[i], b: CornerPinPoint = corners[(i + 1) % 4], c: CornerPinPoint = corners[(i + 2) % 4]
            let e1x: Double = b.x - a.x, e1y: Double = b.y - a.y
            let e2x: Double = c.x - b.x, e2y: Double = c.y - b.y
            let cross: Double = e1x * e2y - e1y * e2x
            let lengths: Double = (e1x * e1x + e1y * e1y).squareRoot() * (e2x * e2x + e2y * e2y).squareRoot()
            if lengths == 0 { return .collinear }   // two corners coincide
            let sine: Double = cross / lengths
            if sine <= -Self.minimumTurnSine { return .notConvex }
            if sine < Self.minimumTurnSine { collinear = true }
        }
        if collinear { return .collinear }
        return area < Self.minimumArea ? .tooSmall : .valid
    }

    /// The shoelace area (positive for the unit square's orientation, y down).
    public var area: Double {
        var sum = 0.0
        for i in 0..<4 {
            let a: CornerPinPoint = corners[i], b: CornerPinPoint = corners[(i + 1) % 4]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    /// `corner` moved to `point` (clamped to the range); `self` when the result would be invalid.
    public func moving(_ corner: Corner, to point: CornerPinPoint) -> CornerPin {
        let clamped = CornerPinPoint(x: min(max(point.x, Self.range.lowerBound), Self.range.upperBound),
                                     y: min(max(point.y, Self.range.lowerBound), Self.range.upperBound))
        var next: [CornerPinPoint] = corners
        next[corner.index] = clamped
        let candidate = CornerPin(unchecked: next)
        return candidate.isValid ? candidate : self
    }

    /// `corner` moved by (`dx`, `dy`); see `moving(_:to:)`.
    public func nudging(_ corner: Corner, dx: Double, dy: Double) -> CornerPin {
        let p: CornerPinPoint = point(corner)
        return moving(corner, to: CornerPinPoint(x: p.x + dx, y: p.y + dy))
    }

    // MARK: - Mapping

    public var homography: Homography { Homography(quad: corners) }

    // MARK: - Stored value (research OUT-007-D6)

    /// "x,y;x,y;x,y;x,y" (TL;TR;BR;BL), six decimals.
    public var stored: String {
        corners.map { (p: CornerPinPoint) -> String in Self.format(p.x) + "," + Self.format(p.y) }.joined(separator: ";")
    }

    /// Nil for a malformed or invalid value.
    public init?(stored: String) {
        let parts: [Substring] = stored.split(separator: ";", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var points: [CornerPinPoint] = []
        for part in parts {
            let fields: [Substring] = part.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count == 2, let x = Double(String(fields[0])), let y = Double(String(fields[1])),
                  x.isFinite, y.isFinite else { return nil }
            points.append(CornerPinPoint(x: x, y: y))
        }
        let candidate = CornerPin(unchecked: points)
        guard candidate.isValid else { return nil }
        self = candidate
    }

    private static func format(_ value: Double) -> String {
        let scaled: Double = (value * 1_000_000).rounded() / 1_000_000
        if scaled == scaled.rounded() { return String(Int(scaled)) }
        return String(scaled)
    }
}

/// The projective mapping from the unit square to a quad:
/// x' = (a·u + b·v + c) / (g·u + h·v + 1), y' = (d·u + e·v + f) / (g·u + h·v + 1).
public struct Homography: Equatable, Sendable {
    public var a, b, c, d, e, f, g, h: Double

    /// Heckbert's closed form for corners (0,0), (1,0), (1,1), (0,1) → `quad[0…3]`.
    public init(quad: [CornerPinPoint]) {
        precondition(quad.count == 4, "four corners")
        let x0: Double = quad[0].x, y0: Double = quad[0].y, x1: Double = quad[1].x, y1: Double = quad[1].y
        let x2: Double = quad[2].x, y2: Double = quad[2].y, x3: Double = quad[3].x, y3: Double = quad[3].y
        let sx: Double = x0 - x1 + x2 - x3
        let sy: Double = y0 - y1 + y2 - y3
        if sx == 0, sy == 0 {   // a parallelogram: affine
            a = x1 - x0; b = x3 - x0; c = x0
            d = y1 - y0; e = y3 - y0; f = y0
            g = 0; h = 0
            return
        }
        let dx1: Double = x1 - x2, dx2: Double = x3 - x2
        let dy1: Double = y1 - y2, dy2: Double = y3 - y2
        let det: Double = dx1 * dy2 - dx2 * dy1
        g = (sx * dy2 - dx2 * sy) / det
        h = (dx1 * sy - sx * dy1) / det
        a = x1 - x0 + g * x1; b = x3 - x0 + h * x3; c = x0
        d = y1 - y0 + g * y1; e = y3 - y0 + h * y3; f = y0
    }

    public static let identity = Homography(quad: CornerPin.identity.corners)

    public func map(x u: Double, y v: Double) -> CornerPinPoint {
        let w: Double = g * u + h * v + 1
        return CornerPinPoint(x: (a * u + b * v + c) / w, y: (d * u + e * v + f) / w)
    }

    /// det ∂(x', y')/∂(u, v) at (u, v); positive where orientation is preserved.
    public func jacobianDeterminant(x u: Double, y v: Double) -> Double {
        let w: Double = g * u + h * v + 1
        let X: Double = a * u + b * v + c, Y: Double = d * u + e * v + f
        let dxdu: Double = (a * w - X * g) / (w * w), dxdv: Double = (b * w - X * h) / (w * w)
        let dydu: Double = (d * w - Y * g) / (w * w), dydv: Double = (e * w - Y * h) / (w * w)
        return dxdu * dydv - dxdv * dydu
    }

    /// The mapping for a layer `width` × `height` (points, origin top-left) applied about the anchor
    /// (`anchorX`, `anchorY`) in the layer's coordinates, as Core Animation's 16 values m11, m12, m13, m14,
    /// m21 … m44 (row vectors: [x y z 1] · M). Core Animation applies a sublayer transform about the anchor, so
    /// this is T(+anchor) · S⁻¹ · H · S · T(−anchor) with S scaling points to the unit square; z passes through.
    public func layerMatrix(width: Double, height: Double, anchorX: Double, anchorY: Double) -> [Double] {
        guard width > 0, height > 0 else { return Self.identityMatrix }
        // Pixel-space homography P (column form): x' = (p11 x + p12 y + p13) / (p31 x + p32 y + p33).
        let p11: Double = a, p12: Double = b * width / height, p13: Double = c * width
        let p21: Double = d * height / width, p22: Double = e, p23: Double = f * height
        let p31: Double = g / width, p32: Double = h / height, p33: Double = 1
        // Conjugate by the anchor: q = p − anchor; result − anchor.
        let ax: Double = anchorX, ay: Double = anchorY
        // Numerators/denominator in q: x' − ax = (p11(q+a) + …)/(W) − ax.
        let w31: Double = p31, w32: Double = p32, w33: Double = p31 * ax + p32 * ay + p33
        let n11: Double = p11 - ax * p31, n12: Double = p12 - ax * p32
        let n13: Double = p11 * ax + p12 * ay + p13 - ax * w33
        let n21: Double = p21 - ay * p31, n22: Double = p22 - ay * p32
        let n23: Double = p21 * ax + p22 * ay + p23 - ay * w33
        // Row-vector layout: column j of the column form becomes row j.
        return [n11, n21, 0, w31,
                n12, n22, 0, w32,
                0, 0, 1, 0,
                n13, n23, 0, w33]
    }

    public static let identityMatrix: [Double] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]

    /// Projects (`x`, `y`, z = 0) through a 16-value row-vector matrix and adds back the anchor (tests: what
    /// Core Animation draws for a sublayer point at (`x`, `y`) of a layer with that anchor).
    public static func project(_ m: [Double], x: Double, y: Double, anchorX: Double, anchorY: Double) -> CornerPinPoint {
        let qx: Double = x - anchorX, qy: Double = y - anchorY
        let X: Double = qx * m[0] + qy * m[4] + m[12]
        let Y: Double = qx * m[1] + qy * m[5] + m[13]
        let W: Double = qx * m[3] + qy * m[7] + m[15]
        return CornerPinPoint(x: X / W + anchorX, y: Y / W + anchorY)
    }
}
