// FlatShapePass.swift — the Metal pass the native spectra share (VIS-001-R1, R17; VIS-002-R1;
// research VIS-001-D3, VIS-002-D1; ADR-0009 decision 3).
//
// One render pass that clears the target to the background and draws flat, premultiplied
// triangles whose positions arrive in normalized device coordinates. The shader source below is a
// constant of this package compiled once in `init` by the system's Metal compiler
// (`makeLibrary(source:options:)`); nothing is read from a file or the network.
//
// Vertex buffers: three, sized for the generator's maximum. A buffer is rewritten only when the
// command buffer that last read it reports completed (or failed); otherwise the frame is skipped.
// No waiting, no completion closures, no allocation per frame. Not Sendable: one thread.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal

final class FlatShapePass {
    static let supportedPixelFormats: [MTLPixelFormat] = [.bgra8Unorm_srgb, .rgba16Float]
    static let bufferCount = 3

    let pixelFormat: MTLPixelFormat
    let maximumVertexCount: Int
    private let pipeline: MTLRenderPipelineState
    private let buffers: [MTLBuffer]
    private var lastReaders: [MTLCommandBuffer?]
    private var next = 0
    private let pass = MTLRenderPassDescriptor()

    init(device: MTLDevice, pixelFormat: MTLPixelFormat, maximumVertexCount: Int, label: String) throws(VisualGeneratorError) {
        guard Self.supportedPixelFormats.contains(pixelFormat) else { throw .unsupportedPixelFormat(pixelFormat.rawValue) }
        self.pixelFormat = pixelFormat
        self.maximumVertexCount = maximumVertexCount
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            throw .pipelineUnavailable("shader compile: \(error.localizedDescription)")
        }
        guard let vertex = library.makeFunction(name: "vis_flat_vertex"),
              let fragment = library.makeFunction(name: "vis_flat_fragment") else {
            throw .pipelineUnavailable("shader functions missing")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = label
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
        let length = maximumVertexCount * MemoryLayout<SpectrumVertex>.stride
        var buffers: [MTLBuffer] = []
        for i in 0..<Self.bufferCount {
            guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
                throw .pipelineUnavailable("vertex buffer \(i)")
            }
            buffer.label = "\(label) vertices \(i)"
            buffers.append(buffer)
        }
        self.buffers = buffers
        lastReaders = [MTLCommandBuffer?](repeating: nil, count: Self.bufferCount)
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
    }

    /// A vertex buffer the GPU no longer reads, or nil.
    func freeSlot() -> Int? {
        for offset in 0..<Self.bufferCount {
            let i = (next + offset) % Self.bufferCount
            guard let reader = lastReaders[i] else { return i }
            if reader.status == .completed || reader.status == .error { return i }
        }
        return nil
    }

    /// The vertices of `slot` (room for `maximumVertexCount`).
    func vertices(_ slot: Int) -> UnsafeMutablePointer<SpectrumVertex> {
        buffers[slot].contents().bindMemory(to: SpectrumVertex.self, capacity: maximumVertexCount)
    }

    /// Clears `target` to `background` and draws `count` vertices of `slot`. False, encoding
    /// nothing, when no encoder could be made.
    func draw(slot: Int, count: Int, into target: MTLTexture, background: LinearColor, commandBuffer: MTLCommandBuffer) -> Bool {
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
            encoder.setVertexBuffer(buffers[slot], offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
        }
        encoder.endEncoding()
        attachment.texture = nil   // do not keep the caller's drawable alive
        lastReaders[slot] = commandBuffer
        next = (slot + 1) % Self.bufferCount
        return true
    }

    /// Positions arrive in normalized device coordinates; colors are linear and premultiplied.
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

    vertex SpectrumVertexOut vis_flat_vertex(uint vid [[vertex_id]],
                                             const device SpectrumVertexIn *vertices [[buffer(0)]]) {
        SpectrumVertexOut out;
        out.position = float4(float2(vertices[vid].position), 0.0, 1.0);
        out.color = float4(vertices[vid].color);
        return out;
    }

    fragment float4 vis_flat_fragment(SpectrumVertexOut in [[stage_in]]) {
        return in.color;
    }
    """
}
#endif
