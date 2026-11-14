// LayerMask.swift — shape masks per layer: ellipse, rounded rectangle and polygon, with a feathered
// edge, an invert flag and the mask's own transform (CMP-007-R1 to R5, R8, R13; research CMP-007-D1,
// D4, D6; specs/104-cmp-007-shape-masks/contracts/shape-masks.md).
//
// CPU only (builds on Linux). A shape lives in a local unit box (−0.5…0.5 on each axis). The mask
// transform places the box on the layer's picture (W × H pixels, shorter side S = min(W, H)):
// centre in layer fractions, scale per axis in units of S, rotation in radians clockwise on screen
// (y down), as CMP-005. Because both axes use S and the rotation is rigid in pixels, an ellipse with
// equal scales is a circle on any aspect. A layer pixel centre p maps to the local frame by
// q = R(−θ)(p − c), in pixels. The signed distance d (negative inside) is measured in pixels:
//
//     ellipse    k0·(k0 − 1)/k1, k0 = |q/h|, k1 = |q/h²|   (exact for circles; sign always exact)
//     rectangle  |max(a, 0)| + min(max(ax, ay), 0) − r, a = |q| − h + r
//     polygon    ± minimum edge distance, sign by the even-odd crossing rule
//
// Coverage over the band w = feather·S + 1 px: t = clamp((w/2 − d)/w, 0, 1), c = t²(3 − 2t); an
// inverted mask gives 1 − c. d ≥ w/2 gives exactly 0 and d ≤ −w/2 exactly 1, so the compositor's
// product (premultiplied colour and alpha × coverage) is exactly transparent outside and exactly the
// unmasked layer inside. `CompositorShaders` evaluates the same steps from the same numbers.
//
// Every intermediate is a named, typed value: long mixed expressions time out the type checker on
// Linux and Xcode 26 (research CMP-007-D6).
import Foundation

/// The three mask shapes, in the mask's local unit box (−0.5…0.5).
public enum LayerMaskShape: Sendable, Equatable {
    /// Fills the box; equal mask scales give a circle.
    case ellipse
    /// Fills the box; `cornerRadius` is a fraction of the rectangle's shorter side (0…0.5).
    case rectangle(cornerRadius: Double)
    /// 3…32 points in the local frame (the box is a reference, not a limit); even-odd fill.
    case polygon([LayerPoint])

    /// The saved names (SCN-001 `composite.mask.shape`).
    public static let kindNames: Set<String> = ["ellipse", "rectangle", "polygon"]

    public var kindName: String {
        switch self {
        case .ellipse: "ellipse"
        case .rectangle: "rectangle"
        case .polygon: "polygon"
        }
    }
}

/// Why a mask was refused (nothing stored).
public enum LayerMaskError: Error, Equatable, Sendable {
    case tooFewPoints(Int)
    case tooManyPoints(Int)
    case zeroArea
    case nonFinitePoint
}

/// Where the mask's box sits on the layer.
public struct LayerMaskTransform: Sendable, Equatable {
    /// Centre components are clamped to this range (layer fractions).
    public static let centerRange: ClosedRange<Double> = -10...10
    /// Scale components are clamped to this range (units of the layer's shorter side).
    public static let scaleRange: ClosedRange<Double> = 0.01...20

    /// Layer fractions; (0.5, 0.5) is the layer's centre.
    public let center: LayerPoint
    /// Size of the box per axis, in units of the layer's shorter side.
    public let scale: LayerPoint
    /// Radians; positive turns clockwise on screen. Any finite value, kept as given.
    public let rotation: Double

    /// Clamps every component; non-finite values read the default (centre (0.5, 0.5), scale 1,
    /// rotation 0); −0 is stored as 0.
    public init(center: LayerPoint = LayerPoint(x: 0.5, y: 0.5), scale: LayerPoint = LayerPoint(x: 1, y: 1),
                rotation: Double = 0) {
        self.center = LayerPoint(x: Self.clamp(center.x, Self.centerRange, 0.5), y: Self.clamp(center.y, Self.centerRange, 0.5))
        self.scale = LayerPoint(x: Self.clamp(scale.x, Self.scaleRange, 1), y: Self.clamp(scale.y, Self.scaleRange, 1))
        let r: Double = rotation.isFinite ? rotation : 0
        self.rotation = r == 0 ? 0 : r
    }

    public static let identity = LayerMaskTransform()

    static func clamp(_ v: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
        guard v.isFinite else { return fallback }
        let c: Double = min(max(v, range.lowerBound), range.upperBound)
        return c == 0 ? 0 : c
    }
}

