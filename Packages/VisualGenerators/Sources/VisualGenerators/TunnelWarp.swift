// TunnelWarp.swift — VIS-015's tunnel: the pace and tempo values, the polar mapping and seamless texture (CPU mirror and
// MSL text), and the tempo-driven drive (specs/263-vis-015-tunnel-warp; research VIS-015-D2 to D4; contract T1-T4).
//
// Mapping: p relative to the frame centre over the shorter side; r = max(|p|, 1e-3); u = atan2(p.y, p.x) / 2π + 0.5;
// depth v = 0.5 / r + phase. Light = ring (0.7 + 0.3 cos 2π·fract v) × fog (smoothstep 0.02…0.5 of r) × (0.35 + 0.65 t);
// t = two octaves of SHD-006's value noise at (8u, v) and (16u, 2v), blended across the angle cut so u = 0 and u = 1 read
// the same lattice cells. The lattice repeats every 4096 cells, so the texture is periodic in depth with period 4096 and
// the phase wraps there without a jump. `TunnelShader.function` is the same operations in Metal (SHD-011: module text).
//
// Drive: target speed (rings/s) = pace × BPM / 60 for a valid tempo, else 1.5 × pace (a 90 BPM equivalent), never above
// 3 rings/s (at any pixel the rings then alternate at most 3 times a second), × 0.5 with Reduce Motion. The speed follows
// the target with τ = 0.5 s on the frame clock's step (clamped to 0…0.25 s); the phase advances by speed × step, never
// backwards; the first frame after a reset takes the target directly. Bass brightens the wall (0.5 + 0.3 × low, ≤ 0.8;
// half the punch with Reduce Motion). No wall clock, no random source, no allocation. Plain Swift; builds on Linux.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Rings per beat (VIS-015-R4); stored by the app as the raw value.
public enum TunnelPace: String, CaseIterable, Sendable {
    case half
    case beat
    case double

    public static let defaultPace = TunnelPace.beat

    public var ringsPerBeat: Double {
        switch self {
        case .half: 0.5
        case .beat: 1
        case .double: 2
        }
    }

    /// "1 ring every 2 beats", "1 ring per beat", "2 rings per beat".
    public var title: String {
        switch self {
        case .half: "1 ring every 2 beats"
        case .beat: "1 ring per beat"
        case .double: "2 rings per beat"
        }
    }

    /// The pace nearest `ringsPerBeat` (> 0); nil for 0, negative or not finite.
    public init?(ringsPerBeat: Double) {
        guard ringsPerBeat.isFinite, ringsPerBeat > 0 else { return nil }
        if ringsPerBeat < 0.75 { self = .half } else if ringsPerBeat < 1.5 { self = .beat } else { self = .double }
    }
}

/// The tempo the tunnel follows: SHOW-011's snapshot as plain values (the app maps it; VIS-015-R4).
public struct TunnelTempo: Sendable, Equatable {
    /// An estimate counts from this confidence (SHOW-011's floor, ANL-005's "high"); manual taps carry 1.
    public static let minimumConfidence = 0.5
    public static let none = TunnelTempo(bpm: nil, confidence: 0)

    public var bpm: Double?
    public var confidence: Double

    public init(bpm: Double?, confidence: Double) {
        self.bpm = bpm
        self.confidence = confidence
    }

    /// The BPM when finite, > 0 and confident enough; else nil (no tempo).
    public var validBPM: Double? {
        guard let bpm, bpm.isFinite, bpm > 0, confidence.isFinite, confidence >= Self.minimumConfidence else { return nil }
        return bpm
    }
}

/// The CPU mirror of the tunnel's picture (`vis_tunnel_sample`).
public enum TunnelMapping {
    public static let depthScale: Float = 0.5
    public static let minimumRadius: Float = 0.001
    public static let fogInner: Float = 0.02
    public static let fogOuter: Float = 0.5
    /// Noise cells around the tunnel (first octave; the second has twice as many).
    public static let cellsAround: Float = 8
    /// SHD-006 field key of the tunnel's texture (0-2 are the noise field's).
    public static let textureField: UInt32 = 3

    /// One texture octave pair at (u, v).
    public static func layer(u: Float, v: Float, seed: UInt32) -> Float {
        let a: Float = SeededNoise.noise(SIMD2<Float>(cellsAround * u, v), key: SeededNoise.key(seed: seed, octave: 0, field: textureField))
        let b: Float = SeededNoise.noise(SIMD2<Float>(2 * cellsAround * u, 2 * v), key: SeededNoise.key(seed: seed, octave: 1, field: textureField))
        return 0.65 * a + 0.35 * b
    }

    /// The seamless texture t (0…1) at angle position u (0…1) and depth v.
    public static func texture(u: Float, v: Float, seed: UInt32) -> Float {
        (1 - u) * layer(u: u, v: v, seed: seed) + u * layer(u: u - 1, v: v, seed: seed)
    }

    /// Metal's `smoothstep`.
    @inlinable
    public static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t: Float = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// (texture t, light) at point p (relative to the centre over the shorter side) for `phase` rings.
    public static func sample(_ p: SIMD2<Float>, phase: Float, seed: UInt32) -> (t: Float, light: Float) {
        let r: Float = max((p.x * p.x + p.y * p.y).squareRoot(), minimumRadius)
        let u: Float = atan2f(p.y, p.x) * 0.159_154_94 + 0.5
        let v: Float = depthScale / r + phase
        let t: Float = texture(u: u, v: v, seed: seed)
        let f: Float = v - v.rounded(.down)
        let ring: Float = 0.7 + 0.3 * cosf(6.283_185_3 * f)
        let fog: Float = smoothstep(fogInner, fogOuter, r)
        return (t, ring * fog * (0.35 + 0.65 * t))
    }
}

