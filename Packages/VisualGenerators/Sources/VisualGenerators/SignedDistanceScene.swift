// SignedDistanceScene.swift — VIS-017's bounded signed-distance scene: the quality presets, the scene (one sphere, one torus,
// four rounded boxes inside a bounding sphere), the bounded march, normals and shading as a CPU mirror, and the same
// operations as Metal text (specs/304-vis-017-signed-distance-primitives; research VIS-017-D2 to D4; contract C3, C4).
//
// Camera at (0, 0, −4.5) looking along +z; pixel p (relative to the frame centre over the shorter side, y up) gives the ray
// direction normalize(p.x, p.y, 1.07) (about 50° across the shorter side). A ray that misses the bounding sphere (radius 2)
// is background with 0 steps; one that enters marches from the entry point by the scene distance (at least the hit
// threshold per step) and stops at a hit (distance < threshold), at the exit point, or at the preset's step cap (never
// above 128). Every primitive's distance is exact or a lower bound (Lipschitz ≤ 1), so the march never passes through a
// surface. A hit is shaded with the tetrahedral normal (4 more distance evaluations): palette colour of its kind ×
// (0.15 + 0.85 · max(n·L, 0)) × brightness × gain, clamped to 0…1. The pose is sanitized before use, so no input can
// reach the maths as NaN or infinity. No allocation, no wall clock. Plain Swift; builds on Linux.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// The marching quality (VIS-017-R4); stored by the app as the raw value.
public enum SignedDistanceQuality: String, CaseIterable, Sendable {
    case low
    case medium
    case high

    public static let defaultQuality = SignedDistanceQuality.medium

    /// The most steps one pixel's march takes.
    public var stepCap: Int {
        switch self {
        case .low: 24
        case .medium: 48
        case .high: 96
        }
    }

    /// A march stops when the scene distance falls below this (scene units).
    public var hitThreshold: Float {
        switch self {
        case .low: 0.004
        case .medium: 0.002
        case .high: 0.001
        }
    }

    public var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

/// The mode's settings in `NoiseFieldConfiguration.signedDistance` (nil there: the mode is off).
public struct SignedDistanceSettings: Sendable, Equatable {
    public static let `default` = SignedDistanceSettings()

    public var quality: SignedDistanceQuality

    public init(quality: SignedDistanceQuality = .defaultQuality) {
        self.quality = quality
    }
}

/// What a ray hit.
public enum SignedDistanceKind: Int, Sendable, CaseIterable {
    case sphere = 0
    case torus = 1
    case box = 2

    /// The kind's position in the 16-stop palette (0…1).
    public var paletteT: Float {
        switch self {
        case .sphere: 0.15
        case .torus: 0.5
        case .box: 0.85
        }
    }
}

/// One frame's pose (the drive's output). `sanitized()` keeps every value finite and in range.
public struct SignedDistancePose: Sendable, Equatable {
    public static let rest = SignedDistancePose(angle: 0, sphereRadius: SignedDistanceScene.sphereRadius,
                                                brightness: SignedDistanceScene.baseBrightness)

    /// Turning angle, radians in [0, 2π).
    public var angle: Float
    /// 0.55…0.70.
    public var sphereRadius: Float
    /// 0.5…0.8 (ACC-012: below full white).
    public var brightness: Float

    public init(angle: Float, sphereRadius: Float, brightness: Float) {
        self.angle = angle
        self.sphereRadius = sphereRadius
        self.brightness = brightness
    }

