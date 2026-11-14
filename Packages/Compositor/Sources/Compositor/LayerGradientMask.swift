// LayerGradientMask.swift — linear and radial alpha gradients per layer with 2…8 editable stops
// (CMP-008-R1 to R4, R12; research CMP-008-D1, D2; specs/207-cmp-008-gradient-masks/contracts/gradient-masks.md).
//
// CPU only (builds on Linux). The gradient is evaluated in the layer's own space at the same layer pixel as
// CMP-007's shape mask (pixel centre = index + 0.5, before the CMP-005 transform), and multiplies the shape's
// coverage. W × H picture, shorter side S = min(W, H):
//
//     linear  s = start·(W, H), e = end·(W, H) in pixels;  t = ((p − s)·(e − s)) / |e − s|²
//     radial  c = center·(W, H), r = radius·S in pixels;   t = |p − c| / r
//
// alpha(t): the first stop's alpha at or before its position, the last stop's at or after its position, else
// the linear interpolation of the two neighbouring stops; so alpha is monotonic between adjacent stops.
// Equal positions give a hard step (the later stop wins). `CompositorShaders` runs the same loop from the
// same numbers (`MaskBlock`). Every intermediate is a named, typed value (type-checker budgets).
import Foundation

/// One stop: where along the gradient (0…1) and the alpha there (0…1).
public struct LayerGradientStop: Sendable, Equatable {
    public let position: Double
    public let alpha: Double

    /// Clamps both to 0…1; a non-finite position reads 0 and a non-finite alpha 1; −0 is stored as 0.
    public init(position: Double, alpha: Double) {
        self.position = LayerGradientMask.clamp(position, 0...1, 0)
        self.alpha = LayerGradientMask.clamp(alpha, 0...1, 1)
    }
}

/// The two gradient kinds.
public enum LayerGradientKind: Sendable, Equatable {
    /// From `start` (t = 0) to `end` (t = 1), in layer fractions.
    case linear(start: LayerPoint, end: LayerPoint)
    /// From `center` (t = 0) out to `radius` (t = 1); the centre in layer fractions, the radius in units of the
    /// layer's shorter side, so it stays round on any aspect.
    case radial(center: LayerPoint, radius: Double)

    /// The saved names (SCN-001 `composite.gradientMask.kind`).
    public static let kindNames: Set<String> = ["linear", "radial"]

    public var kindName: String {
        switch self {
        case .linear: "linear"
        case .radial: "radial"
        }
    }
}

/// Why a gradient was refused (nothing stored).
public enum LayerGradientMaskError: Error, Equatable, Sendable {
    case tooFewStops(Int)
    case tooManyStops(Int)
    /// A linear gradient whose start and end are closer than `minimumLength` (layer fractions).
    case zeroLength
}

/// A layer's gradient mask (CMP-008). nil in `LayerCompositeSettings.gradientMask` draws without one.
public struct LayerGradientMask: Sendable, Equatable {
    public static let minimumStops = 2
    /// One fixed 8-stop shader block (research CMP-008-D3).
    public static let maximumStops = 8
    /// Point coordinates are clamped to this range (layer fractions).
    public static let pointRange: ClosedRange<Double> = -10...10
    /// Radial radius range (units of the layer's shorter side).
    public static let radiusRange: ClosedRange<Double> = 0.01...20
    public static let defaultRadius = 0.5
    /// Linear gradients shorter than this (layer fractions) are refused.
    public static let minimumLength = 1e-6

    public let kind: LayerGradientKind
    /// 2…8 stops sorted by position (stable: equal positions keep their order).
    public let stops: [LayerGradientStop]

    /// Clamps the geometry, stable-sorts the stops; refuses fewer than 2 or more than 8 stops and a linear
    /// gradient of zero length.
    public init(kind: LayerGradientKind, stops: [LayerGradientStop]) throws(LayerGradientMaskError) {
        guard stops.count >= Self.minimumStops else { throw .tooFewStops(stops.count) }
        guard stops.count <= Self.maximumStops else { throw .tooManyStops(stops.count) }
        switch kind {
        case let .linear(start, end):
            let s: LayerPoint = Self.clampPoint(start, fallback: LayerPoint(x: 0, y: 0.5))
            let e: LayerPoint = Self.clampPoint(end, fallback: LayerPoint(x: 1, y: 0.5))
            let dx: Double = e.x - s.x
            let dy: Double = e.y - s.y
            let length: Double = (dx * dx + dy * dy).squareRoot()
            guard length >= Self.minimumLength else { throw .zeroLength }
            self.kind = .linear(start: s, end: e)
        case let .radial(center, radius):
            let c: LayerPoint = Self.clampPoint(center, fallback: LayerPoint(x: 0.5, y: 0.5))
            let r: Double = Self.clamp(radius, Self.radiusRange, Self.defaultRadius)
            self.kind = .radial(center: c, radius: r)
        }
        self.stops = Self.sorted(stops)
    }

