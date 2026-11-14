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
                              constant CMPBlendDraw &d [[buffer(0)]]) {
        uint2 pixel = uint2(in.position.xy);
        float4 c;
        if (d.params.y > 0.5) {
            constexpr sampler bilinear(coord::normalized, address::clamp_to_zero, filter::linear);
            float3 p = float3(in.position.xy, 1.0);
            float2 src = float2(dot(d.row0.xyz, p), dot(d.row1.xyz, p));
            float2 size = float2(float(picture.get_width()), float(picture.get_height()));
            c = picture.sample(bilinear, src / size);
        } else {
            c = picture.read(pixel);
        }
        c = select(c, float4(0.0), isnan(c) || isinf(c));
        c.a = clamp(c.a, 0.0, 1.0);
        c.rgb = max(c.rgb, float3(0.0));
        float4 s = c * clamp(d.params.x, 0.0, 1.0);
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

    // The composite times the flash guard's gain (RGB only; never brightens). The output's format
    // does the encoding (sRGB for the screen).
    fragment float4 cmp_output(FullScreenOut in [[stage_in]], texture2d<float, access::read> composite [[texture(0)]],
                               device const float *gain [[buffer(0)]]) {
        float4 c = composite.read(uint2(in.position.xy));
        float g = clamp(gain[0], 0.0, 1.0);
        return float4(c.rgb * g, c.a);
    }
    """

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