    public func sanitized() -> SignedDistancePose {
        let turn: Float = 2 * Float.pi
        var a: Float = angle.isFinite ? angle.truncatingRemainder(dividingBy: turn) : 0
        if a < 0 { a += turn }
        if !(a < turn) { a = 0 }
        let r: Float = sphereRadius.isFinite
            ? min(max(sphereRadius, SignedDistanceScene.sphereRadius), SignedDistanceScene.maximumSphereRadius) : SignedDistanceScene.sphereRadius
        let b: Float = brightness.isFinite
            ? min(max(brightness, 0), SignedDistanceScene.maximumBrightness) : SignedDistanceScene.baseBrightness
        return SignedDistancePose(angle: a, sphereRadius: r, brightness: b)
    }
}

/// One ray's march.
public struct SignedDistanceMarch: Sendable, Equatable {
    /// Scene evaluations in the march loop (0 for a ray that misses the bounding sphere).
    public var steps: Int
    /// The ray parameter where it stopped.
    public var distance: Float
    /// nil: background.
    public var kind: SignedDistanceKind?
}

/// The CPU mirror of the scene (`SignedDistanceShader`).
public enum SignedDistanceScene {
    /// Absolute ceiling on any march (the shader clamps its uniform to this too).
    public static let maximumSteps = 128
    public static let boundingRadius: Float = 2.0
    public static let cameraDistance: Float = 4.5
    public static let focal: Float = 1.07
    public static let sphereRadius: Float = 0.55
    public static let sphereSwell: Float = 0.15
    public static let maximumSphereRadius: Float = 0.70
    public static let torusMajor: Float = 1.05
    public static let torusMinor: Float = 0.11
    public static let tilt: Float = 0.5
    public static let boxHalf: Float = 0.16
    public static let boxRounding: Float = 0.03
    public static let boxOrbit: Float = 1.6
    public static let boxCount = 4
    public static let ambient: Float = 0.15
    public static let baseBrightness: Float = 0.5
    public static let maximumBrightness: Float = 0.8
    public static let light = SIMD3<Float>(0.5, 0.8, -0.6) / (0.25 + 0.64 + 0.36 as Float).squareRoot()
    public static let normalStep: Float = 0.001

    // MARK: primitives (exact distances)

    @inlinable
    static func length(_ v: SIMD3<Float>) -> Float { (v * v).sum().squareRoot() }

    public static func sphere(_ p: SIMD3<Float>, radius: Float) -> Float { length(p) - radius }

    /// A torus in the xz-plane.
    public static func torus(_ p: SIMD3<Float>, major: Float, minor: Float) -> Float {
        let ring: Float = (p.x * p.x + p.z * p.z).squareRoot() - major
        return (ring * ring + p.y * p.y).squareRoot() - minor
    }

    /// A box of half-size `half` with edges rounded by `rounding`.
    public static func roundedBox(_ p: SIMD3<Float>, half: Float, rounding: Float) -> Float {
        let q: SIMD3<Float> = SIMD3<Float>(abs(p.x), abs(p.y), abs(p.z)) - SIMD3<Float>(repeating: half - rounding)
        let outside: Float = length(simd_max3(q, .zero))
        let inside: Float = min(max(q.x, max(q.y, q.z)), 0)
        return outside + inside - rounding
    }

