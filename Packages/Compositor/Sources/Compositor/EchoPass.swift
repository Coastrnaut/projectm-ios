// EchoPass.swift — FX-010 "Echo feedback" on the GPU (specs/297-fx-010-echo-feedback, contracts/echo-feedback.md
// C1 to C4, research FX-010-D1 to D7; ADR-0108).
//
// While Echo is active, per frame: `cmp_echo` writes the shown picture, max(input, Σ w_k × history_k) (only when at
// least one picture is stored; otherwise the input itself is shown, bit for bit), then on a storing frame
// `cmp_echo_capture` writes a 4-sample downsample of the input into the oldest ring slot. Both sources are module
// constants spliced after `CompositorShaders.source` at the compositor's existing reviewed compile site (SHD-011,
// ADR-0024) and listed in `CompositorShaderSources.archived`.
//
// Memory (contract C4): the ring is exactly `EchoFeedback.cap` (4) pooled `rgba16Float` pictures at
// `EchoFeedback.historySize` (≤ 960 × 960), taken from the pool on the first active frame, kept through count, delay
// and fade changes, replaced only when the history size changes, and returned (fenced by the last command buffer)
// when Echo turns inactive and with the compositor; one output picture at the input size is held alongside, like
// FX-006/FX-007's. Per frame only Metal's own command objects are created; the blocks are copied by
// `setFragmentBytes`.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal

final class EchoPass {
    /// `cmp_echo` and `cmp_echo_capture` (the same maths as `EchoFeedback.referencePixel` and `downsample`, with
    /// hardware linear filtering).
    static let source = """

    struct CMPEcho { float4 weights; uint count; uint pad0; uint pad1; uint pad2; };
    struct CMPEchoStore { float2 texel; float2 pad; };

    // FX-010: the echo cap; the loop below never runs more than this many echoes whatever `count` says.
    constant uint cmp_echo_cap = 4;

    // FX-010: a stored sample never holds NaN/±Inf or negatives, and its alpha stays ≤ 1.
    inline float4 cmp_echo_clean(float4 v) {
        v = select(v, float4(0.0), isnan(v) || isinf(v));
        v = max(v, float4(0.0));
        v.a = min(v.a, 1.0);
        return v;
    }

    // FX-010: one history pixel = the mean of 4 filtered samples at ±1/4 history pixel around its centre (an exact
    // 2 × 2 box at a 2× ratio).
    fragment float4 cmp_echo_capture(FullScreenOut in [[stage_in]], texture2d<float> source [[texture(0)]],
                                     constant CMPEchoStore &s [[buffer(0)]]) {
        constexpr sampler linearClamp(coord::normalized, filter::linear, address::clamp_to_edge);
        float2 uv = in.position.xy * s.texel;
        float2 d = 0.25 * s.texel;
        float4 sum = cmp_echo_clean(source.sample(linearClamp, uv + float2(-d.x, -d.y)));
        sum += cmp_echo_clean(source.sample(linearClamp, uv + float2(d.x, -d.y)));
        sum += cmp_echo_clean(source.sample(linearClamp, uv + float2(-d.x, d.y)));
        sum += cmp_echo_clean(source.sample(linearClamp, uv + float2(d.x, d.y)));
        return sum * 0.25;
    }

    // FX-010: the input, or the weighted stored frames where they are brighter (per channel, premultiplied alpha
    // included). Weights sum to at most 1, so nothing gets brighter than the frames it is made of. A non-finite
    // input pixel passes through (FX-002 then counts it).
    fragment float4 cmp_echo(FullScreenOut in [[stage_in]], texture2d<float, access::read> source [[texture(0)]],
                             array<texture2d<float>, 4> history [[texture(1)]], constant CMPEcho &e [[buffer(0)]]) {
        constexpr sampler linearClamp(coord::normalized, filter::linear, address::clamp_to_edge);
        uint2 p = uint2(in.position.xy);
        float4 c = source.read(p);
        if (any(isnan(c) || isinf(c))) return c;
        float2 uv = (float2(p) + 0.5) / float2(float(source.get_width()), float(source.get_height()));
        float4 echo = float4(0.0);
        uint n = min(e.count, cmp_echo_cap);
        for (uint k = 0; k < n; k++) {
            echo += e.weights[k] * history[k].sample(linearClamp, uv);
        }
        return max(c, echo);
    }
    """

    /// `CMPEcho` (32 bytes).
    struct Block {
        var weights: SIMD4<Float>
        var count: UInt32
        var pad0: UInt32 = 0
        var pad1: UInt32 = 0
        var pad2: UInt32 = 0
    }

    /// `CMPEchoStore` (16 bytes).
    struct StoreBlock {
        var texel: SIMD2<Float>
        var pad: SIMD2<Float> = .zero
    }

    private let echoPipeline: MTLRenderPipelineState
    private let storePipeline: MTLRenderPipelineState
    /// The ring (0 or `EchoFeedback.cap` pictures).
    private(set) var history: [MTLTexture] = []
    private var output: MTLTexture?
    private(set) var schedule = EchoSchedule()
    /// Pictures taken from the pool, echo passes drawn and stores made (tests, diagnostics).
    private(set) var allocations = 0
    private(set) var frames = 0
    private(set) var stores = 0

