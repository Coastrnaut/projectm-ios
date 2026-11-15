// CymaticPattern.swift — VIS-019's standing-wave field: the band ranges, the plate-mode table, the square-plate (Chladni)
// field, its blend, the nodal-line intensity, the nodal mask and the shading as a CPU mirror, and the same operations as
// Metal text (specs/308-vis-019-cymatic-line-patterns; research VIS-019-D2, D5; contract C3, C5).
//
// Mode (n, m, s): F(x, y) = cos(nπx)·cos(mπy) + s·cos(mπx)·cos(nπy) on the plate square x, y ∈ [0, 1] (the centred
// square on the shorter side, y up; the field continues beyond it), |F| ≤ 2. The frame blends the nine modes by their
// weights, F̄ = Σ wₖFₖ / Σ wₖ, and draws the nodal lines: L = 1 − smoothstep(0, width, |F̄|). Value = (L + fill ×
// (1 − L) × min(|F̄| / 2, 1)) × brightness × gain; colour = the 16-stop palette at the blended t. Every value is
// sanitized, so no input reaches the maths as NaN or infinity. No allocation, no wall clock. Plain Swift; builds on Linux.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Which bands drive the figure (VIS-019-R3); stored by the app as the raw value.
public enum CymaticBandRange: String, CaseIterable, Sendable {
    case all
    case low
    case mid
    case high

    public static let defaultRange = CymaticBandRange.all

    /// The band indices of `count` bands this range selects (VIS-007's thirds; the remainder goes to high).
    public func indices(count: Int) -> Range<Int> {
        let n: Int = max(count, 0)
        let g: Int = n / 3
        switch self {
        case .all: return 0..<n
        case .low: return 0..<g
        case .mid: return g..<(2 * g)
        case .high: return (2 * g)..<n
        }
    }

    public var title: String {
        switch self {
        case .all: "All"
        case .low: "Low"
        case .mid: "Mid"
        case .high: "High"
        }
    }
}

/// The mode's settings in `NoiseFieldConfiguration.cymatic` (nil there: the mode is off).
public struct CymaticSettings: Sendable, Equatable {
    public static let `default` = CymaticSettings()

    public var bands: CymaticBandRange

    public init(bands: CymaticBandRange = .defaultRange) {
        self.bands = bands
    }
}

/// One square-plate mode.
public struct CymaticMode: Sendable, Equatable {
    public var n: Float
    public var m: Float
    /// +1 or −1.
    public var sign: Float
    /// The mode's position in the 16-stop palette (0…1).
    public var paletteT: Float

    public init(n: Float, m: Float, sign: Float, paletteT: Float) {
        self.n = n
        self.m = m
        self.sign = sign
        self.paletteT = paletteT
    }
}

/// What one frame draws (the drive's output; the shader's uniform block).
public struct CymaticFrame: Sendable, Equatable {
    /// Lanes 0…8: the modes' blend weights (0…1); lanes 9…15 unused (0).
    public var weights: SIMD16<Float>
    /// 0…1.
    public var amplitude: Float
    /// Line half-profile width in field units.
    public var width: Float
    /// Blended palette position, 0…1.
    public var paletteT: Float
    /// Antinode fill depth, 0…0.15.
    public var fill: Float
    /// 0.35…0.8 (ACC-012: below full white).
    public var brightness: Float

    public init(weights: SIMD16<Float>, amplitude: Float, width: Float, paletteT: Float, fill: Float, brightness: Float) {
        self.weights = weights
        self.amplitude = amplitude
        self.width = width
        self.paletteT = paletteT
        self.fill = fill
        self.brightness = brightness
    }

    /// The resting frame (whatever Reduce Motion: the amplitude is 0).
    public static let rest = CymaticField.frame(weights: CymaticField.restWeights, amplitude: 0, reduceMotion: false)
}