    @inlinable
    static func simd_max3(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z))
    }

    /// Rotation about x by `a` (as the shader's `vis_sdf_rx`).
    static func rotateX(_ p: SIMD3<Float>, _ a: Float) -> SIMD3<Float> {
        let c: Float = cosf(a), s: Float = sinf(a)
        return SIMD3<Float>(p.x, c * p.y - s * p.z, s * p.y + c * p.z)
    }

    /// Rotation about y by `a`.
    static func rotateY(_ p: SIMD3<Float>, _ a: Float) -> SIMD3<Float> {
        let c: Float = cosf(a), s: Float = sinf(a)
        return SIMD3<Float>(c * p.x + s * p.z, p.y, -s * p.x + c * p.z)
    }

    // MARK: scene

    /// The scene distance at `p` and the nearest primitive's kind. `pose` must be sanitized.
    public static func distance(_ p: SIMD3<Float>, pose: SignedDistancePose) -> (distance: Float, kind: SignedDistanceKind) {
        var best: Float = sphere(p, radius: pose.sphereRadius)
        var kind: SignedDistanceKind = .sphere
        let tilted: SIMD3<Float> = rotateX(p, -tilt)
        let ring: Float = torus(rotateY(tilted, -pose.angle), major: torusMajor, minor: torusMinor)
        if ring < best { best = ring; kind = .torus }
        let orbit: SIMD3<Float> = rotateY(tilted, pose.angle)
        for k in 0..<boxCount {
            let a: Float = Float(k) * 0.5 * Float.pi
            let centre = SIMD3<Float>(boxOrbit * cosf(a), 0, boxOrbit * sinf(a))
            let local: SIMD3<Float> = rotateX(orbit - centre, 2 * pose.angle)
            let d: Float = roundedBox(local, half: boxHalf, rounding: boxRounding)
            if d < best { best = d; kind = .box }
        }
        return (best, kind)
    }

    /// The camera ray through pixel offset `p` (relative to the frame centre over the shorter side, y up).
    public static func ray(_ p: SIMD2<Float>) -> (origin: SIMD3<Float>, direction: SIMD3<Float>) {
        let raw = SIMD3<Float>(p.x, p.y, focal)
        let n: Float = max((raw * raw).sum(), 1e-12).squareRoot()
        return (SIMD3<Float>(0, 0, -cameraDistance), raw / n)
    }

    /// The bounding sphere's entry and exit along a unit ray; nil when the ray misses it.
    public static func bounds(origin: SIMD3<Float>, direction: SIMD3<Float>) -> (entry: Float, exit: Float)? {
        let b: Float = (origin * direction).sum()
        let c: Float = (origin * origin).sum() - boundingRadius * boundingRadius
        let disc: Float = b * b - c
        guard disc > 0 else { return nil }
        let root: Float = disc.squareRoot()
        return (max(-b - root, 0), -b + root)
    }

    /// The effective cap for `quality` (never above `maximumSteps`, at least 1).
    public static func cap(_ quality: SignedDistanceQuality) -> Int { min(max(quality.stepCap, 1), maximumSteps) }

    /// Marches one ray (unit `direction`) under `quality`. Always ends within `cap(quality)` evaluations.
    public static func march(origin: SIMD3<Float>, direction: SIMD3<Float>, pose: SignedDistancePose,
                             quality: SignedDistanceQuality) -> SignedDistanceMarch {
        guard let span = bounds(origin: origin, direction: direction) else {
            return SignedDistanceMarch(steps: 0, distance: 0, kind: nil)
        }
        let eps: Float = quality.hitThreshold
        var t: Float = span.entry
        var steps = 0
        for _ in 0..<cap(quality) {
            let s: (distance: Float, kind: SignedDistanceKind) = distance(origin + t * direction, pose: pose)
            steps += 1
            if s.distance < eps { return SignedDistanceMarch(steps: steps, distance: t, kind: s.kind) }
            t += max(s.distance, eps)
            if t > span.exit { break }
        }
        return SignedDistanceMarch(steps: steps, distance: t, kind: nil)
    }

    /// The tetrahedral normal estimate at `p` (unit; (0, 0, −1) when degenerate).
    public static func normal(_ p: SIMD3<Float>, pose: SignedDistancePose) -> SIMD3<Float> {
        let h: Float = normalStep
        let k0 = SIMD3<Float>(1, -1, -1), k1 = SIMD3<Float>(-1, -1, 1), k2 = SIMD3<Float>(-1, 1, -1), k3 = SIMD3<Float>(1, 1, 1)
        var n: SIMD3<Float> = k0 * distance(p + h * k0, pose: pose).distance
        n += k1 * distance(p + h * k1, pose: pose).distance
        n += k2 * distance(p + h * k2, pose: pose).distance
        n += k3 * distance(p + h * k3, pose: pose).distance
        let l: Float = (n * n).sum()
        return l > 1e-20 ? n / l.squareRoot() : SIMD3<Float>(0, 0, -1)
    }

    /// The palette colour at `t` (0…1) from 16 stops (the shader's interpolation).
    public static func paletteColor(_ t: Float, stops: UnsafePointer<LinearColor>) -> LinearColor {
        let position: Float = min(max(t, 0), 1) * 15
        let i: Int = min(Int(position), 14)
        let f: Float = position - Float(i)
        let a: LinearColor = stops[i], b: LinearColor = stops[i + 1]
        return LinearColor(red: a.red + (b.red - a.red) * f, green: a.green + (b.green - a.green) * f,
                           blue: a.blue + (b.blue - a.blue) * f, alpha: 1)
    }

    /// The pixel's colour at gain 1 (linear, 0…1) and its march. `p` as `ray(_:)`; `stops` holds 16 colours.
    public static func shade(_ p: SIMD2<Float>, pose rawPose: SignedDistancePose, quality: SignedDistanceQuality,
                             stops: UnsafePointer<LinearColor>) -> (color: LinearColor, march: SignedDistanceMarch) {
        let pose: SignedDistancePose = rawPose.sanitized()
        let safe = SIMD2<Float>(p.x.isFinite ? p.x : 0, p.y.isFinite ? p.y : 0)
        let r: (origin: SIMD3<Float>, direction: SIMD3<Float>) = ray(safe)
        let m: SignedDistanceMarch = march(origin: r.origin, direction: r.direction, pose: pose, quality: quality)
        guard let kind = m.kind else { return (.opaqueBlack, m) }
        let n: SIMD3<Float> = normal(r.origin + m.distance * r.direction, pose: pose)
        let diffuse: Float = max((n * light).sum(), 0)
        let lit: Float = (ambient + (1 - ambient) * diffuse) * pose.brightness
        let base: LinearColor = paletteColor(kind.paletteT, stops: stops)
        func clean(_ v: Float) -> Float { v.isFinite ? min(max(v, 0), 1) : 0 }
        return (LinearColor(red: clean(base.red * lit), green: clean(base.green * lit), blue: clean(base.blue * lit), alpha: 1), m)
    }

    /// Pixel centre `pixel` (pixel units, rows top first) as `ray`'s offset: over the shorter side, y up.
    public static func offset(pixel: SIMD2<Float>, width: Int, height: Int) -> SIMD2<Float> {
        let size = SIMD2<Float>(Float(max(width, 1)), Float(max(height, 1)))
        let p: SIMD2<Float> = (pixel - 0.5 * size) / min(size.x, size.y)
        return SIMD2<Float>(p.x, -p.y)
    }
}

