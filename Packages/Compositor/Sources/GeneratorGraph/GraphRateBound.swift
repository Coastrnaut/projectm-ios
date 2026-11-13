// GraphRateBound.swift — a conservative bound on every value of a graph: its largest absolute
// component and how fast it can change per unit of phase and per unit of music level (SHD-002-R12;
// research SHD-002-D5; data-model.md "Node kinds", column "Bound").
//
// Bounds use the max norm over components and the chain rule with each operation's Lipschitz
// constant (smoothstep 1.5 per edge width, value noise 3 per cell, a rotation √2 between max norms).
// A bound may be +∞ (polar of a moving point: its angle jumps), which the compiler rejects. NaN
// (0 · ∞) is read as +∞. Plain Swift; builds on Linux.

/// Change per unit of phase (`p`) and per unit of music level (`a`).
struct GraphRate: Equatable, Sendable {
    var p: Double
    var a: Double

    static let zero = GraphRate(p: 0, a: 0)

    static func + (l: GraphRate, r: GraphRate) -> GraphRate { GraphRate(p: l.p + r.p, a: l.a + r.a) }
    static func * (k: Double, r: GraphRate) -> GraphRate { GraphRate(p: k * r.p, a: k * r.a).sanitized }
    func maximum(_ o: GraphRate) -> GraphRate { GraphRate(p: max(p, o.p), a: max(a, o.a)) }
    var isZero: Bool { p == 0 && a == 0 }
    var sanitized: GraphRate { GraphRate(p: p.isNaN ? .infinity : p, a: a.isNaN ? .infinity : a) }
}

struct GraphBound: Equatable, Sendable {
    /// Largest absolute component.
    var m: Double
    var d: GraphRate

    static let coordinates = GraphBound(m: 2, d: .zero)
    static let time = GraphBound(m: 0, d: GraphRate(p: 1, a: 0))
    static let music = GraphBound(m: 1, d: GraphRate(p: 0, a: 1))

    static func literal(_ components: [Double]) -> GraphBound {
        GraphBound(m: components.reduce(0) { (x: Double, v: Double) -> Double in max(x, abs(v)) }, d: .zero)
    }

    /// The bound after clamping to `lower…upper`.
    func clamped(_ lower: Double, _ upper: Double) -> GraphBound {
        GraphBound(m: min(m, max(abs(lower), abs(upper))), d: d)
    }
}

enum GraphRateBounds {
    static let sqrt2 = 2.0.squareRoot()
    static let tau = 2 * Double.pi

    /// Lipschitz constant of the interpreter's value noise / fbm per unit of input, for `scale` and
    /// `octaves`: 3 · scale · Σ(0.5ⁱ · 2.03ⁱ) / Σ 0.5ⁱ (smoothstep interpolation slope 1.5 per axis).
    static func noiseLipschitz(scale: Double, octaves: Int) -> Double {
        var sum = 0.0, norm = 0.0, amp = 1.0, freq = 1.0
        for _ in 0..<max(1, min(octaves, 5)) {
            sum += amp * freq
            norm += amp
            amp *= 0.5
            freq *= 2.03
        }
        return 3 * scale * sum / norm
    }

    /// The bound of a node's value from its inputs' bounds (`inputs` in the kind's value-input order),
    /// whether its phase input is connected, and its settings.
    static func bound(_ kind: GraphNodeKind, inputs x: [GraphBound], phaseConnected: Bool,
                      setting s: (String) -> Double) -> GraphBound {
        let phaseRate = phaseConnected ? GraphRate(p: 1, a: 0) : .zero
        switch kind {
        case .coordinates: return .coordinates
        case .time: return .time
        case .musicLevel: return .music
        case .oscillate:
            return GraphBound(m: 1, d: (Double.pi * abs(s("rate"))) * phaseRate)
        case .spin:
            let p = x[0]
            return GraphBound(m: sqrt2 * p.m, d: sqrt2 * p.d + (tau * abs(s("rate")) * sqrt2 * p.m) * phaseRate)
        case .drift:
            let p = x[0]
            let v = max(abs(s("velocityX")), abs(s("velocityY")))
            return GraphBound(m: p.m + GraphTimeTerm.driftWrap, d: p.d + v * phaseRate)
        case .scale:
            let p = x[0], k = x[1]
            return GraphBound(m: p.m * k.m, d: k.m * p.d + p.m * k.d)
        case .rotate:
            let p = x[0], t = x[1]
            return GraphBound(m: sqrt2 * p.m, d: sqrt2 * p.d + (tau * sqrt2 * p.m) * t.d)
        case .translate:
            let p = x[0], tx = x[1], ty = x[2]
            return GraphBound(m: p.m + max(tx.m, ty.m), d: p.d + tx.d.maximum(ty.d))
        case .polar:
            let p = x[0]
            let d = p.d.isZero ? GraphRate.zero : GraphRate(p: p.d.p == 0 ? 0 : .infinity, a: p.d.a == 0 ? 0 : .infinity)
            return GraphBound(m: max(1, sqrt2 * p.m), d: d)
        case .circle, .ring, .box:
            let lip = 1.5 / (2 * s("softness")) * sqrt2
            return GraphBound(m: 1, d: lip * x[0].d)
        case .noise:
            let lip = noiseLipschitz(scale: s("scale"), octaves: Int(s("octaves").rounded()))
            return GraphBound(m: 1, d: lip * x[0].d)
        case .add:
            return GraphBound(m: x[0].m + x[1].m, d: x[0].d + x[1].d)
        case .multiply:
            return GraphBound(m: x[0].m * x[1].m, d: x[1].m * x[0].d + x[0].m * x[1].d)
        case .clamp:
            return GraphBound(m: min(x[0].m, max(abs(s("min")), abs(s("max")))), d: x[0].d)
        case .smoothstep:
            return GraphBound(m: 1, d: (1.5 / abs(s("edge1") - s("edge0"))) * x[0].d)
        case .wave:
            return GraphBound(m: 1, d: (Double.pi * s("frequency")) * x[0].d)
        case .component:
            return GraphBound(m: x[0].m, d: x[0].d)
        case .gradient:
            // mix(A, B, t) with colors in 0…1: (1 − t)·dA + t·dB + (B − A)·dt.
            return GraphBound(m: 1, d: x[1].d.maximum(x[2].d) + x[0].d)
        case .palette:
            let f = s("frequency")
            return GraphBound(m: 1, d: (Double.pi * f) * x[0].d + (Double.pi * abs(s("shiftRate"))) * phaseRate)
        case .hsv:
            return GraphBound(m: 1, d: 6 * x[0].d + x[1].d + x[2].d)
        case .mixColor:
            return GraphBound(m: 1, d: x[0].d.maximum(x[1].d) + x[2].d)
        case .scaleColor:
            return GraphBound(m: 1, d: x[0].d + x[1].d)
        case .output:
            return GraphBound(m: 1, d: s("brightness") * x[0].d)
        }
    }
}