    init(device: MTLDevice, library: MTLLibrary, vertex: MTLFunction) throws(CompositorError) {
        echoPipeline = try CompositorShaders.pipeline(device: device, vertex: vertex,
                                                      fragment: try CompositorShaders.function(library, "cmp_echo"),
                                                      format: LayerPictureDescriptor.metalPixelFormat, blendOver: false,
                                                      label: "FX-010 echo")
        storePipeline = try CompositorShaders.pipeline(device: device, vertex: vertex,
                                                       fragment: try CompositorShaders.function(library, "cmp_echo_capture"),
                                                       format: LayerPictureDescriptor.metalPixelFormat, blendOver: false,
                                                       label: "FX-010 echo store")
    }

    var holdsPictures: Bool { !history.isEmpty || output != nil }

    /// Empties the history (no echo of earlier content); the next frame stores at once. Pictures are kept.
    func reset() { schedule.reset() }

    /// Every picture back to the pool, reusable once `fence` completed; the history starts empty.
    func release(to pool: TexturePool, after fence: MTLCommandBuffer?) {
        releaseHistory(to: pool, after: fence)
        if let output { pool.recycle(output, after: fence) }
        output = nil
    }

    private func releaseHistory(to pool: TexturePool, after fence: MTLCommandBuffer?) {
        for picture in history { pool.recycle(picture, after: fence) }
        history = []
        schedule.reset()
    }

    /// One pooled picture (an allocation point).
    private func take(width: Int, height: Int, label: String, pool: TexturePool) -> MTLTexture? {
        guard let size = LayerPictureDescriptor(width: width, height: height),
              let made = pool.makeTexture(descriptor: size.textureDescriptor()) else { return nil }
        made.label = label
        allocations += 1
        return made
    }

    /// The ring at the history size for `input` (taken when missing or of another size class).
    private func prepareHistory(for input: MTLTexture, pool: TexturePool, fence: MTLCommandBuffer?) -> Bool {
        guard let size = EchoFeedback.historySize(width: input.width, height: input.height) else { return false }
        if let first = history.first, first.width != size.width || first.height != size.height {
            releaseHistory(to: pool, after: fence)   // a new size class starts empty
        }
        guard history.isEmpty else { return true }
        var ring: [MTLTexture] = []
        for i in 0..<EchoFeedback.cap {
            guard let made = take(width: size.width, height: size.height, label: "FX-010 echo history \(i)", pool: pool) else {
                for picture in ring { pool.recycle(picture, after: fence) }
                return false
            }
            ring.append(made)
        }
        history = ring
        schedule.reset()
        return true
    }

    /// Encodes one frame of Echo on `input`; returns the shown picture (this pass's output, or `input` itself while
    /// nothing is stored), nil when a picture or an encoder cannot be created.
    func encode(input: MTLTexture, echo: EchoFeedback, frameDuration: Double, pool: TexturePool, fence: MTLCommandBuffer?,
                commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard prepareHistory(for: input, pool: pool, fence: fence),
              prepareOutput(like: input, pool: pool, fence: fence) else { return nil }
        let store: Bool = schedule.advance(frameDuration: frameDuration, delay: echo.delaySeconds)
        let weights: [Float] = echo.weights(valid: schedule.valid)
        var shown: MTLTexture = input
        if !weights.isEmpty {
            guard let drawn = encodeEcho(input: input, weights: weights, commandBuffer: commandBuffer) else { return nil }
            shown = drawn
        }
        if store {
            guard encodeStore(input: input, into: history[schedule.nextSlot], commandBuffer: commandBuffer) else { return nil }
            schedule.stored(delay: echo.delaySeconds)
        }
        return shown
    }

    /// The output picture at the input's size, taken with the ring (or when the output size changes).
    private func prepareOutput(like input: MTLTexture, pool: TexturePool, fence: MTLCommandBuffer?) -> Bool {
        if let current = output, current.width != input.width || current.height != input.height {
            pool.recycle(current, after: fence)
            output = nil
        }
        if output == nil { output = take(width: input.width, height: input.height, label: "FX-010 echo", pool: pool) }
        return output != nil
    }

    private func encodeEcho(input: MTLTexture, weights: [Float], commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard let target = output else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.label = "FX-010 echo"
        encoder.setRenderPipelineState(echoPipeline)
        encoder.setFragmentTexture(input, index: 0)
        let slots: [MTLTexture?] = (1...EchoFeedback.cap).map { (k: Int) -> MTLTexture? in history[schedule.slot(echo: k)] }
        encoder.setFragmentTextures(slots, range: 1..<(1 + EchoFeedback.cap))
        var w = SIMD4<Float>(repeating: 0)
        for (k, value) in weights.prefix(EchoFeedback.cap).enumerated() { w[k] = value }
        var block = Block(weights: w, count: UInt32(min(weights.count, EchoFeedback.cap)))
        encoder.setFragmentBytes(&block, length: MemoryLayout<Block>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        frames += 1
        return target
    }

    private func encodeStore(input: MTLTexture, into slot: MTLTexture, commandBuffer: MTLCommandBuffer) -> Bool {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = slot
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        encoder.label = "FX-010 echo store"
        encoder.setRenderPipelineState(storePipeline)
        encoder.setFragmentTexture(input, index: 0)
        var block = StoreBlock(texel: SIMD2<Float>(1 / Float(slot.width), 1 / Float(slot.height)))
        encoder.setFragmentBytes(&block, length: MemoryLayout<StoreBlock>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        stores += 1
        return true
    }
}
#endif