/// The GPU side of `SignedDistanceScene`: Metal Shading Language authored in this module (no external code; SHD-011).
/// Placed after the noise field's body (uses `NoiseOut` and `NoiseUniforms`).
public enum SignedDistanceShader {
    /// Floats of the mode's own uniform block (buffer 1): step cap, hit threshold, angle, sphere radius.
    public static let uniformFloats = 4

    public static let functions = """

    // VIS-017: signed-distance primitives (matches SignedDistanceScene; the pose arrives sanitized).
    struct SdfUniforms {
        float stepCap;
        float threshold;
        float angle;
        float sphereRadius;
    };

    static float3 vis_sdf_rx(float3 p, float a) {
        float c = cos(a), s = sin(a);
        return float3(p.x, c * p.y - s * p.z, s * p.y + c * p.z);
    }

    static float3 vis_sdf_ry(float3 p, float a) {
        float c = cos(a), s = sin(a);
        return float3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
    }

    static float vis_sdf_box(float3 p, float half_, float rounding) {
        float3 q = abs(p) - float3(half_ - rounding);
        return length(max(q, float3(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0) - rounding;
    }

    // x: distance, y: kind (0 sphere, 1 torus, 2 box).
    static float2 vis_sdf_scene(float3 p, float angle, float radius) {
        float best = length(p) - radius;
        float kind = 0.0;
        float3 tilted = vis_sdf_rx(p, -0.5);
        float3 tp = vis_sdf_ry(tilted, -angle);
        float ring = length(float2(length(tp.xz) - 1.05, tp.y)) - 0.11;
        if (ring < best) { best = ring; kind = 1.0; }
        float3 orbit = vis_sdf_ry(tilted, angle);
        for (int k = 0; k < 4; k++) {
            float a = float(k) * 1.5707964;
            float3 centre = float3(1.6 * cos(a), 0.0, 1.6 * sin(a));
            float d = vis_sdf_box(vis_sdf_rx(orbit - centre, 2.0 * angle), 0.16, 0.03);
            if (d < best) { best = d; kind = 2.0; }
        }
        return float2(best, kind);
    }

    // x: steps, y: ray parameter, z: kind (−1 = background).
    static float3 vis_sdf_march(float3 ro, float3 rd, constant SdfUniforms &s) {
        float b = dot(ro, rd);
        float c = dot(ro, ro) - 4.0;
        float disc = b * b - c;
        if (!(disc > 0.0)) { return float3(0.0, 0.0, -1.0); }
        float root = sqrt(disc);
        float t = max(-b - root, 0.0);
        float exitT = -b + root;
        int cap = clamp(int(s.stepCap), 1, 128);
        float eps = clamp(s.threshold, 0.0001, 0.01);
        int steps = 0;
        for (int i = 0; i < 128; i++) {
            if (i >= cap) { break; }
            float2 d = vis_sdf_scene(ro + t * rd, s.angle, s.sphereRadius);
            steps += 1;
            if (d.x < eps) { return float3(float(steps), t, d.y); }
            t += max(d.x, eps);
            if (t > exitT) { break; }
        }
        return float3(float(steps), t, -1.0);
    }

    static float3 vis_sdf_normal(float3 p, constant SdfUniforms &s) {
        const float h = 0.001;
        float3 k0 = float3(1.0, -1.0, -1.0), k1 = float3(-1.0, -1.0, 1.0), k2 = float3(-1.0, 1.0, -1.0), k3 = float3(1.0);
        float3 n = k0 * vis_sdf_scene(p + h * k0, s.angle, s.sphereRadius).x
                 + k1 * vis_sdf_scene(p + h * k1, s.angle, s.sphereRadius).x
                 + k2 * vis_sdf_scene(p + h * k2, s.angle, s.sphereRadius).x
                 + k3 * vis_sdf_scene(p + h * k3, s.angle, s.sphereRadius).x;
        float l = dot(n, n);
        return l > 1e-20 ? n * rsqrt(l) : float3(0.0, 0.0, -1.0);
    }

    static void vis_sdf_ray(float2 position, float2 size, thread float3 &ro, thread float3 &rd) {
        float2 p = (position - 0.5 * size) / min(size.x, size.y);
        float3 raw = float3(p.x, -p.y, 1.07);
        ro = float3(0.0, 0.0, -4.5);
        rd = raw * rsqrt(max(dot(raw, raw), 1e-12));
    }

    fragment float4 vis_sdf_fragment(NoiseOut in [[stage_in]], constant NoiseUniforms &u [[buffer(0)]],
                                     constant SdfUniforms &s [[buffer(1)]]) {
        float2 size = max(u.size, float2(1.0));
        float3 ro, rd;
        vis_sdf_ray(in.position.xy, size, ro, rd);
        float3 m = vis_sdf_march(ro, rd, s);
        if (m.z < 0.0) { return float4(0.0, 0.0, 0.0, 1.0); }
        float3 n = vis_sdf_normal(ro + m.y * rd, s);
        float diffuse = max(dot(n, normalize(float3(0.5, 0.8, -0.6))), 0.0);
        float lit = (0.15 + 0.85 * diffuse) * u.brightness;
        float t = m.z < 0.5 ? 0.15 : (m.z < 1.5 ? 0.5 : 0.85);
        float position = t * 15.0;
        int i = min(int(position), 14);
        float f = position - float(i);
        float3 c = mix(u.palette[i].rgb, u.palette[i + 1].rgb, f) * lit;
        c = select(c, float3(0.0), isnan(c) || isinf(c));
        return float4(clamp(c, 0.0, 1.0), 1.0);
    }

    // Tests only (VIS-017-D6): the march's step count in red, 1 in green for a hit.
    fragment float4 vis_sdf_steps_fragment(NoiseOut in [[stage_in]], constant NoiseUniforms &u [[buffer(0)]],
                                           constant SdfUniforms &s [[buffer(1)]]) {
        float2 size = max(u.size, float2(1.0));
        float3 ro, rd;
        vis_sdf_ray(in.position.xy, size, ro, rd);
        float3 m = vis_sdf_march(ro, rd, s);
        return float4(m.x, m.z < 0.0 ? 0.0 : 1.0, 0.0, 1.0);
    }
    """
}
