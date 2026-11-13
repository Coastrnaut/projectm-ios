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

    // The composite times the flash guard's gain (RGB only; never brightens). The output's format
    // does the encoding (sRGB for the screen).
    fragment float4 cmp_output(FullScreenOut in [[stage_in]], texture2d<float, access::read> composite [[texture(0)]],
                               device const float *gain [[buffer(0)]]) {
        float4 c = composite.read(uint2(in.position.xy));
        float g = clamp(gain[0], 0.0, 1.0);
        return float4(c.rgb * g, c.a);
    }
    """

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
