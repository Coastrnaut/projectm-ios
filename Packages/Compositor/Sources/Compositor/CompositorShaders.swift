// CompositorShaders.swift — the compositor's Metal shaders as a Swift constant, compiled at run
// time with safe math (ADR-0009 decision 3: this Mac's Xcode has no Metal toolchain; `isnan`/`isinf`
// need safe math). CMP-001-R9, R10; research CMP-001-D2, D4.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal

enum CompositorShaders {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    // A full-screen triangle from the vertex index; no vertex buffer.
    struct FullScreenOut { float4 position [[position]]; };

    vertex FullScreenOut cmp_fullscreen(uint vid [[vertex_id]]) {
        float2 p = float2(float((vid << 1) & 2), float(vid & 2));
        FullScreenOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return o;
    }

    // One layer picture, same size as the target, drawn with premultiplied "over" blending
    // (one, oneMinusSourceAlpha). Non-finite channels read 0, color is clamped to >= 0 and alpha to
    // 0...1, so a broken layer cannot poison the composite. CMP-003: every channel × the layer's
    // opacity (0...1; × 1.0 is exact, so opacity 1 is bit-identical to CMP-002).
    fragment float4 cmp_over(FullScreenOut in [[stage_in]], texture2d<float, access::read> picture [[texture(0)]],
                             constant float &opacity [[buffer(0)]]) {
        float4 c = picture.read(uint2(in.position.xy));
        c = select(c, float4(0.0), isnan(c) || isinf(c));
        c.a = clamp(c.a, 0.0, 1.0);
        c.rgb = max(c.rgb, float3(0.0));
        return c * clamp(opacity, 0.0, 1.0);
    }

    // CMP-005: a transformed layer. `row0`, `row1` (xyz) are the inverse placement matrix in pixels:
    // output pixel centre → layer pixel. Bilinear sample; outside the picture reads (0, 0, 0, 0),
    // transparent in premultiplied alpha. Then sanitized and × opacity (`params.x`) as `cmp_over`.
    // Identity transforms never come here (they keep the exact per-pixel `cmp_over`).
    struct CMPTransformedDraw { float4 row0; float4 row1; float4 params; };

    fragment float4 cmp_over_transformed(FullScreenOut in [[stage_in]], texture2d<float, access::sample> picture [[texture(0)]],
                                         constant CMPTransformedDraw &d [[buffer(0)]]) {
        constexpr sampler bilinear(coord::normalized, address::clamp_to_zero, filter::linear);
        float3 p = float3(in.position.xy, 1.0);
        float2 src = float2(dot(d.row0.xyz, p), dot(d.row1.xyz, p));
        float2 size = float2(float(picture.get_width()), float(picture.get_height()));
        float4 c = picture.sample(bilinear, src / size);
        c = select(c, float4(0.0), isnan(c) || isinf(c));
        c.a = clamp(c.a, 0.0, 1.0);
        c.rgb = max(c.rgb, float3(0.0));
        return c * clamp(d.params.x, 0.0, 1.0);
    }

    // CMP-007: shape masks (contracts/shape-masks.md in specs/104). The same steps as
    // `LayerMaskGeometry` (CPU reference) from the same numbers: `rot` = (cos, sin, centre x, centre y)
    // in layer pixels, `shape` = (kind 1 ellipse / 2 rectangle / 3 polygon, half width, half height,
    // corner radius), `edge` = (band, inverted, point count, 0), points in local pixels. Kind 0: no mask.
    // CMP-008 (contracts/gradient-masks.md in specs/207): `grad` = (kind 1 linear / 2 radial, stop count, 0, 0),
    // `axis` = linear (start x, y, end x, y) / radial (centre x, y, radius, 0) in layer pixels, `stops` =
    // (position, alpha). Kind 0: no gradient. The same steps as `LayerGradientGeometry`.
    struct CMPMask { float4 rot; float4 shape; float4 edge; float2 points[32]; float4 grad; float4 axis; float2 stops[8]; };