/// A layer's shape mask (CMP-007). nil in `LayerCompositeSettings.mask` means unmasked.
public struct LayerMask: Sendable, Equatable {
    /// The polygon point cap (CMP-007-R8; research D4): one fixed shader block.
    public static let maximumPolygonPoints = 32
    /// Polygon coordinates are clamped to this range (local units).
    public static let pointRange: ClosedRange<Double> = -10...10
    /// Corner radius range (fraction of the rectangle's shorter side).
    public static let cornerRadiusRange: ClosedRange<Double> = 0...0.5
    /// Feather range (fraction of the layer's shorter side).
    public static let featherRange: ClosedRange<Double> = 0...1
    /// Polygons with |area| at or below this (local units²) are refused as degenerate.
    public static let minimumPolygonArea = 1e-12

    public let shape: LayerMaskShape
    public let transform: LayerMaskTransform
    /// Width of the soft edge, a fraction of the layer's shorter side; one pixel of anti-aliasing is
    /// always added.
    public let feather: Double
    /// Shows the outside of the shape instead of the inside.
    public let inverted: Bool

    /// Clamps the corner radius, polygon coordinates and feather (non-finite radius and feather read
    /// 0); refuses a polygon with fewer than 3 or more than 32 points, a non-finite point or zero area.
    public init(shape: LayerMaskShape, transform: LayerMaskTransform = .identity, feather: Double = 0,
                inverted: Bool = false) throws(LayerMaskError) {
        switch shape {
        case .ellipse:
            self.shape = .ellipse
        case let .rectangle(cornerRadius):
            self.shape = .rectangle(cornerRadius: LayerMaskTransform.clamp(cornerRadius, Self.cornerRadiusRange, 0))
        case let .polygon(points):
            guard points.count >= 3 else { throw .tooFewPoints(points.count) }
            guard points.count <= Self.maximumPolygonPoints else { throw .tooManyPoints(points.count) }
            guard points.allSatisfy({ (p: LayerPoint) -> Bool in p.x.isFinite && p.y.isFinite }) else { throw .nonFinitePoint }
            let clamped: [LayerPoint] = points.map { (p: LayerPoint) -> LayerPoint in
                LayerPoint(x: LayerMaskTransform.clamp(p.x, Self.pointRange, 0), y: LayerMaskTransform.clamp(p.y, Self.pointRange, 0))
            }
            guard abs(Self.shoelaceArea(clamped)) > Self.minimumPolygonArea else { throw .zeroArea }
            self.shape = .polygon(clamped)
        }
        self.transform = transform
        self.feather = LayerMaskTransform.clamp(feather, Self.featherRange, 0)
        self.inverted = inverted
    }

    /// Signed area (local units²) of a closed polygon.
    public static func shoelaceArea(_ points: [LayerPoint]) -> Double {
        var twice: Double = 0
        for i in points.indices {
            let a: LayerPoint = points[i]
            let b: LayerPoint = points[(i + 1) % points.count]
            let term: Double = a.x * b.y - b.x * a.y
            twice += term
        }
        return twice / 2
    }

    /// The mask resolved for a picture of `width` × `height` pixels (sizes below 1 read 1).
    public func geometry(width: Int, height: Int) -> LayerMaskGeometry {
        LayerMaskGeometry(mask: self, width: width, height: height)
    }
}

/// A mask resolved in pixels for one picture size: the CPU reference of the shader (CMP-007-R5) and
/// the numbers the compositor hands to it.
public struct LayerMaskGeometry: Sendable, Equatable {
    /// 1 ellipse, 2 rectangle, 3 polygon (the shader's kind; 0 is "no mask").
    public let kind: Int
    /// Inverse placement, layer pixel → local pixels: q = (cos·dx + sin·dy, −sin·dx + cos·dy),
    /// d = p − centre.
    public let cosine: Double
    public let sine: Double
    public let centerX: Double
    public let centerY: Double
    /// Half extents of the box in pixels.
    public let halfWidth: Double
    public let halfHeight: Double
    /// Rectangle corner radius in pixels (0 otherwise).
    public let cornerRadius: Double
    /// Polygon vertices in local pixels (empty otherwise).
    public let points: [LayerPoint]
    /// Edge band width in pixels: feather·S + 1.
    public let band: Double
    public let inverted: Bool

