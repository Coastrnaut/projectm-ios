// NoiseTextureReference.swift — the CPU reference of Noise Flow's seeded noise, and the deterministic seed sequence
// of "Randomize seed" (SHD-006-R2, R6; specs/245-shd-006-noise-editor, research SHD-006-D3, D4, D8; contract N2).
//
// The functions mirror `mat_nhash`, `mat_snoise`, `mat_sfbm`, `mat_noiseFlow` and `mat_noiseFlowLite` in
// ProceduralMaterialShaders.swift operation for operation: the lattice hash is integer arithmetic (identical on CPU
// and GPU), the interpolation is Float. Nothing here uses a random number source, the clock or device state, so the
// same settings always give the same values. Plain Swift; builds on Linux.
import VisualGenerators

/// Noise Flow's noise settings as the shader reads them (clamped the same way).
public struct NoiseTextureSettings: Sendable, Equatable {
    public var seed: UInt32
    public var octaves: Int
    public var lacunarity: Float
    public var gain: Float
    public var warpAmount: Float
    public var warpFrequency: Float
    /// Cells across the shorter side.
    public var scale: Float

    public init(seed: UInt32 = 0, octaves: Int = 3, lacunarity: Float = 2.03, gain: Float = 0.5, warpAmount: Float = 0.8,
                warpFrequency: Float = 1, scale: Float = 4) {
        self.seed = min(seed, 65535)
        self.octaves = min(max(octaves, 1), 8)
        self.lacunarity = min(max(lacunarity, 1.5), 3.5)
        self.gain = min(max(gain, 0.2), 0.8)
        self.warpAmount = min(max(warpAmount, 0), 4)
        self.warpFrequency = min(max(warpFrequency, 0.25), 4)
        self.scale = scale
    }

    /// The settings a Noise Flow layer with `values` draws (slots 0, 2, 6-10).
    public init(values: MaterialParameterValues) {
        let seedValue: Float = min(max(values.slot(6).x, 0), 65535) + 0.5
        self.init(seed: UInt32(seedValue), octaves: Int(values.slot(2).x + 0.5), lacunarity: values.slot(7).x,
                  gain: values.slot(8).x, warpAmount: values.slot(9).x, warpFrequency: values.slot(10).x,
                  scale: values.slot(0).x)
    }
}

public enum NoiseTextureReference {
    // VIS-013-R2: the core lives in VisualGenerators' `SeededNoise` (shared with the native Noise Field); these
    // forward to it so the material's API and values are unchanged.

    /// The 32-bit finalizer ("lowbias32").
    public static func mix(_ value: UInt32) -> UInt32 { SeededNoise.mix(value) }

    /// The hash key of one octave of one field (0 = noise, 1/2 = warp x/y).
    public static func key(seed: UInt32, octave: Int, field: UInt32) -> UInt32 {
        SeededNoise.key(seed: seed, octave: octave, field: field)
    }

    /// `mat_nhash`: 0…1 (24-bit) for a lattice cell; cells wrap every 4096 per axis.
    public static func hash(cellX: Int32, cellY: Int32, key: UInt32) -> Float {
        SeededNoise.hash(cellX: cellX, cellY: cellY, key: key)
    }

    /// `mat_snoise`: smooth value noise.
    public static func noise(_ q: SIMD2<Float>, key: UInt32) -> Float { SeededNoise.noise(q, key: key) }

    /// `mat_sfbm`: normalised fBm.
    public static func fbm(_ point: SIMD2<Float>, settings s: NoiseTextureSettings, octaves: Int, field: UInt32) -> Float {
        SeededNoise.fbm(point, octaves: octaves, lacunarity: s.lacunarity, gain: s.gain, seed: s.seed, field: field)
    }

    /// The noise value n (0…1) at domain point `q` (= point · scale + drift). `lite` is the Low cost variant (no warp,
    /// at most 3 octaves).
    public static func value(at q: SIMD2<Float>, settings s: NoiseTextureSettings, lite: Bool = false) -> Float {
        if lite { return fbm(q, settings: s, octaves: min(s.octaves, 3), field: 0) }
        var warped: SIMD2<Float> = q
        if s.warpAmount > 0 {
            let wq: SIMD2<Float> = q * s.warpFrequency
            let wx: Float = fbm(wq + SIMD2<Float>(3.1, 7.7), settings: s, octaves: s.octaves, field: 1)
            let wy: Float = fbm(wq + SIMD2<Float>(8.3, 2.8), settings: s, octaves: s.octaves, field: 2)
            warped += s.warpAmount * (SIMD2<Float>(wx, wy) - 0.5)
        }
        return fbm(warped, settings: s, octaves: s.octaves, field: 0)
    }

    /// The domain point of pixel (x, y) (rows top first) of a `width` × `height` picture at `phase` (`mat_point`).
    public static func domainPoint(x: Int, y: Int, width: Int, height: Int, scale: Float, phase: Float = 0) -> SIMD2<Float> {
        let size: SIMD2<Float> = SIMD2(Float(max(width, 1)), Float(max(height, 1)))
        let position: SIMD2<Float> = SIMD2(Float(x) + 0.5, Float(y) + 0.5)
        let p: SIMD2<Float> = (position - 0.5 * size) / min(size.x, size.y)
        return p * scale + SIMD2<Float>(phase, 0.5 * phase)
    }

    /// The noise values of a whole picture, rows top first.
    public static func field(width: Int, height: Int, settings s: NoiseTextureSettings, phase: Float = 0,
                             lite: Bool = false) -> [Float] {
        var out: [Float] = []
        out.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                let q: SIMD2<Float> = domainPoint(x: x, y: y, width: width, height: height, scale: s.scale, phase: phase)
                out.append(value(at: q, settings: s, lite: lite))
            }
        }
        return out
    }

    /// High-frequency energy: the mean magnitude of the discrete Laplacian |4v − left − right − up − down| over the
    /// interior (research SHD-006-D6). Smooth (low-frequency) structure contributes almost nothing, finer and stronger
    /// detail raises it.
    public static func highFrequencyEnergy(_ values: [Float], width: Int, height: Int) -> Double {
        guard width > 2, height > 2, values.count == width * height else { return 0 }
        var sum: Double = 0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i: Int = y * width + x
                let around: Float = values[i - 1] + values[i + 1] + values[i - width] + values[i + width]
                sum += Double(abs(4 * values[i] - around))
            }
        }
        return sum / Double((width - 2) * (height - 2))
    }
}

/// "Randomize seed" (research SHD-006-D8): seeds from a counter through the same finalizer, never the current seed.
/// No system random source, so the sequence is the same on every run.
public struct NoiseSeedSequence: Sendable, Equatable {
    public static let seedRange: ClosedRange<Int> = 0...65535

    /// The next counter value used.
    public private(set) var counter: UInt32

    public init(counter: UInt32 = 1) { self.counter = counter }

    /// The next seed that differs from `current`.
    public mutating func next(after current: Int) -> Int {
        while true {
            let seed: Int = Int(NoiseTextureReference.mix(counter) & 0xFFFF)
            counter &+= 1
            if seed != current { return seed }
        }
    }
}