/// The CPU mirror of the field (`CymaticShader`).
public enum CymaticField {
    /// Mode 0 rests; 1…8 are driven, one per part of the selected range.
    public static let modeCount = 9
    public static let drivenCount = 8
    public static let restIndex = 0
    /// The table (VIS-019 Clarifications Q2): rest (1, 1, +), then rising complexity.
    public static let modes: [CymaticMode] = [
        CymaticMode(n: 1, m: 1, sign: 1, paletteT: 0.5),
        CymaticMode(n: 1, m: 2, sign: -1, paletteT: 0),
        CymaticMode(n: 1, m: 3, sign: 1, paletteT: 1.0 / 7),
        CymaticMode(n: 2, m: 3, sign: -1, paletteT: 2.0 / 7),
        CymaticMode(n: 1, m: 4, sign: -1, paletteT: 3.0 / 7),
        CymaticMode(n: 2, m: 4, sign: 1, paletteT: 4.0 / 7),
        CymaticMode(n: 3, m: 4, sign: -1, paletteT: 5.0 / 7),
        CymaticMode(n: 2, m: 5, sign: 1, paletteT: 6.0 / 7),
        CymaticMode(n: 3, m: 5, sign: -1, paletteT: 1),
    ]
    public static let baseWidth: Float = 0.08
    public static let widthDepth: Float = 0.06
    /// The nodal mask: |F̄| ≤ this (L ≥ 0.5 at amplitude 0).
    public static let maskHalfWidth: Float = 0.04
    public static let fillDepth: Float = 0.15
    public static let baseBrightness: Float = 0.35
    public static let brightnessDepth: Float = 0.45
    public static let maximumBrightness: Float = 0.8
    /// ACC-001: the width depth factor.
    public static let reduceMotionScale: Float = 0.5

    /// Weight 1 on the rest mode only.
    public static let restWeights: SIMD16<Float> = one(restIndex)

    /// Weight 1 on mode `k` only (k clamped to 0…8).
    public static func one(_ k: Int) -> SIMD16<Float> {
        var w = SIMD16<Float>(repeating: 0)
        w[min(max(k, 0), modeCount - 1)] = 1
        return w
    }

    static func clean(_ v: Float) -> Float { v.isFinite ? min(max(v, 0), 1) : 0 }

    /// The frame for `weights` (sanitized; all zero → rest) and `amplitude`.
    public static func frame(weights raw: SIMD16<Float>, amplitude rawAmplitude: Float, reduceMotion: Bool) -> CymaticFrame {
        var w = SIMD16<Float>(repeating: 0)
        var sum: Float = 0
        var t: Float = 0
        for k in 0..<modeCount {
            let v: Float = clean(raw[k])
            w[k] = v
            sum += v
            t += v * modes[k].paletteT
        }
        if !(sum > 0) { w = restWeights; sum = 1; t = modes[restIndex].paletteT }
        let a: Float = clean(rawAmplitude)
        let depth: Float = reduceMotion ? widthDepth * reduceMotionScale : widthDepth
        return CymaticFrame(weights: w, amplitude: a, width: baseWidth + depth * a, paletteT: clean(t / sum), fill: fillDepth * a,
                            brightness: min(baseBrightness + brightnessDepth * a, maximumBrightness))
    }

    /// Plate coordinates of pixel centre `pixel` (pixel units, rows top first) in a `width × height` output.
    public static func plate(pixel: SIMD2<Float>, width: Int, height: Int) -> SIMD2<Float> {
        let size = SIMD2<Float>(Float(max(width, 1)), Float(max(height, 1)))
        let p: SIMD2<Float> = (pixel - 0.5 * size) / min(size.x, size.y)
        return SIMD2<Float>(p.x + 0.5, -p.y + 0.5)
    }

    /// Mode `mode`'s displacement at plate point `q`.
    public static func value(_ mode: CymaticMode, at q: SIMD2<Float>) -> Float {
        let pi: Float = Float.pi
        let a: Float = cosf(mode.n * pi * q.x) * cosf(mode.m * pi * q.y)
        let b: Float = cosf(mode.m * pi * q.x) * cosf(mode.n * pi * q.y)
        return a + mode.sign * b
    }

    /// The blended displacement F̄ at `q` (weights as a sanitized frame's; 0 when they sum to 0).
    public static func blended(at q: SIMD2<Float>, weights: SIMD16<Float>) -> Float {
        let safe = SIMD2<Float>(q.x.isFinite ? q.x : 0, q.y.isFinite ? q.y : 0)
        var sum: Float = 0
        var total: Float = 0
        for k in 0..<modeCount where weights[k] > 0 {
            sum += weights[k] * value(modes[k], at: safe)
            total += weights[k]
        }
        return total > 0 ? sum / total : 0
    }

    /// The nodal-line intensity for displacement `f`: 1 − smoothstep(0, width, |f|).
    public static func line(_ f: Float, width: Float) -> Float {
        let w: Float = width.isFinite ? min(max(width, 0.01), 0.5) : baseWidth
        let x: Float = f.isFinite ? min(abs(f) / w, 1) : 1
        return 1 - x * x * (3 - 2 * x)
    }

