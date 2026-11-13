// ProceduralMaterialShaders.swift — every material's Metal code, as one constant authored in this
// module (SHD-001-R7; research SHD-001-D1, D6; ADR-0018).
//
// The build Mac has no Metal Toolchain (ADR-0009 decision 3), so the source is a Swift string
// constant compiled into the app and turned into a GPU library when a material layer is prepared.
// `makeLibrary(device:)` is the module's only library creation and takes only `Self.source`: no
// shader is ever compiled from user text, documents, files or downloads (`MaterialSourceSafetyTests`
// scans this module for that).
//
// Shared rules (research SHD-001-D6): every time-dependent term advances by at most one cycle per
// unit of phase; output is linear color clamped to 0…1 with alpha 1 (opaque, so premultiplied);
// non-finite values become 0. Hashes use fixed constants per material (the seed is part of the
// material), so output is deterministic. Uniform slot i is parameter i of the material's definition
// (ProceduralMaterialCatalog.swift).
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal

enum ProceduralMaterialShaders {
    static let vertexFunction = "mat_fullscreen"

    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct MatOut { float4 position [[position]]; };

    // Matches MaterialUniforms (144 bytes).
    struct MatUniforms {
        float2 size;
        float phase;
        float audio;
        float4 slots[8];
    };

    vertex MatOut mat_fullscreen(uint vid [[vertex_id]]) {
        float2 p = float2(float((vid << 1) & 2), float(vid & 2));
        MatOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return o;
    }

    constant float TAU = 6.2831853;

    // Centered point; the shorter side spans -0.5...0.5.
    static float2 mat_point(MatOut in, constant MatUniforms &u) {
        float2 size = max(u.size, float2(1.0));
        return (in.position.xy - 0.5 * size) / min(size.x, size.y);
    }

    static float4 mat_finish(float3 c) {
        c = select(c, float3(0.0), isnan(c) || isinf(c));
        return float4(clamp(c, 0.0, 1.0), 1.0);
    }

