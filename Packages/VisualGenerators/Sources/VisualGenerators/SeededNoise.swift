// SeededNoise.swift — SHD-006's seeded lattice noise, shared by the Noise Flow material and the native Noise Field
// (VIS-013-R2; specs/252-vis-013-noise-field, research VIS-013-D1; SHD-006 contract N2).
//
// `SeededNoise` is the CPU mirror: the lattice hash is integer arithmetic (identical on CPU and GPU), the interpolation
// is Float, operation for operation as the GPU functions in `SeededNoiseShader.functions`. ProceduralMaterials'
// `NoiseTextureReference` calls this mirror; the material's shader literal contains `SeededNoiseShader.functions`
// verbatim (pinned by its `SharedNoiseSourceTests`), and VIS-013's generator builds its shader from it. Nothing here
// uses a random number source, the clock or device state. Plain Swift; builds on Linux.

public enum SeededNoise {
    /// The 32-bit finalizer ("lowbias32").
    @inlinable
    public static func mix(_ value: UInt32) -> UInt32 {
        var h: UInt32 = value
        h ^= h >> 16
        h = h &* 0x7FEB_352D
        h ^= h >> 15
        h = h &* 0x846C_A68B
        h ^= h >> 16
        return h
    }

    /// The hash key of one octave of one field (0 = noise, 1/2 = warp x/y).
    @inlinable
    public static func key(seed: UInt32, octave: Int, field: UInt32) -> UInt32 {
        seed | (UInt32(octave) << 16) | (field << 19)
    }

    /// `mat_nhash`: 0…1 (24-bit) for a lattice cell; cells wrap every 4096 per axis.
    @inlinable
    public static func hash(cellX: Int32, cellY: Int32, key: UInt32) -> Float {
        var h: UInt32 = (UInt32(bitPattern: cellX) & 4095) | ((UInt32(bitPattern: cellY) & 4095) << 12)
        h ^= key &* 0x9E37_79B9
        return Float(mix(h) >> 8) * (1.0 / 16_777_216.0)
    }

    /// `mat_snoise`: smooth value noise.
    public static func noise(_ q: SIMD2<Float>, key: UInt32) -> Float {
        let i: SIMD2<Float> = SIMD2(q.x.rounded(.down), q.y.rounded(.down))
        let f: SIMD2<Float> = q - i
        let w: SIMD2<Float> = f * f * (SIMD2<Float>(repeating: 3) - 2 * f)
        let cx: Int32 = Int32(i.x)
        let cy: Int32 = Int32(i.y)
        let a: Float = hash(cellX: cx, cellY: cy, key: key)
        let b: Float = hash(cellX: cx &+ 1, cellY: cy, key: key)
        let d: Float = hash(cellX: cx, cellY: cy &+ 1, key: key)
        let e: Float = hash(cellX: cx &+ 1, cellY: cy &+ 1, key: key)
        let top: Float = a + (b - a) * w.x
        let bottom: Float = d + (e - d) * w.x
        return top + (bottom - top) * w.y
    }

    /// `mat_sfbm`: normalised fBm of 1…8 octaves (amplitude × gain, frequency × lacunarity per octave).
    public static func fbm(_ point: SIMD2<Float>, octaves: Int, lacunarity: Float, gain: Float, seed: UInt32,
                           field: UInt32) -> Float {
        var q: SIMD2<Float> = point
        var sum: Float = 0
        var amplitude: Float = 1
        var norm: Float = 0
        for octave in 0..<min(max(octaves, 1), 8) {
            sum += amplitude * noise(q, key: key(seed: seed, octave: octave, field: field))
            norm += amplitude
            q = q * lacunarity + SIMD2<Float>(17.1, 9.2)
            amplitude *= gain
        }
        return sum / max(norm, 1e-4)
    }

    /// The domain-warped value (0…1) at `q`: two decorrelated fields (1, 2) at `warpFrequency` displace q by
    /// `warpAmount` cells, skipped at amount 0, then field 0 (`mat_noiseFlow`'s body).
    public static func warped(_ q: SIMD2<Float>, octaves: Int, lacunarity: Float, gain: Float, seed: UInt32,
                              warpAmount: Float, warpFrequency: Float) -> Float {
        var p: SIMD2<Float> = q
        if warpAmount > 0 {
            let wq: SIMD2<Float> = q * warpFrequency
            let wx: Float = fbm(wq + SIMD2<Float>(3.1, 7.7), octaves: octaves, lacunarity: lacunarity, gain: gain, seed: seed, field: 1)
            let wy: Float = fbm(wq + SIMD2<Float>(8.3, 2.8), octaves: octaves, lacunarity: lacunarity, gain: gain, seed: seed, field: 2)
            p += warpAmount * (SIMD2<Float>(wx, wy) - 0.5)
        }
        return fbm(p, octaves: octaves, lacunarity: lacunarity, gain: gain, seed: seed, field: 0)
    }

    /// The domain point of pixel centre (x, y) (rows top first) of a `width` × `height` picture: the shorter side spans
    /// −0.5…0.5, times `scale` cells, plus the drift (phase, 0.5 · phase) (`mat_point`).
    public static func domainPoint(x: Float, y: Float, width: Int, height: Int, scale: Float, phase: Float = 0) -> SIMD2<Float> {
        let size: SIMD2<Float> = SIMD2(Float(max(width, 1)), Float(max(height, 1)))
        let position: SIMD2<Float> = SIMD2(x, y)
        let p: SIMD2<Float> = (position - 0.5 * size) / min(size.x, size.y)
        return p * scale + SIMD2<Float>(phase, 0.5 * phase)
    }
}

/// The GPU side of `SeededNoise`: Metal Shading Language functions authored in this module (no external code; SHD-011).
public enum SeededNoiseShader {
    /// `mat_nhash`, `mat_snoise`, `mat_sfbm`, exactly as in the Noise Flow material's shader literal.
    public static let functions = """
    static float mat_nhash(int2 cell, uint key) {
        uint h = (uint(cell.x) & 4095u) | ((uint(cell.y) & 4095u) << 12);
        h ^= key * 0x9E3779B9u;
        h ^= h >> 16;
        h *= 0x7FEB352Du;
        h ^= h >> 15;
        h *= 0x846CA68Bu;
        h ^= h >> 16;
        return float(h >> 8) * (1.0 / 16777216.0);
    }

    static float mat_snoise(float2 q, uint key) {
        float2 i = floor(q);
        float2 f = q - i;
        float2 w = f * f * (3.0 - 2.0 * f);
        int2 c = int2(i);
        float a = mat_nhash(c, key);
        float b = mat_nhash(c + int2(1, 0), key);
        float d = mat_nhash(c + int2(0, 1), key);
        float e = mat_nhash(c + int2(1, 1), key);
        return mix(mix(a, b, w.x), mix(d, e, w.x), w.y);
    }

    // fBm of up to 8 octaves: amplitude × gain and frequency × lacunarity per octave, normalised to 0…1.
    static float mat_sfbm(float2 q, int octaves, float lacunarity, float gain, uint seed, uint field) {
        float sum = 0.0, amp = 1.0, norm = 0.0;
        for (int i = 0; i < 8; i++) {
            if (i >= octaves) break;
            sum += amp * mat_snoise(q, seed | (uint(i) << 16) | (field << 19));
            norm += amp;
            q = q * lacunarity + float2(17.1, 9.2);
            amp *= gain;
        }
        return sum / max(norm, 1e-4);
    }

    """
}
