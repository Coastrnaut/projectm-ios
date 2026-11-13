// CircularSpectrumGenerator.swift — the circular spectrum on Metal (VIS-001-R1 to R10, R17;
// research VIS-001-D2 to D4, D7, D8).
//
// Per frame: Reduce-flashing slew → CPU layout for the target's size → luminance gain → tessellate
// into a preallocated vertex buffer → one render pass that clears to the background and draws flat,
// premultiplied triangles. The GPU only passes positions through.
//
// Shaders: `shaderSource` below is compiled once in `init` by the system's Metal compiler
// (`makeLibrary(source:options:)`). It is a constant of this package; nothing is read from a file or
// the network. Build-time `.metal` compilation needs the Metal Toolchain, which the build Mac's
// Xcode 27.2 does not have (ADR-0009 decision 3).
//
// Vertex buffers: three, each sized for 128 bars. A buffer is rewritten only when the command buffer
// that last read it reports completed (or failed); otherwise the frame is skipped. No waiting, no
// completion closures, no allocation in this file's per-frame code (Metal's own command objects
// are the system's). Not Sendable: one thread drives a generator.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal

public final class CircularSpectrumGenerator: TextureGenerator {
    public static let supportedPixelFormats: [MTLPixelFormat] = [.bgra8Unorm_srgb, .rgba16Float]
    static let bufferCount = 3

    public let device: MTLDevice
    public let pixelFormat: MTLPixelFormat
    /// Geometry of the last frame (tests and diagnostics).
    public let layout: CircularSpectrumLayout
    public let limiter = FlashSafetyLimiter()
    /// The Reduce-flashing gain of the last frame (1 when not limited).
    public private(set) var lastGain: Float = 1

    private let pipeline: MTLRenderPipelineState
    private let buffers: [MTLBuffer]
    private var lastReaders: [MTLCommandBuffer?]
    private var next = 0
    private let pass = MTLRenderPassDescriptor()

    public var configuration: CircularSpectrumConfiguration {
        get { layout.configuration }
        set { layout.configuration = newValue }
    }

    public init(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb,
                configuration: CircularSpectrumConfiguration = CircularSpectrumConfiguration()) throws(VisualGeneratorError) {
        guard Self.supportedPixelFormats.contains(pixelFormat) else { throw .unsupportedPixelFormat(pixelFormat.rawValue) }
        self.device = device
        self.pixelFormat = pixelFormat
        layout = CircularSpectrumLayout(configuration: configuration)
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            throw .pipelineUnavailable("shader compile: \(error.localizedDescription)")
        }
        guard let vertex = library.makeFunction(name: "vis_circular_vertex"),
              let fragment = library.makeFunction(name: "vis_circular_fragment") else {
            throw .pipelineUnavailable("shader functions missing")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "VIS-001 circular spectrum"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = pixelFormat
        // Premultiplied "over": correct on the opaque background and on a transparent one (CMP-001).
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        do {
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw .pipelineUnavailable("pipeline: \(error.localizedDescription)")
        }
        let length = CircularSpectrumLayout.maximumVertexCount * MemoryLayout<SpectrumVertex>.stride
        var buffers: [MTLBuffer] = []
        for i in 0..<Self.bufferCount {
            guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
                throw .pipelineUnavailable("vertex buffer \(i)")
            }
            buffer.label = "VIS-001 vertices \(i)"
            buffers.append(buffer)
        }
        self.buffers = buffers
        lastReaders = [MTLCommandBuffer?](repeating: nil, count: Self.bufferCount)
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
    }

    /// A vertex buffer the GPU no longer reads, or nil.
    private func freeBuffer() -> Int? {
        for offset in 0..<Self.bufferCount {
            let i = (next + offset) % Self.bufferCount
            guard let reader = lastReaders[i] else { return i }
            if reader.status == .completed || reader.status == .error { return i }
        }
        return nil
    }

    public func encode(into target: MTLTexture, commandBuffer: MTLCommandBuffer,
                       bands: UnsafeBufferPointer<Float>, context: VisualFrameContext) -> Bool {
        guard target.pixelFormat == pixelFormat, let slot = freeBuffer() else { return false }
        let shown = limiter.limitValues(bands, frameTime: context.frameDuration, enabled: context.reduceFlashing)
        layout.layout(values: shown, width: target.width, height: target.height)
        let parts = layout.luminanceComponents()
        let gain = limiter.gain(barsLuminance: parts.bars, backgroundLuminance: parts.background,
                                frameTime: context.frameDuration, enabled: context.reduceFlashing)
        lastGain = gain
        let buffer = buffers[slot]
        let vertices = buffer.contents().bindMemory(to: SpectrumVertex.self, capacity: CircularSpectrumLayout.maximumVertexCount)
        let count = layout.tessellate(into: vertices, capacity: CircularSpectrumLayout.maximumVertexCount, gain: gain)

        let background = layout.configuration.background
        let attachment = pass.colorAttachments[0]!
        attachment.texture = target
        attachment.clearColor = MTLClearColor(red: Double(background.red), green: Double(background.green),
                                              blue: Double(background.blue), alpha: Double(background.alpha))
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            attachment.texture = nil
            return false
        }
        if count > 0 {
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
        }
        encoder.endEncoding()
        attachment.texture = nil   // do not keep the caller's drawable alive
        lastReaders[slot] = commandBuffer
        next = (slot + 1) % Self.bufferCount
        return true
    }

    /// The shaders, compiled at runtime from this constant (ADR-0009 decision 3). Positions arrive in
    /// normalized device coordinates; colors are linear and premultiplied.
    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct SpectrumVertexIn {
        packed_float2 position;
        packed_float4 color;
    };

    struct SpectrumVertexOut {
        float4 position [[position]];
        float4 color;
    };

    vertex SpectrumVertexOut vis_circular_vertex(uint vid [[vertex_id]],
                                                 const device SpectrumVertexIn *vertices [[buffer(0)]]) {
        SpectrumVertexOut out;
        out.position = float4(float2(vertices[vid].position), 0.0, 1.0);
        out.color = float4(vertices[vid].color);
        return out;
    }

    fragment float4 vis_circular_fragment(SpectrumVertexOut in [[stage_in]]) {
        return in.color;
    }
    """
}
#endif
