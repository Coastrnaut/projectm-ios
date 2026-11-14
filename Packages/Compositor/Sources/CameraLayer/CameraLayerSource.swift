// CameraLayerSource.swift — the camera as a CMP-001 layer (CAM-001-R2, R3, R5, R6, R8, R15; research
// CAM-001-D2, D3, D5; contracts/camera-layer.md "CameraLayerSource").
//
// Per frame: unless the provider is `running` with a picture, `render` throws `.notReady` and the
// compositor shows the transparent fallback — never a frozen picture presented as live. Otherwise one
// render pass clears the layer picture and draws a full-screen triangle that samples the camera
// texture (`.bgra8Unorm_srgb`, so the sampler returns linear light) with aspect fill and the
// picture's rotation; alpha is 1, so the premultiplied picture equals the color. The geometry goes in
// with `setFragmentBytes` (no buffer). When the newest-picture slot is busy this instant, the picture
// used last frame is drawn again (the render never waits). The shader is a Swift constant compiled
// at run time (ADR-0009 decision 3). Not Sendable: the compositor's thread drives it and reads the
// provider's main-thread `state` (the app's compositor runs on the main thread).
// CAM-002: `mirrored` flips the upright camera picture (CameraPictureGeometry, research CAM-002-D1)
// from the next frame; it never touches the camera. A picture is drawn only when its position equals
// the provider's current position (research CAM-002-D3), so a camera switch never shows the old camera.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal

public final class CameraLayerSource: LayerSource {
    public let layerName = "camera"
    public let fallback = LayerFallback.transparent
    public let provider: any CameraFrameProvider
    private var pipeline: MTLRenderPipelineState?
    private var sampler: MTLSamplerState?
    /// The picture drawn last frame (only while running).
    private var held: CameraFrame?
    /// Frames whose own camera picture was drawn (diagnostics, tests).
    public private(set) var framesShown = 0
    /// CAM-002-R3, R5: flip the camera picture left to right (main thread; applies from the next frame).
    public var mirrored = false

    public init(provider: any CameraFrameProvider) {
        self.provider = provider
    }

    /// Starts the camera (user action only: CAM-001-R4, R7).
    public func start() { provider.start() }

    /// Stops the camera and drops the held picture (CAM-001-R7, R9).
    public func stop() {
        held = nil
        provider.stop()
    }

    public func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {
        if pipeline != nil { return }
        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            guard let vertex = library.makeFunction(name: "cam_fullscreen"),
                  let fragment = library.makeFunction(name: "cam_picture") else {
                throw LayerSourceError.resourceUnavailable("camera shader functions")
            }
            let d = MTLRenderPipelineDescriptor()
            d.label = "CAM-001 camera"
            d.vertexFunction = vertex
            d.fragmentFunction = fragment
            d.colorAttachments[0].pixelFormat = LayerPictureDescriptor.metalPixelFormat
            pipeline = try device.makeRenderPipelineState(descriptor: d)
        } catch let error as LayerSourceError {
            throw error
        } catch {
            throw .resourceUnavailable("camera pipeline: \(error)")
        }
        let s = MTLSamplerDescriptor()
        s.minFilter = .linear
        s.magFilter = .linear
        s.sAddressMode = .clampToEdge
        s.tAddressMode = .clampToEdge
        guard let state = device.makeSamplerState(descriptor: s) else {
            pipeline = nil
            throw .resourceUnavailable("camera sampler")
        }
        sampler = state
    }

    public func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                       audio: LayerAudioContext) throws(LayerSourceError) {
        guard provider.state.showsPicture else {
            held = nil
            throw .notReady
        }
        if let newest = provider.latestFrame() { held = newest }
        if let stale = held, stale.position != provider.position { held = nil }   // CAM-002-R7: never the previous camera
        guard let camera = held, let pipeline, let sampler else { throw .notReady }
        let geometry = CameraPictureGeometry(pictureWidth: camera.width, pictureHeight: camera.height, rotation: camera.rotation,
                                             outputWidth: picture.width, outputHeight: picture.height, mirrored: mirrored)
        var uniforms = CameraUniforms(geometry: geometry, outputWidth: picture.width, outputHeight: picture.height)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = picture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { throw .frameSkipped }
        encoder.label = "CAM-001 camera"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(camera.texture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CameraUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        framesShown += 1
    }

    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct CamOut { float4 position [[position]]; };

    vertex CamOut cam_fullscreen(uint vid [[vertex_id]]) {
        float2 p = float2(float((vid << 1) & 2), float(vid & 2));
        CamOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return o;
    }

    struct CamUniforms {
        float2 visible;
        float2 offset;
        float2 outputSize;
        uint rotation;   // quarter turns clockwise to upright
        uint mirror;     // CAM-002: 1 flips the upright picture left to right
    };

    // Output point (0...1, top-left) -> visible part of the upright picture -> camera texture
    // (CameraPictureGeometry.textureCoordinate does the same). The texture is sRGB, so the sample
    // is linear light; alpha 1 makes it premultiplied.
    fragment float4 cam_picture(CamOut in [[stage_in]], texture2d<float> camera [[texture(0)]],
                                sampler s [[sampler(0)]], constant CamUniforms &u [[buffer(0)]]) {
        float2 p = in.position.xy / u.outputSize;
        float2 ab = u.offset + p * u.visible;
        if (u.mirror == 1u) { ab.x = 1.0 - ab.x; }
        float2 t = ab;
        if (u.rotation == 1u) { t = float2(ab.y, 1.0 - ab.x); }
        else if (u.rotation == 2u) { t = float2(1.0 - ab.x, 1.0 - ab.y); }
        else if (u.rotation == 3u) { t = float2(1.0 - ab.y, ab.x); }
        float3 c = camera.sample(s, t).rgb;
        return float4(max(c, float3(0.0)), 1.0);
    }
    """
}

/// Matches `CamUniforms` in the shader (32 bytes; CAM-002's `mirror` took the padding word).
struct CameraUniforms {
    var visible: SIMD2<Float>
    var offset: SIMD2<Float>
    var outputSize: SIMD2<Float>
    var rotation: UInt32
    var mirror: UInt32

    init(geometry: CameraPictureGeometry, outputWidth: Int, outputHeight: Int) {
        visible = SIMD2(geometry.visibleWidth, geometry.visibleHeight)
        offset = SIMD2(geometry.offsetX, geometry.offsetY)
        outputSize = SIMD2(Float(max(outputWidth, 1)), Float(max(outputHeight, 1)))
        rotation = UInt32(geometry.rotation.rawValue / 90)
        mirror = geometry.mirrored ? 1 : 0
    }
}
#endif