/// The GPU side of `TunnelMapping`: Metal Shading Language authored in this module (no external code; SHD-011). Needs
/// `SeededNoiseShader.functions` before it.
public enum TunnelShader {
    public static let function = """
    static float vis_tunnel_layer(float u, float v, uint seed) {
        float a = mat_snoise(float2(8.0 * u, v), seed | (3u << 19));
        float b = mat_snoise(float2(16.0 * u, 2.0 * v), seed | (1u << 16) | (3u << 19));
        return 0.65 * a + 0.35 * b;
    }

    static float vis_tunnel_texture(float u, float v, uint seed) {
        return (1.0 - u) * vis_tunnel_layer(u, v, seed) + u * vis_tunnel_layer(u - 1.0, v, seed);
    }

    // x: texture t (0…1), y: light (ring × fog × texture shade), as TunnelMapping.sample.
    static float2 vis_tunnel_sample(float2 p, float phase, uint seed) {
        float r = max(length(p), 0.001);
        float u = atan2(p.y, p.x) * 0.15915494 + 0.5;
        float v = 0.5 / r + phase;
        float t = vis_tunnel_texture(u, v, seed);
        float f = v - floor(v);
        float ring = 0.7 + 0.3 * cos(6.2831853 * f);
        float fog = smoothstep(0.02, 0.5, r);
        return float2(t, ring * fog * (0.35 + 0.65 * t));
    }

    """
}

/// The tunnel's motion and light per frame (VIS-015-R4 to R8; contract T1, T2). Not Sendable-sensitive: one thread.
public struct TunnelDrive: Sendable, Equatable {
    /// Base speed per ring-per-beat without a tempo (a 90 BPM equivalent), rings/s.
    public static let baseRingsPerSecond = 1.5
    /// Safety cap, rings/s (3 luminance cycles per second at any pixel).
    public static let maximumRingsPerSecond = 3.0
    public static let speedTimeConstant = 0.5
    /// The most one frame advances, s.
    public static let maxStep = 0.25
    public static let phasePeriod = 4096.0
    public static let reduceMotionScale = 0.5
    public static let baseBrightness = 0.5
    public static let bassBrightness = 0.3
    public static let maximumBrightness = 0.8
    public static let attackTimeConstant = 0.08
    public static let releaseTimeConstant = 0.3

    /// Rings per second (smoothed).
    public private(set) var speed: Double = 0
    /// The last frame's target speed.
    public private(set) var target: Double = 0
    /// 0.5…0.8.
    public private(set) var brightness: Double = TunnelDrive.baseBrightness
    /// Rings in [0, 4096).
    public private(set) var phase: Double = 0
    private var lastNanoseconds: UInt64?

    public init() {}

    public mutating func reset() { self = TunnelDrive() }

    /// The target speed (rings/s) for `tempo` at `ringsPerBeat` (≤ 0 or not finite → 0).
    public static func targetSpeed(tempo: TunnelTempo, ringsPerBeat: Double, reduceMotion: Bool) -> Double {
        let pace: Double = ringsPerBeat.isFinite ? max(ringsPerBeat, 0) : 0
        let raw: Double
        if let bpm = tempo.validBPM { raw = pace * bpm / 60 } else { raw = pace * baseRingsPerSecond }
        let capped: Double = min(raw, maximumRingsPerSecond)
        return reduceMotion ? capped * reduceMotionScale : capped
    }

    /// The brightness target for a low group `low` (0…1; else clamped, not finite → 0).
    public static func brightnessTarget(low: Double, reduceMotion: Bool) -> Double {
        let l: Double = low.isFinite ? min(max(low, 0), 1) : 0
        let punch: Double = reduceMotion ? bassBrightness * reduceMotionScale : bassBrightness
        return min(baseBrightness + punch * l, maximumBrightness)
    }

    /// Advances to the frame at `nanoseconds`.
    public mutating func advance(groups: MandalaBandGroups, tempo: TunnelTempo, timeNanoseconds nanoseconds: UInt64,
                                 configuration: NoiseFieldConfiguration) {
        let goal: Double = Self.targetSpeed(tempo: tempo, ringsPerBeat: configuration.tunnelPace,
                                            reduceMotion: configuration.reduceMotion)
        target = goal
        guard let last = lastNanoseconds else {
            speed = goal   // nothing to be continuous with
            lastNanoseconds = nanoseconds
            return
        }
        let dt: Double = nanoseconds > last ? min(Double(nanoseconds - last) / 1e9, Self.maxStep) : 0
        let k: Double = 1 - exp(-dt / Self.speedTimeConstant)
        speed += (goal - speed) * k
        let lit: Double = Self.brightnessTarget(low: groups.low, reduceMotion: configuration.reduceMotion)
        let tau: Double = lit > brightness ? Self.attackTimeConstant : Self.releaseTimeConstant
        brightness += (lit - brightness) * (1 - exp(-dt / tau))
        brightness = min(max(brightness, Self.baseBrightness), Self.maximumBrightness)
        phase = (phase + speed * dt).truncatingRemainder(dividingBy: Self.phasePeriod)
        if nanoseconds > last { lastNanoseconds = nanoseconds }
    }
}