    /// Whether `f` lies on the nodal mask (VIS-019 Clarifications Q2).
    public static func onMask(_ f: Float) -> Bool { abs(f) <= maskHalfWidth }

    /// The pixel's colour at gain 1 (linear, 0…1) for `frame`; `stops` holds 16 colours.
    public static func shade(_ q: SIMD2<Float>, frame: CymaticFrame, stops: UnsafePointer<LinearColor>) -> LinearColor {
        let f: Float = blended(at: q, weights: frame.weights)
        let l: Float = line(f, width: frame.width)
        let fill: Float = clean(frame.fill) * (1 - l) * min(abs(f) * 0.5, 1)
        let lit: Float = (l + fill) * min(max(frame.brightness.isFinite ? frame.brightness : 0, 0), maximumBrightness)
        let base: LinearColor = SignedDistanceScene.paletteColor(frame.paletteT, stops: stops)
        return LinearColor(red: clean(base.red * lit), green: clean(base.green * lit), blue: clean(base.blue * lit), alpha: 1)
    }
}

/// The GPU side of `CymaticField`: Metal Shading Language authored in this module (no external code; SHD-011).
/// Placed after the noise field's body (uses `NoiseOut` and `NoiseUniforms`).
public enum CymaticShader {
    /// Floats of the mode's own uniform block (buffer 1): nine float4 (n, m, sign, weight), then amplitude, width,
    /// palette t, fill.
    public static let uniformFloats = 4 * CymaticField.modeCount + 4

    public static let functions = """

    // VIS-019: cymatic lines (matches CymaticField; the block arrives sanitized).
    struct CymUniforms {
        float4 modes[9];
        float amplitude;
        float width;
        float paletteT;
        float fill;
    };

    static float vis_cym_field(float2 q, constant CymUniforms &c) {
        float sum = 0.0;
        float total = 0.0;
        for (int k = 0; k < 9; k++) {
            float4 m = c.modes[k];
            if (!(m.w > 0.0)) { continue; }
            float a = cos(m.x * M_PI_F * q.x) * cos(m.y * M_PI_F * q.y);
            float b = cos(m.y * M_PI_F * q.x) * cos(m.x * M_PI_F * q.y);
            sum += m.w * (a + m.z * b);
            total += m.w;
        }
        return total > 0.0 ? sum / total : 0.0;
    }

    static float2 vis_cym_plate(float2 position, float2 size) {
        float2 p = (position - 0.5 * size) / min(size.x, size.y);
        return float2(p.x + 0.5, -p.y + 0.5);
    }

    static float vis_cym_line(float f, float width) {
        float w = clamp(width, 0.01, 0.5);
        float x = min(abs(f) / w, 1.0);
        return 1.0 - x * x * (3.0 - 2.0 * x);
    }

    fragment float4 vis_cym_fragment(NoiseOut in [[stage_in]], constant NoiseUniforms &u [[buffer(0)]],
                                     constant CymUniforms &c [[buffer(1)]]) {
        float2 size = max(u.size, float2(1.0));
        float f = vis_cym_field(vis_cym_plate(in.position.xy, size), c);
        float l = vis_cym_line(f, c.width);
        float lit = (l + clamp(c.fill, 0.0, 1.0) * (1.0 - l) * min(abs(f) * 0.5, 1.0)) * u.brightness;
        float position = clamp(c.paletteT, 0.0, 1.0) * 15.0;
        int i = min(int(position), 14);
        float t = position - float(i);
        float3 col = mix(u.palette[i].rgb, u.palette[i + 1].rgb, t) * lit;
        col = select(col, float3(0.0), isnan(col) || isinf(col));
        return float4(clamp(col, 0.0, 1.0), 1.0);
    }

    // Tests only (VIS-019-D5): the blended displacement in red, the line intensity in green.
    fragment float4 vis_cym_mask_fragment(NoiseOut in [[stage_in]], constant NoiseUniforms &u [[buffer(0)]],
                                          constant CymUniforms &c [[buffer(1)]]) {
        float2 size = max(u.size, float2(1.0));
        float f = vis_cym_field(vis_cym_plate(in.position.xy, size), c);
        return float4(f, vis_cym_line(f, c.width), 0.0, 1.0);
    }
    """
}
