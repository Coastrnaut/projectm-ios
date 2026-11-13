// GeneratorGraphShaders.swift — the one fixed interpreter that draws every generator graph, as a
// constant authored in this module (SHD-002-R10; research SHD-002-D2; ADR-0018 decision 3).
//
// The fragment function `graph_main` runs the compiled plan for each pixel: at most 64 fixed-size
// instructions read from a buffer, each selecting one pre-written operation by opcode
// (GraphNodeKind.opcode), with operands from 16 four-number registers, literals or the picture
// coordinates. A graph is data for this program; no shader source is ever built from a document,
// and `makeLibrary(device:)` (the module's only library creation) takes only `Self.source`
// (`GraphSourceSafetyTests` scans this module for that).
//
// Shared rules: coordinates are centered with the shorter side spanning −0.5…0.5, clamped to ±2;
// time arrives only as per-instruction terms reduced on the CPU; smoothstep is written out so edge
// order never matters; output is linear color clamped to 0…1 with alpha 1 (opaque, so
// premultiplied), non-finite values become 0. The noise matches SHD-001's value noise and its
// slope bound (GraphRateBound.swift). Each operation's formula is in data-model.md "Node kinds".
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal

enum GeneratorGraphShaders {
    static let vertexFunction = "graph_fullscreen"
    static let fragmentFunction = "graph_main"

    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct GOut { float4 position [[position]]; };

    // Matches GraphInstruction (80 bytes).
    struct GraphInstr {
        uint op;
        uint dst;
        uint sources;
        uint flags;
        float4 a;
        float4 b;
        float4 c;
        float4 k;
    };

    // Matches GraphFrameUniforms (16 bytes).
    struct GraphFrame {
        float2 size;
        float music;
        uint count;
    };

    vertex GOut graph_fullscreen(uint vid [[vertex_id]]) {
        float2 p = float2(float((vid << 1) & 2), float(vid & 2));
        GOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return o;
    }

    constant float TAU = 6.2831853;