    /// Stable sort by position.
    public static func sorted(_ stops: [LayerGradientStop]) -> [LayerGradientStop] {
        let indexed: [(offset: Int, element: LayerGradientStop)] = Array(stops.enumerated())
        let ordered = indexed.sorted { (a: (offset: Int, element: LayerGradientStop), b: (offset: Int, element: LayerGradientStop)) -> Bool in
            if a.element.position != b.element.position { return a.element.position < b.element.position }
            return a.offset < b.offset
        }
        return ordered.map { (entry: (offset: Int, element: LayerGradientStop)) -> LayerGradientStop in entry.element }
    }

    /// Left to right across the layer, alpha 1 → 0 (the inspector's Linear default).
    public static let linearDefault: LayerGradientMask = makeDefault(.linear(start: LayerPoint(x: 0, y: 0.5), end: LayerPoint(x: 1, y: 0.5)))
    /// Centred, radius half the shorter side, alpha 1 → 0 (the inspector's Radial default).
    public static let radialDefault: LayerGradientMask = makeDefault(.radial(center: LayerPoint(x: 0.5, y: 0.5), radius: defaultRadius))

    private static func makeDefault(_ kind: LayerGradientKind) -> LayerGradientMask {
        let stops: [LayerGradientStop] = [LayerGradientStop(position: 0, alpha: 1), LayerGradientStop(position: 1, alpha: 0)]
        // Valid by construction: two stops, non-zero length.
        return (try? LayerGradientMask(kind: kind, stops: stops)) ?? LayerGradientMask(unchecked: kind, stops: stops)
    }

    private init(unchecked kind: LayerGradientKind, stops: [LayerGradientStop]) {
        self.kind = kind
        self.stops = stops
    }

    /// The gradient's alpha at parameter `t` (research CMP-008-D1).
    public func alpha(at t: Double) -> Double {
        Self.alpha(at: t, stops: stops)
    }

    public static func alpha(at t: Double, stops: [LayerGradientStop]) -> Double {
        guard let first = stops.first else { return 1 }
        var a: Double = first.alpha
        var i: Int = 1
        while i < stops.count {
            let previous: LayerGradientStop = stops[i - 1]
            let next: LayerGradientStop = stops[i]
            if t >= next.position {
                a = next.alpha
                i += 1
                continue
            }
            if t > previous.position {
                let span: Double = next.position - previous.position
                let f: Double = (t - previous.position) / span
                let delta: Double = next.alpha - previous.alpha
                a = previous.alpha + delta * f
            }
            break
        }
        return a
    }

    /// The gradient resolved for a picture of `width` × `height` pixels (sizes below 1 read 1).
    public func geometry(width: Int, height: Int) -> LayerGradientGeometry {
        LayerGradientGeometry(gradient: self, width: width, height: height)
    }

    static func clamp(_ v: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
        guard v.isFinite else { return fallback }
        let c: Double = min(max(v, range.lowerBound), range.upperBound)
        return c == 0 ? 0 : c
    }

    static func clampPoint(_ p: LayerPoint, fallback: LayerPoint) -> LayerPoint {
        LayerPoint(x: clamp(p.x, pointRange, fallback.x), y: clamp(p.y, pointRange, fallback.y))
    }
}

/// A gradient resolved in pixels for one picture size: the CPU reference of the shader (CMP-008-R4) and the
/// numbers the compositor hands to it.
public struct LayerGradientGeometry: Sendable, Equatable {
    /// 1 linear, 2 radial (the shader's kind; 0 is "no gradient").
    public let kind: Int
    /// Linear: start x, y, end x, y; radial: centre x, y, radius, 0 (pixels).
    public let axis: (Double, Double, Double, Double)
    public let stops: [LayerGradientStop]

    init(gradient: LayerGradientMask, width: Int, height: Int) {
        let w: Double = Double(max(width, 1))
        let h: Double = Double(max(height, 1))
        let s: Double = min(w, h)
        switch gradient.kind {
        case let .linear(start, end):
            kind = 1
            axis = (start.x * w, start.y * h, end.x * w, end.y * h)
        case let .radial(center, radius):
            kind = 2
            axis = (center.x * w, center.y * h, radius * s, 0)
        }
        stops = gradient.stops
    }

    /// The gradient parameter t at the layer point (`x`, `y`) (pixel centre = index + 0.5).
    public func parameter(x: Double, y: Double) -> Double {
        if kind == 2 {
            let dx: Double = x - axis.0
            let dy: Double = y - axis.1
            let distance: Double = (dx * dx + dy * dy).squareRoot()
            return distance / axis.2
        }
        let ex: Double = axis.2 - axis.0
        let ey: Double = axis.3 - axis.1
        let px: Double = x - axis.0
        let py: Double = y - axis.1
        let along: Double = px * ex + py * ey
        let lengthSquared: Double = ex * ex + ey * ey
        return along / lengthSquared
    }

    /// The gradient alpha 0…1 at the layer point (`x`, `y`).
    public func alpha(x: Double, y: Double) -> Double {
        LayerGradientMask.alpha(at: parameter(x: x, y: y), stops: stops)
    }

    public static func == (lhs: LayerGradientGeometry, rhs: LayerGradientGeometry) -> Bool {
        lhs.kind == rhs.kind && lhs.axis == rhs.axis && lhs.stops == rhs.stops
    }
}