    static float mat_hash(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    static float mat_noise(float2 q) {
        float2 i = floor(q);
        float2 f = fract(q);
        float2 w = f * f * (3.0 - 2.0 * f);
        float a = mat_hash(i);
        float b = mat_hash(i + float2(1.0, 0.0));
        float c = mat_hash(i + float2(0.0, 1.0));
        float d = mat_hash(i + float2(1.0, 1.0));
        return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
    }

    static float mat_fbm(float2 q, int octaves) {
        float sum = 0.0, amp = 0.5, norm = 0.0;
        for (int i = 0; i < 5; i++) {
            if (i >= octaves) break;
            sum += amp * mat_noise(q);
            norm += amp;
            q = q * 2.03 + float2(17.1, 9.2);
            amp *= 0.5;
        }
        return sum / max(norm, 1e-4);
    }

    // Gradient Field: 0 colorA, 1 colorB, 2 speed (turns/s), 3 brightness, 4 audioReactivity.
    fragment float4 mat_gradient(MatOut in [[stage_in]], constant MatUniforms &u [[buffer(0)]]) {
        float2 p = mat_point(in, u);
        float a = TAU * u.phase;
        float t = smoothstep(-0.6, 0.6, dot(p, float2(cos(a), sin(a))));
        float3 c = mix(u.slots[0].rgb, u.slots[1].rgb, t) * u.slots[3].x;
        return mat_finish(c);
    }

    // Plasma: 0 scale, 1 speed, 2 brightness, 3 saturation, 4 audioReactivity.
    fragment float4 mat_plasma(MatOut in [[stage_in]], constant MatUniforms &u [[buffer(0)]]) {
        float2 p = mat_point(in, u);
        float k = TAU * u.slots[0].x;
        float t = TAU * u.phase;
        float v = sin(p.x * k + t) + sin(p.y * k * 0.8 - t) + sin((p.x + p.y) * k * 0.6 + t) + sin(length(p) * k * 1.2 - t);
        // h follows the waves (one cycle per phase cycle); half a palette turn over its range keeps
        // each channel monotonic in h, so color changes no faster than the waves.
        float h = v * 0.125 + 0.5;
        float3 col = 0.5 + 0.5 * cos(TAU * (0.5 * h + float3(0.0, 0.33, 0.67)));
        float l = dot(col, float3(0.2126, 0.7152, 0.0722));
        col = mix(float3(l), col, u.slots[3].x) * u.slots[2].x;
        return mat_finish(col);
    }

    // Noise Flow: 0 scale, 1 speed (cells/s), 2 octaves, 3 tint, 4 brightness, 5 audioReactivity.
    fragment float4 mat_noiseFlow(MatOut in [[stage_in]], constant MatUniforms &u [[buffer(0)]]) {
        float2 p = mat_point(in, u);
        int octaves = clamp(int(u.slots[2].x + 0.5), 1, 5);
        float2 q = p * u.slots[0].x + float2(u.phase, 0.5 * u.phase);
        float w = mat_fbm(q + float2(3.1, 7.7), octaves);
        float n = mat_fbm(q + 0.8 * (w - 0.5), octaves);
        float3 c = u.slots[3].rgb * (0.25 + 0.75 * n) * u.slots[4].x;
        return mat_finish(c);
    }

    // Ring Tunnel: 0 ringDensity, 1 speed (rings/s), 2 contrast, 3 color, 4 brightness, 5 audioReactivity.
    fragment float4 mat_tunnel(MatOut in [[stage_in]], constant MatUniforms &u [[buffer(0)]]) {
        float2 p = mat_point(in, u);
        float r = length(p) * 2.0;
        float wave = 0.5 + 0.5 * cos(TAU * (r * u.slots[0].x - u.phase));
        float contrast = clamp(u.slots[2].x, 0.0, 1.0);
        float v = (1.0 - contrast) + contrast * wave;
        float fade = 0.3 + 0.7 * smoothstep(0.0, 0.2, r);
        float3 c = u.slots[3].rgb * u.slots[4].x * v * fade;
        return mat_finish(c);
    }

    // Starfield: 0 density, 1 speed (half screens/s), 2 starSize, 3 color, 4 brightness, 5 audioReactivity.
    fragment float4 mat_starfield(MatOut in [[stage_in]], constant MatUniforms &u [[buffer(0)]]) {
        float2 p = mat_point(in, u);
        float density = u.slots[0].x;
        float size = clamp(u.slots[2].x, 0.1, 0.9);
        float acc = 0.0;
        for (int layer = 0; layer < 3; layer++) {
            float L = float(layer);
            float cells = 8.0 + 7.0 * L;
            float layerSpeed = 1.0 - 0.3 * L;
            float depth = 1.0 - 0.25 * L;
            float2 q = p * cells + float2(u.phase * 0.5 * layerSpeed * cells, 0.0) + float2(31.7 * L, 11.3 * L);
            float2 cell = floor(q);
            float2 f = q - cell;
            if (mat_hash(cell + 0.37 * L) < density) {
                float2 jitter = float2(mat_hash(cell + 3.1), mat_hash(cell + 7.3)) - 0.5;
                float2 center = 0.5 + jitter * (1.0 - size);
                float radius = 0.5 * size;
                float d = length(f - center);
                acc += (1.0 - smoothstep(0.0, radius, d)) * depth * (0.5 + 0.5 * mat_hash(cell + 11.9));
            }
        }
        float3 c = u.slots[3].rgb * u.slots[4].x * min(acc, 1.0);
        return mat_finish(c);
    }
    """

    /// The module's only library creation: `source` above, with safe math (`isnan`/`isinf`).
    static func makeLibrary(device: MTLDevice) throws(LayerSourceError) -> MTLLibrary {
        let options = MTLCompileOptions()
        options.mathMode = .safe
        do {
            return try device.makeLibrary(source: Self.source, options: options)
        } catch {
            throw .resourceUnavailable("material shaders: \(error.localizedDescription)")
        }
    }
}

/// Matches `MatUniforms` in the shader (144 bytes).
struct MaterialUniforms {
    var size: SIMD2<Float>
    var phase: Float
    var audio: Float
    var s0, s1, s2, s3, s4, s5, s6, s7: SIMD4<Float>

    init(width: Int, height: Int, phase: Double, audio: Double, values: MaterialParameterValues) {
        size = SIMD2(Float(max(width, 1)), Float(max(height, 1)))
        self.phase = Float(phase)
        self.audio = Float(audio)
        s0 = values.slot(0); s1 = values.slot(1); s2 = values.slot(2); s3 = values.slot(3)
        s4 = values.slot(4); s5 = values.slot(5); s6 = values.slot(6); s7 = values.slot(7)
    }
}
#endif