    init(mask: LayerMask, width: Int, height: Int) {
        let w: Double = Double(max(width, 1))
        let h: Double = Double(max(height, 1))
        let s: Double = min(w, h)
        let t: LayerMaskTransform = mask.transform
        cosine = cos(t.rotation)
        sine = sin(t.rotation)
        centerX = t.center.x * w
        centerY = t.center.y * h
        let hw: Double = 0.5 * t.scale.x * s
        let hh: Double = 0.5 * t.scale.y * s
        halfWidth = hw
        halfHeight = hh
        let featherPixels: Double = mask.feather * s
        band = featherPixels + 1
        inverted = mask.inverted
        switch mask.shape {
        case .ellipse:
            kind = 1
            cornerRadius = 0
            points = []
        case let .rectangle(radius):
            kind = 2
            let shorter: Double = 2 * min(hw, hh)
            cornerRadius = radius * shorter
            points = []
        case let .polygon(local):
            kind = 3
            cornerRadius = 0
            let sx: Double = t.scale.x * s
            let sy: Double = t.scale.y * s
            points = local.map { (p: LayerPoint) -> LayerPoint in LayerPoint(x: p.x * sx, y: p.y * sy) }
        }
    }

    /// Layer pixel → the mask's local frame, in pixels.
    public func local(x: Double, y: Double) -> LayerPoint {
        let dx: Double = x - centerX
        let dy: Double = y - centerY
        let qx: Double = cosine * dx + sine * dy
        let qy: Double = cosine * dy - sine * dx
        return LayerPoint(x: qx, y: qy)
    }

    /// Signed distance in pixels from the layer point (`x`, `y`) (pixel centre = index + 0.5) to the
    /// shape's edge; negative inside.
    public func signedDistance(x: Double, y: Double) -> Double {
        let q: LayerPoint = local(x: x, y: y)
        switch kind {
        case 1: return Self.ellipseDistance(q, halfWidth, halfHeight)
        case 2: return Self.roundedBoxDistance(q, halfWidth, halfHeight, cornerRadius)
        default: return Self.polygonDistance(q, points)
        }
    }

    /// Coverage 0…1 at the layer point (`x`, `y`): exactly 0 beyond the band, exactly 1 inside it
    /// (swapped when inverted).
    public func coverage(x: Double, y: Double) -> Double {
        Self.coverage(distance: signedDistance(x: x, y: y), band: band, inverted: inverted)
    }

    public static func coverage(distance d: Double, band w: Double, inverted: Bool) -> Double {
        let half: Double = 0.5 * w
        let raw: Double = (half - d) / w
        let t: Double = min(max(raw, 0), 1)
        let smooth: Double = t * t * (3 - 2 * t)
        return inverted ? 1 - smooth : smooth
    }

    static func ellipseDistance(_ q: LayerPoint, _ rx: Double, _ ry: Double) -> Double {
        let ux: Double = q.x / rx
        let uy: Double = q.y / ry
        let vx: Double = ux / rx
        let vy: Double = uy / ry
        let k0: Double = (ux * ux + uy * uy).squareRoot()
        let k1: Double = (vx * vx + vy * vy).squareRoot()
        guard k1 > 0 else { return -min(rx, ry) }
        let numerator: Double = k0 * (k0 - 1)
        return numerator / k1
    }

    static func roundedBoxDistance(_ q: LayerPoint, _ hx: Double, _ hy: Double, _ r: Double) -> Double {
        let ax: Double = abs(q.x) - hx + r
        let ay: Double = abs(q.y) - hy + r
        let ox: Double = max(ax, 0)
        let oy: Double = max(ay, 0)
        let outside: Double = (ox * ox + oy * oy).squareRoot()
        let inside: Double = min(max(ax, ay), 0)
        return outside + inside - r
    }

    static func polygonDistance(_ q: LayerPoint, _ v: [LayerPoint]) -> Double {
        guard let first = v.first else { return .greatestFiniteMagnitude }
        let fx: Double = q.x - first.x
        let fy: Double = q.y - first.y
        var best: Double = fx * fx + fy * fy
        var sign: Double = 1
        var j: Int = v.count - 1
        for i in v.indices {
            let vi: LayerPoint = v[i]
            let vj: LayerPoint = v[j]
            let ex: Double = vj.x - vi.x
            let ey: Double = vj.y - vi.y
            let wx: Double = q.x - vi.x
            let wy: Double = q.y - vi.y
            let ee: Double = ex * ex + ey * ey
            let we: Double = wx * ex + wy * ey
            let along: Double = ee > 0 ? min(max(we / ee, 0), 1) : 0
            let bx: Double = wx - ex * along
            let by: Double = wy - ey * along
            let bb: Double = bx * bx + by * by
            best = min(best, bb)
            let c1: Bool = q.y >= vi.y
            let c2: Bool = q.y < vj.y
            let lhs: Double = ex * wy
            let rhs: Double = ey * wx
            let c3: Bool = lhs > rhs
            if (c1 && c2 && c3) || (!c1 && !c2 && !c3) { sign = -sign }
            j = i
        }
        return sign * best.squareRoot()
    }
}