    static float cmp_mask_distance(constant CMPMask &m, float2 p) {
        float2 dp = p - m.rot.zw;
        float2 q = float2(m.rot.x * dp.x + m.rot.y * dp.y, m.rot.x * dp.y - m.rot.y * dp.x);
        int kind = int(m.shape.x + 0.5);
        float2 h = m.shape.yz;
        if (kind == 1) {
            float2 u = q / h;
            float2 v = u / h;
            float k0 = length(u);
            float k1 = length(v);
            if (!(k1 > 0.0)) return -min(h.x, h.y);
            return k0 * (k0 - 1.0) / k1;
        }
        if (kind == 2) {
            float r = m.shape.w;
            float2 a = abs(q) - h + r;
            return length(max(a, float2(0.0))) + min(max(a.x, a.y), 0.0) - r;
        }
        int n = clamp(int(m.edge.z + 0.5), 0, 32);
        if (n < 3) return 1.0e30;
        float2 f = q - m.points[0];
        float best = dot(f, f);
        float s = 1.0;
        for (int i = 0, j = n - 1; i < n; j = i, i++) {
            float2 e = m.points[j] - m.points[i];
            float2 w = q - m.points[i];
            float ee = dot(e, e);
            float along = ee > 0.0 ? clamp(dot(w, e) / ee, 0.0, 1.0) : 0.0;
            float2 b = w - e * along;
            best = min(best, dot(b, b));
            bool c1 = q.y >= m.points[i].y;
            bool c2 = q.y < m.points[j].y;
            bool c3 = e.x * w.y > e.y * w.x;
            if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) s = -s;
        }
        return s * sqrt(best);
    }

    // CMP-008: piecewise-linear alpha between sorted stops, clamped outside; monotonic between adjacent stops.
    static float cmp_gradient_alpha(constant CMPMask &m, float2 p) {
        int kind = int(m.grad.x + 0.5);
        int n = clamp(int(m.grad.y + 0.5), 0, 8);
        if (kind == 0 || n < 1) return 1.0;
        float t;
        if (kind == 2) {
            t = length(p - m.axis.xy) / m.axis.z;
        } else {
            float2 e = m.axis.zw - m.axis.xy;
            t = dot(p - m.axis.xy, e) / dot(e, e);
        }
        float a = m.stops[0].y;
        for (int i = 1; i < n; i++) {
            float2 previous = m.stops[i - 1];
            float2 next = m.stops[i];
            if (t >= next.x) { a = next.y; continue; }
            if (t > previous.x) {
                float f = (t - previous.x) / (next.x - previous.x);
                a = previous.y + (next.y - previous.y) * f;
            }
            break;
        }
        return a;
    }

    // Shape: exactly 0 at distance >= band/2, exactly 1 at <= -band/2 (swapped when inverted); shape kind 0
    // (CMP-008: a gradient alone) gives 1. Times the gradient's alpha (1 without a gradient).
    static float cmp_mask_coverage(constant CMPMask &m, float2 p) {
        float c = 1.0;
        if (m.shape.x > 0.5) {
            float w = m.edge.x;
            float t = clamp((0.5 * w - cmp_mask_distance(m, p)) / w, 0.0, 1.0);
            float s = t * t * (3.0 - 2.0 * t);
            c = m.edge.y > 0.5 ? 1.0 - s : s;
        }
        if (m.grad.x > 0.5) c *= cmp_gradient_alpha(m, p);
        return c;
    }

    // CMP-007: a normal-mode masked layer, drawn in the open "over" pass (fixed-function blending, no
    // extra pass). `d` as CMPTransformedDraw: params.x opacity, params.y 1 for a transformed layer
    // (sampled as `cmp_over_transformed`), else read per pixel as `cmp_over`. The mask is evaluated at
    // the layer pixel (the inverse-mapped position), so it moves with the layer.
    fragment float4 cmp_over_masked(FullScreenOut in [[stage_in]], texture2d<float, access::sample> picture [[texture(0)]],
                                    constant CMPTransformedDraw &d [[buffer(0)]], constant CMPMask &m [[buffer(1)]]) {
        float2 layerPixel = in.position.xy;
        float4 c;
        if (d.params.y > 0.5) {
            constexpr sampler bilinear(coord::normalized, address::clamp_to_zero, filter::linear);
            float3 p = float3(in.position.xy, 1.0);
            layerPixel = float2(dot(d.row0.xyz, p), dot(d.row1.xyz, p));
            float2 size = float2(float(picture.get_width()), float(picture.get_height()));
            c = picture.sample(bilinear, layerPixel / size);
        } else {
            c = picture.read(uint2(in.position.xy));
        }
        c = select(c, float4(0.0), isnan(c) || isinf(c));
        c.a = clamp(c.a, 0.0, 1.0);
        c.rgb = max(c.rgb, float3(0.0));
        return c * clamp(d.params.x, 0.0, 1.0) * cmp_mask_coverage(m, layerPixel);
    }

    // CMP-004: a layer with a blend mode other than normal (contracts/blend-modes.md in specs/099,
    // ADR-0037). Written without fixed-function blending into the other composite texture: reads the
    // backdrop (the composite so far) and the picture (identity: per-pixel read; transformed: as
    // `cmp_over_transformed`), sanitizes and × opacity as `cmp_over`, then
    //   B on sRGB-encoded straight colours clamped to 0…1, decoded to linear, and
    //   co = cs·(1 − αb) + cb·(1 − αs) + αs·αb·B, αo = αs + αb·(1 − αs).
    // `params`: x opacity, y 1 for a transformed layer, z the mode (1 add, 2 screen, 3 multiply,
    // 4 overlay, 5 difference; 0 normal for completeness). Same steps as `LayerBlend` (CPU reference).
    struct CMPBlendDraw { float4 row0; float4 row1; float4 params; };

    static float cmp_encode(float x) {
        x = clamp(x, 0.0, 1.0);
        return x <= 0.0031308 ? x * 12.92 : 1.055 * pow(x, 1.0 / 2.4) - 0.055;
    }

    static float cmp_decode(float y) {
        y = clamp(y, 0.0, 1.0);
        return y <= 0.04045 ? y / 12.92 : pow((y + 0.055) / 1.055, 2.4);
    }

    static float cmp_screen(float a, float b) { return a + b - a * b; }

    static float cmp_function(int mode, float cb, float cs) {
        switch (mode) {
        case 1: return min(cb + cs, 1.0);
        case 2: return cmp_screen(cb, cs);
        case 3: return cb * cs;
        case 4: return cb <= 0.5 ? 2.0 * cb * cs : cmp_screen(cs, 2.0 * cb - 1.0);
        case 5: return abs(cb - cs);
        default: return cs;
        }
    }

    fragment float4 cmp_blend(FullScreenOut in [[stage_in]], texture2d<float, access::sample> picture [[texture(0)]],
                              texture2d<float, access::read> backdrop [[texture(1)]],
                              constant CMPBlendDraw &d [[buffer(0)]], constant CMPMask &m [[buffer(1)]]) {
        uint2 pixel = uint2(in.position.xy);
        float2 layerPixel = in.position.xy;   // CMP-007: where the mask is evaluated
        float4 c;
        if (d.params.y > 0.5) {
            constexpr sampler bilinear(coord::normalized, address::clamp_to_zero, filter::linear);
            float3 p = float3(in.position.xy, 1.0);
            float2 src = float2(dot(d.row0.xyz, p), dot(d.row1.xyz, p));
            float2 size = float2(float(picture.get_width()), float(picture.get_height()));
            c = picture.sample(bilinear, src / size);
            layerPixel = src;
        } else {
            c = picture.read(pixel);
        }
        c = select(c, float4(0.0), isnan(c) || isinf(c));
        c.a = clamp(c.a, 0.0, 1.0);
        c.rgb = max(c.rgb, float3(0.0));
        float4 s = c * clamp(d.params.x, 0.0, 1.0);
        if (m.shape.x > 0.5 || m.grad.x > 0.5) s *= cmp_mask_coverage(m, layerPixel);   // CMP-007, CMP-008; none leaves s untouched
        float4 b = backdrop.read(pixel);
        int mode = int(d.params.z + 0.5);
        float both = s.a * b.a;
        float4 o = float4(0.0);
        for (int i = 0; i < 3; i++) {
            float sb = b.a > 0.0 ? b[i] / b.a : 0.0;
            float ss = s.a > 0.0 ? s[i] / s.a : 0.0;
            float blended = cmp_decode(cmp_function(mode, cmp_encode(sb), cmp_encode(ss)));
            o[i] = s[i] * (1.0 - b.a) + b[i] * (1.0 - s.a) + both * blended;
        }
        o.a = s.a + b.a * (1.0 - s.a);
        return o;
    }

    \(displaySource)
    // FX-002 (ADR-0047), FX-003: the displayed composite (graded, then tone-mapped; `cmp_display`) times the flash
    // guard's gain (RGB only; never brightens). The guard measured the same `cmp_display` values with the same grade,
    // so the gain applies to what it judged. The output's format does the encoding (sRGB for the screen).
    // `nonFinite` counts composite pixels with a NaN or infinite channel (the screen pass binds the compositor's
    // counter, recording and capture a sink; FX-002-R7). `grade`: FX-003's coefficients (flags 0 = bypass).
    fragment float4 cmp_output(FullScreenOut in [[stage_in]], texture2d<float, access::read> composite [[texture(0)]],
                               device const float *gain [[buffer(0)]], device atomic_uint *nonFinite [[buffer(1)]],
                               constant CMPGrade &grade [[buffer(2)]]) {
        float4 c = composite.read(uint2(in.position.xy));
        if (any(isnan(c) || isinf(c))) atomic_fetch_add_explicit(nonFinite, 1u, memory_order_relaxed);
        float4 t = cmp_display(c, grade);
        float g = clamp(gain[0], 0.0, 1.0);
        return float4(t.rgb * g, t.a);
    }
    """

    /// FX-002 (contracts/tone-map.md in specs/122, research FX-002-D1; ADR-0047): the output tone map, the same
    /// steps as `ToneMap.map` (CPU reference). Spliced into `source` and into the composite flash guard's
    /// source, so the guard measures exactly what the output pass shows. Needs safe math (`isnan`/`isinf`).
    ///   1. NaN/±Inf/negative colour → 0; alpha NaN/±Inf → 0, clamped to 0…1;
    ///   2. max channel m ≤ 1: unchanged; 3. luminance Y ≥ 1: white;
    ///   4. else rgb = clamp(Y + (1 − Y)/(m − Y)·(c − Y), 0, 1), computed as 1 − k·(m − c) with k = (1 − Y)/(m − Y)
    ///      (luminance and hue kept, desaturated; the largest channel exactly 1).
    static let toneMapSource = """
    static float4 cmp_tone_map(float4 c) {
        float4 s = select(c, float4(0.0), isnan(c) || isinf(c));
        s = max(s, float4(0.0));
        s.a = min(s.a, 1.0);
        float m = max(s.r, max(s.g, s.b));
        if (m <= 1.0) return s;
        float y = dot(s.rgb, float3(0.2126, 0.7152, 0.0722));
        if (y >= 1.0) return float4(1.0, 1.0, 1.0, s.a);
        float k = (1.0 - y) / (m - y);
        // y + k·(c − y) written as 1 − k·(m − c): the same value, but exactly 1 for the largest channel, so float
        // rounding cannot dip it below the identity branch's 1 (the order across the m = 1 boundary).
        return float4(clamp(1.0 - k * (m - s.rgb), 0.0, 1.0), s.a);
    }
    """

    /// FX-003 (contracts/color-grade.md in specs/123, research FX-003-D2 to D5): the colour grade, the same steps
    /// as `ColorGradeCoefficients.apply` (CPU reference), then FX-002's tone map. Spliced into `source` and into the
    /// composite flash guard's source, so the guard measures exactly what the output pass shows.
    ///   flags 0 (every control neutral): the pixel is returned untouched, so `cmp_tone_map` sees the ungraded input
    ///   (bypass, bit for bit); else sanitise (NaN/±Inf → 0, colour ≥ 0, alpha 0…1), then temperature (× balance),
    ///   lift (max(v·scale + offset, 0)), gamma (v^exponent), gain (× gain), saturation (around Rec. 709 luminance),
    ///   FX-004 hue (`ColorGradeCoefficients.rotateHue`: the differences (r − g, b − g) times `hue` as a 2 × 2 matrix,
    ///   rebuilt around the luminance g + wR·d1 + wB·d2, which is exact for greys; negative results pulled to grey).
    static let displaySource = """
    struct CMPGrade { float4 balance; float4 tone; float4 hue; float saturation; uint flags; uint pad0; uint pad1; };

    \(toneMapSource)
    static float4 cmp_grade(float4 c, constant CMPGrade &g) {
        if (g.flags == 0u) return c;
        float4 s = select(c, float4(0.0), isnan(c) || isinf(c));
        float3 v = max(s.rgb, float3(0.0));
        float a = clamp(s.a, 0.0, 1.0);
        if ((g.flags & 1u) != 0u) v *= g.balance.rgb;
        if ((g.flags & 2u) != 0u) v = max(v * g.tone.x + g.tone.y, float3(0.0));
        if ((g.flags & 4u) != 0u) v = select(pow(v, float3(g.tone.z)), float3(0.0), v <= 0.0);
        if ((g.flags & 8u) != 0u) v *= g.tone.w;
        if ((g.flags & 16u) != 0u) {
            float y = dot(v, float3(0.2126, 0.7152, 0.0722));
            v = max(y + g.saturation * (v - y), float3(0.0));
        }
        if ((g.flags & 32u) != 0u) {
            float d1 = v.r - v.g;
            float d2 = v.b - v.g;
            float y = v.g + 0.2126 * d1 + 0.0722 * d2;
            float e1 = g.hue.x * d1 + g.hue.y * d2;
            float e2 = g.hue.z * d1 + g.hue.w * d2;
            float gg = y - 0.2126 * e1 - 0.0722 * e2;
            v = float3(gg + e1, gg, gg + e2);
            float m = min(v.r, min(v.g, v.b));
            if (m < 0.0) v = y > 0.0 ? max(y + (y / (y - m)) * (v - y), float3(0.0)) : float3(0.0);
        }
        return float4(v, a);
    }

    static float4 cmp_display(float4 c, constant CMPGrade &g) { return cmp_tone_map(cmp_grade(c, g)); }
    """

    /// FX-003: `CMPGrade` in the shader (64 bytes since FX-004's `hue`, copied by `setFragmentBytes` / `setBytes`;
    /// research FX-003-D4, FX-004-D5).
    struct GradeBlock: Equatable {
        var balance: SIMD4<Float>
        /// (lift scale, lift offset, exponent, gain).
        var tone: SIMD4<Float>
        /// FX-004: T(θ) (T00, T01, T10, T11).
        var hue: SIMD4<Float>
        var saturation: Float
        var flags: UInt32
        var pad0: UInt32 = 0
        var pad1: UInt32 = 0

        /// Flags 0: `cmp_grade` returns its input (bypass).
        static let neutral = GradeBlock(ColorGrade.neutral.coefficients)

        /// The coefficients rounded to `Float`.
        init(_ k: ColorGradeCoefficients) {
            balance = SIMD4<Float>(Float(k.balance.x), Float(k.balance.y), Float(k.balance.z), 0)
            tone = SIMD4<Float>(Float(k.liftScale), Float(k.liftOffset), Float(k.exponent), Float(k.gain))
            hue = SIMD4<Float>(Float(k.hueMatrix.x), Float(k.hueMatrix.y), Float(k.hueMatrix.z), Float(k.hueMatrix.w))
            saturation = Float(k.saturation)
            flags = k.flags
        }
    }

    /// CMP-007: `CMPMask` in the shader (400 bytes since CMP-008, copied by `setFragmentBytes`; research
    /// CMP-007-D3, CMP-008-D3).
    struct MaskBlock {
        var rot: SIMD4<Float> = .zero
        var shape: SIMD4<Float> = .zero
        var edge: SIMD4<Float> = .zero
        // 32 float2 points, two per SIMD4.
        var points: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
                     SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
                     SIMD4<Float>, SIMD4<Float>) = (.zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
                                                    .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero)
        /// CMP-008: (kind, stop count, 0, 0), the axis in pixels, 8 float2 stops (two per SIMD4).
        var grad: SIMD4<Float> = .zero
        var axis: SIMD4<Float> = .zero
        var stops: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) = (.zero, .zero, .zero, .zero)

        /// Kind 0: no mask (`cmp_blend` leaves the source untouched).
        static let none = MaskBlock()

        /// A shape, a gradient or both (CMP-008); nil leaves that part's kind 0.
        init(shape: LayerMaskGeometry?, gradient: LayerGradientGeometry?) {
            if let shape { self.init(shape) } else { self.init() }
            if let gradient { setGradient(gradient) }
        }

        private mutating func setGradient(_ g: LayerGradientGeometry) {
            let count: Int = min(g.stops.count, LayerGradientMask.maximumStops)
            grad = SIMD4<Float>(Float(g.kind), Float(count), 0, 0)
            axis = SIMD4<Float>(Float(g.axis.0), Float(g.axis.1), Float(g.axis.2), Float(g.axis.3))
            withUnsafeMutableBytes(of: &stops) { (raw: UnsafeMutableRawBufferPointer) in
                let floats = raw.bindMemory(to: Float.self)
                for k in 0..<count {
                    floats[2 * k] = Float(g.stops[k].position)
                    floats[2 * k + 1] = Float(g.stops[k].alpha)
                }
            }
        }

        /// The block for `geometry` (the CPU reference's numbers, rounded to `Float`).
        init(_ geometry: LayerMaskGeometry) {
            rot = SIMD4<Float>(Float(geometry.cosine), Float(geometry.sine), Float(geometry.centerX), Float(geometry.centerY))
            shape = SIMD4<Float>(Float(geometry.kind), Float(geometry.halfWidth), Float(geometry.halfHeight),
                                 Float(geometry.cornerRadius))
            let count: Int = min(geometry.points.count, LayerMask.maximumPolygonPoints)
            edge = SIMD4<Float>(Float(geometry.band), geometry.inverted ? 1 : 0, Float(count), 0)
            withUnsafeMutableBytes(of: &points) { (raw: UnsafeMutableRawBufferPointer) in
                let floats = raw.bindMemory(to: Float.self)
                for k in 0..<count {
                    floats[2 * k] = Float(geometry.points[k].x)
                    floats[2 * k + 1] = Float(geometry.points[k].y)
                }
            }
        }

        private init() {}
    }

    /// `params.z` of `CMPBlendDraw` for a mode (the shader's switch).
    static func shaderIndex(_ mode: LayerBlendMode) -> Float {
        switch mode {
        case .normal: 0
        case .add: 1
        case .screen: 2
        case .multiply: 3
        case .overlay: 4
        case .difference: 5
        }
    }

    static func library(device: MTLDevice, source: String) throws(CompositorError) -> MTLLibrary {
        let options = MTLCompileOptions()
        options.mathMode = .safe
        do {
            return try device.makeLibrary(source: source, options: options)
        } catch {
            throw .pipelineUnavailable("shader compile: \(error.localizedDescription)")
        }
    }

    static func function(_ library: MTLLibrary, _ name: String) throws(CompositorError) -> MTLFunction {
        guard let f = library.makeFunction(name: name) else { throw .pipelineUnavailable("missing function \(name)") }
        return f
    }

    static func pipeline(device: MTLDevice, vertex: MTLFunction, fragment: MTLFunction, format: MTLPixelFormat,
                         blendOver: Bool, label: String) throws(CompositorError) -> MTLRenderPipelineState {
        let d = MTLRenderPipelineDescriptor()
        d.label = label
        d.vertexFunction = vertex
        d.fragmentFunction = fragment
        d.colorAttachments[0].pixelFormat = format
        if blendOver {
            let a = d.colorAttachments[0]!
            a.isBlendingEnabled = true
            a.rgbBlendOperation = .add
            a.alphaBlendOperation = .add
            a.sourceRGBBlendFactor = .one
            a.sourceAlphaBlendFactor = .one
            a.destinationRGBBlendFactor = .oneMinusSourceAlpha
            a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        do {
            return try device.makeRenderPipelineState(descriptor: d)
        } catch {
            throw .pipelineUnavailable("\(label): \(error.localizedDescription)")
        }
    }
}
#endif