    static float g_hash(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    static float g_noise(float2 q) {
        float2 i = floor(q);
        float2 f = fract(q);
        float2 w = f * f * (3.0 - 2.0 * f);
        float a = g_hash(i);
        float b = g_hash(i + float2(1.0, 0.0));
        float c = g_hash(i + float2(0.0, 1.0));
        float d = g_hash(i + float2(1.0, 1.0));
        return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
    }

    static float g_fbm(float2 q, int octaves) {
        float sum = 0.0, amp = 1.0, norm = 0.0;
        for (int i = 0; i < 5; i++) {
            if (i >= octaves) break;
            sum += amp * g_noise(q);
            norm += amp;
            q = q * 2.03 + float2(17.1, 9.2);
            amp *= 0.5;
        }
        return sum / max(norm, 1e-4);
    }

    static float g_smooth(float e0, float e1, float x) {
        float d = e1 - e0;
        float t = clamp((x - e0) / (abs(d) < 1e-6 ? 1e-6 : d), 0.0, 1.0);
        return t * t * (3.0 - 2.0 * t);
    }

    static float3 g_hsv(float h, float s, float v) {
        float3 k = fract(h + float3(0.0, 2.0 / 3.0, 1.0 / 3.0));
        float3 rgb = clamp(abs(k * 6.0 - 3.0) - 1.0, 0.0, 1.0);
        return v * mix(float3(1.0), rgb, s);
    }

    static float4 g_operand(uint slot, GraphInstr I, thread float4 *r, float2 uv) {
        uint src = (I.sources >> (8u * slot)) & 0xFFu;
        float4 lit = slot == 0u ? I.a : (slot == 1u ? I.b : I.c);
        if (src == 0xFFu) return lit;
        if (src == 0xFEu) return float4(uv, 0.0, 0.0);
        float4 v = r[min(src, 15u)];
        if (((I.flags >> slot) & 1u) != 0u) v = clamp(v, float4(lit.x), float4(lit.y));
        return v;
    }

    fragment float4 graph_main(GOut in [[stage_in]], constant GraphFrame &f [[buffer(0)]],
                               const device GraphInstr *plan [[buffer(1)]], constant float4 *terms [[buffer(2)]]) {
        float2 size = max(f.size, float2(1.0));
        float2 uv = clamp((in.position.xy - 0.5 * size) / min(size.x, size.y), -2.0, 2.0);
        float4 r[16];
        for (int i = 0; i < 16; i++) r[i] = float4(0.0);
        float3 result = float3(0.0);
        uint count = min(f.count, 64u);
        for (uint i = 0u; i < count; i++) {
            GraphInstr I = plan[i];
            float4 A = g_operand(0u, I, r, uv);
            float4 B = g_operand(1u, I, r, uv);
            float4 C = g_operand(2u, I, r, uv);
            float4 k = I.k;
            float4 t = terms[i];
            if (I.op == 26u) {                      // output
                result = clamp(A.xyz, 0.0, 1.0) * clamp(k.x, 0.0, 1.0);
                break;
            }
            float4 o = float4(0.0);
            switch (I.op) {
                case 3u: o.x = f.music; break;                                        // musicLevel
                case 4u: o.x = 0.5 + 0.5 * cos(TAU * t.x); break;                     // oscillate
                case 5u: {                                                            // spin
                    float an = TAU * t.x;
                    float cs = cos(an), sn = sin(an);
                    o.xy = float2(cs * A.x - sn * A.y, sn * A.x + cs * A.y);
                    break;
                }
                case 6u: o.xy = A.xy + t.xy; break;                                   // drift
                case 7u: o.xy = A.xy * B.x; break;                                    // scale
                case 8u: {                                                            // rotate
                    float an = TAU * B.x;
                    float cs = cos(an), sn = sin(an);
                    o.xy = float2(cs * A.x - sn * A.y, sn * A.x + cs * A.y);
                    break;
                }
                case 9u: o.xy = A.xy + float2(B.x, C.x); break;                       // translate
                case 10u: o.xy = float2(atan2(A.y, A.x) / TAU + 0.5, length(A.xy)); break;   // polar
                case 11u: o.x = 1.0 - g_smooth(k.x - k.y, k.x + k.y, length(A.xy)); break;  // circle
                case 12u: o.x = 1.0 - g_smooth(k.y - k.z, k.y + k.z, abs(length(A.xy) - k.x)); break; // ring
                case 13u: {                                                           // box
                    float2 d = abs(A.xy) - 0.5 * k.xy;
                    float sd = length(max(d, float2(0.0))) + min(max(d.x, d.y), 0.0);
                    o.x = 1.0 - g_smooth(-k.z, k.z, sd);
                    break;
                }
                case 14u: o.x = g_fbm(A.xy * k.x, clamp(int(k.y + 0.5), 1, 5)); break;   // noise
                case 15u: o.x = A.x + B.x; break;                                     // add
                case 16u: o.x = A.x * B.x; break;                                     // multiply
                case 17u: o.x = clamp(A.x, min(k.x, k.y), max(k.x, k.y)); break;      // clamp
                case 18u: o.x = g_smooth(k.x, k.y, A.x); break;                       // smoothstep
                case 19u: o.x = 0.5 + 0.5 * cos(TAU * k.x * A.x); break;              // wave
                case 20u: o.x = k.x > 0.5 ? A.y : A.x; break;                         // component
                case 21u: o.xyz = mix(B.xyz, C.xyz, clamp(A.x, 0.0, 1.0)); break;     // gradient
                case 22u: o.xyz = 0.5 + 0.5 * cos(TAU * (k.x * A.x + t.x + float3(0.0, 1.0 / 3.0, 2.0 / 3.0))); break; // palette
                case 23u: o.xyz = g_hsv(A.x, clamp(B.x, 0.0, 1.0), clamp(C.x, 0.0, 1.0)); break;   // hsv
                case 24u: o.xyz = mix(A.xyz, B.xyz, clamp(C.x, 0.0, 1.0)); break;     // mixColor
                case 25u: o.xyz = A.xyz * clamp(B.x, 0.0, 1.0); break;                // scaleColor
                default: break;
            }
            r[min(I.dst, 15u)] = o;
        }
        result = select(result, float3(0.0), isnan(result) || isinf(result));
        return float4(clamp(result, 0.0, 1.0), 1.0);
    }
    """

    /// The module's only library creation: `source` above, with safe math (`isnan`/`isinf`).
    static func makeLibrary(device: MTLDevice) throws(LayerSourceError) -> MTLLibrary {
        let options = MTLCompileOptions()
        options.mathMode = .safe
        do {
            return try device.makeLibrary(source: Self.source, options: options)
        } catch {
            throw .resourceUnavailable("generator graph interpreter: \(error.localizedDescription)")
        }
    }
}

/// Matches `GraphFrame` in the shader (16 bytes).
struct GraphFrameUniforms {
    var size: SIMD2<Float>
    var music: Float
    var count: UInt32
}
#endif
