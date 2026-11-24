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
// CAM-007: `crop` (Fill or Fit, anchor, zoom) enters the same per-frame geometry, from the next frame,
// without touching the camera; the geometry is rebuilt every frame from the picture's size and
// rotation and the layer picture's size, so a device rotation keeps the chosen crop. Output points
// outside the picture (Fit's bars) are transparent (CAM-007-R4).
// CAM-005: `drawnPicture` records the size and rotation of the picture drawn last, so a touch can be
// mapped to the camera point under it with the same geometry.
// CAM-008 (contracts/person-mask.md C3, research CAM-008-D2, D3): with `personMaskMode` Person or
// Background, the masker's newest mask (8-bit coverage aligned with the camera picture) is uploaded into
// a small `.r8Unorm` ring (only when a new mask arrived) and multiplied into the coverage: the shader
// samples it where it samples the picture (texture space) or at the upright, unmirrored point (upright
// space), so rotation, mirror and crop follow. Off, an unavailable masker, no mask yet, or a mask of the
// other camera: the Off picture exactly (a 1×1 placeholder is bound, the mask term unused).
// QA-011 D3 (CMP-013 render caching, spec 033 Clarification 2026-11-24): the layer declares itself still between camera
// pictures (`LayerRenderCaching`): content = a generation bumped whenever a new camera picture is taken, parameters = a
// generation bumped by `mirrored`, `crop` and `personMaskMode`. When the camera delivers fewer pictures than the display
// shows frames (the 1280×720 preset keeps AVFoundation's default rate, expected 30 fps, fewer in low light), the
// frames between two pictures reuse the layer picture instead of clearing and redrawing a full-screen rgba16Float
// target (bit-identical: same picture, same geometry). Not running, no picture, or a person mask in use: dynamic (rendered every frame, as before). A reused
// frame still counts in `framesShown` (it shows the camera picture).
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal

public final class CameraLayerSource: LayerSource, LayerRenderCaching {
    public let layerName = "camera"
    public let fallback = LayerFallback.transparent
    public let provider: any CameraFrameProvider
    private var pipeline: MTLRenderPipelineState?
    private var sampler: MTLSamplerState?
    /// The picture drawn last frame (only while running).
    private var held: CameraFrame?
    /// Frames whose own camera picture was drawn (diagnostics, tests).
    public private(set) var framesShown = 0
    /// Pictures dropped because they came from the other camera (CAM-002-R7), each counted once; QA-011 switch diagnosis.
    public private(set) var staleDropped = 0
    /// CAM-002-R3, R5: flip the camera picture left to right (main thread; applies from the next frame).
    public var mirrored = false {
        didSet { if mirrored != oldValue { parameterGeneration &+= 1 } }
    }
    /// CAM-007-R1, R5: the user's crop (main thread; applies from the next frame; never touches the camera).
    public var crop: CameraCrop = .fill {
        didSet { if crop != oldValue { parameterGeneration &+= 1 } }
    }
    /// CAM-005-R2: the camera picture drawn last frame (size and rotation), nil when none is drawn; a
    /// touch is mapped against it (`CameraFocusMapping`). Three integers per frame, no allocation.
    public private(set) var drawnPicture: CameraDrawnPicture?
    /// QA-011 CAM-007-T15/T16: the picture, crop, layer size and geometry drawn last frame (nil when none is drawn),
    /// so a DEBUG probe reports the drawn rectangle from the geometry the shader used. Plain values, no allocation.
    public private(set) var drawnLayout: CameraDrawnLayout?
    /// CAM-008-R1: the user's person mask choice (main thread; from the next frame).
    public var personMaskMode: CameraPersonMaskMode = .off {
        didSet {
            personMasker?.isEnabled = personMaskMode != .off
            if personMaskMode != oldValue { parameterGeneration &+= 1 }
        }
    }
    /// CAM-008: the masker fed by the provider (nil: no masking).
    public var personMasker: PersonMasker? {
        didSet {
            oldValue?.isEnabled = false
            personMasker?.isEnabled = personMaskMode != .off
            provider.personMasker = personMasker
        }
    }
    /// CAM-008: frames drawn with a person mask (tests, diagnostics).
    public private(set) var framesMasked = 0
    private var maskPlaceholder: MTLTexture?
    /// Three textures, so a mask upload never overwrites one a frame still in flight samples.
    private var maskRing: [MTLTexture] = []
    private var maskRingIndex = 0
    private var uploadedMaskSerial: UInt64?
    /// QA-011 D3 (CMP-013): bumped whenever `held` takes a new camera picture.
    private var pictureGeneration: UInt64 = 0
    /// QA-011 D3 (CMP-013): bumped whenever a drawing parameter (mirror, crop, mask mode) changes.
    private var parameterGeneration: UInt64 = 0
    /// QA-011 D3: frames that reused the layer picture of the same camera picture (tests, diagnostics).
    public private(set) var framesReused = 0
    /// The last picture of the other camera counted in `staleDropped`.
    private var lastStaleSequence: UInt64?
    private weak var lastStaleTexture: MTLTexture?

    public init(provider: any CameraFrameProvider) {
        self.provider = provider
    }

    /// Starts the camera (user action only: CAM-001-R4, R7).
    public func start() { provider.start() }

    /// Stops the camera and drops the held picture (CAM-001-R7, R9).
    public func stop() {
        held = nil
        drawnPicture = nil
        drawnLayout = nil
        personMasker?.reset()   // CAM-008-R7
        provider.pictureAnalyzer?.reset()   // CAM-009: values back to neutral
        uploadedMaskSerial = nil
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
        let one = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: 1, height: 1, mipmapped: false)
        one.usage = [.shaderRead]
        guard let placeholder = device.makeTexture(descriptor: one) else { throw .resourceUnavailable("camera mask placeholder") }
        var white: UInt8 = 255
        placeholder.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &white, bytesPerRow: 1)
        maskPlaceholder = placeholder
    }

    /// CAM-008-R2, R5: the mask texture to draw with this frame, or nil (draw the Off picture).
    private func maskTexture(for camera: CameraFrame, device: MTLDevice) -> (MTLTexture, PersonMaskSpace)? {
        guard personMaskMode != .off, let masker = personMasker, masker.availability == .available,
              let mask = masker.latestMask(), mask.position == camera.position else { return nil }
        let bitmap: PersonMaskBitmap = mask.bitmap
        if uploadedMaskSerial == mask.serial, let current = maskRing.indices.contains(maskRingIndex) ? maskRing[maskRingIndex] : nil,
           current.width == bitmap.width, current.height == bitmap.height {
            return (current, bitmap.space)
        }
        if maskRing.first.map({ (t: MTLTexture) -> Bool in t.width != bitmap.width || t.height != bitmap.height }) ?? true {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: bitmap.width, height: bitmap.height, mipmapped: false)
            d.usage = [.shaderRead]
            maskRing = (0..<3).compactMap { (_: Int) -> MTLTexture? in device.makeTexture(descriptor: d) }
            guard maskRing.count == 3 else { maskRing = []; return nil }
            maskRingIndex = 0
        } else {
            maskRingIndex = (maskRingIndex + 1) % maskRing.count
        }
        let target: MTLTexture = maskRing[maskRingIndex]
        bitmap.bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Void in
            target.replace(region: MTLRegionMake2D(0, 0, bitmap.width, bitmap.height), mipmapLevel: 0,
                           withBytes: raw.baseAddress!, bytesPerRow: bitmap.width)
        }
        uploadedMaskSerial = mask.serial
        return (target, bitmap.space)
    }

    /// Takes the provider's newest picture into `held` (a new one bumps `pictureGeneration`) and drops a picture of the
    /// other camera (CAM-002-R7). Never waits: a busy slot keeps the held picture.
    private func takeNewestPicture() {
        if let newest = provider.latestFrame(), newest.sequence != held?.sequence || newest.texture !== held?.texture {
            held = newest
            pictureGeneration &+= 1
        }
        if let stale = held, stale.position != provider.position {   // CAM-002-R7: never the previous camera
            held = nil
            // Counted once per picture (the dependencies and the render both look at it in one frame).
            if stale.sequence != lastStaleSequence || stale.texture !== lastStaleTexture {
                staleDropped += 1
                lastStaleSequence = stale.sequence
                lastStaleTexture = stale.texture
            }
        }
    }

    /// CMP-013: still between camera pictures; dynamic while not running, without a picture or with a person mask.
    /// Takes the newest picture first, so the reported generation is never newer than what `render` draws.
    public var renderDependencies: LayerRenderDependencies {
        guard provider.state.showsPicture else { return .dynamic }
        takeNewestPicture()
        guard held != nil, pipeline != nil, personMaskMode == .off || personMasker == nil else { return .dynamic }
        return .still(content: pictureGeneration, parameters: parameterGeneration)
    }

    /// CMP-013: the layer picture of the held camera picture is shown again; it still shows the camera.
    public func renderReused(frame: LayerFrameContext) {
        framesShown += 1
        framesReused += 1
    }

    public func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                       audio: LayerAudioContext) throws(LayerSourceError) {
        guard provider.state.showsPicture else {
            held = nil
            drawnPicture = nil
            drawnLayout = nil
            throw .notReady
        }
        takeNewestPicture()
        guard let camera = held, let pipeline, let sampler, let maskPlaceholder else {
            drawnPicture = nil
            drawnLayout = nil
            throw .notReady
        }
        let geometry = CameraPictureGeometry(pictureWidth: camera.width, pictureHeight: camera.height, rotation: camera.rotation,
                                             outputWidth: picture.width, outputHeight: picture.height, mirrored: mirrored,
                                             crop: crop)
        var uniforms = CameraUniforms(geometry: geometry, outputWidth: picture.width, outputHeight: picture.height)
        let mask: (texture: MTLTexture, space: PersonMaskSpace)? = maskTexture(for: camera, device: picture.device)
        if let mask {
            uniforms.maskMode = personMaskMode == .person ? 1 : 2
            uniforms.maskSpace = mask.space == .upright ? 1 : 0
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = picture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { throw .frameSkipped }
        encoder.label = "CAM-001 camera"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(camera.texture, index: 0)
        encoder.setFragmentTexture(mask?.texture ?? maskPlaceholder, index: 1)   // CAM-008
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CameraUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        framesShown += 1
        if mask != nil { framesMasked += 1 }
        let drawn = CameraDrawnPicture(width: camera.width, height: camera.height, rotation: camera.rotation)
        drawnPicture = drawn   // CAM-005
        drawnLayout = CameraDrawnLayout(picture: drawn, crop: crop, outputWidth: picture.width, outputHeight: picture.height,
                                        geometry: geometry)   // QA-011 CAM-007-T15/T16
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
        uint maskMode;   // CAM-008: 0 none, 1 person, 2 background
        uint maskSpace;  // CAM-008: 0 camera texture, 1 upright (not mirrored)
    };

    // Output point (0...1, top-left) -> visible part of the upright picture -> camera texture
    // (CameraPictureGeometry.textureCoordinate does the same). The texture is sRGB, so the sample
    // is linear light; alpha 1 makes it premultiplied.
    fragment float4 cam_picture(CamOut in [[stage_in]], texture2d<float> camera [[texture(0)]],
                                texture2d<float> mask [[texture(1)]],
                                sampler s [[sampler(0)]], constant CamUniforms &u [[buffer(0)]]) {
        float2 p = in.position.xy / u.outputSize;
        float2 ab = u.offset + p * u.visible;
        // CAM-007-R4: Fit's bars are transparent (CameraPictureGeometry.contains, same tolerance).
        if (any(ab < float2(-1e-4)) || any(ab > float2(1.0 + 1e-4))) { return float4(0.0); }
        if (u.mirror == 1u) { ab.x = 1.0 - ab.x; }
        float2 t = ab;
        if (u.rotation == 1u) { t = float2(ab.y, 1.0 - ab.x); }
        else if (u.rotation == 2u) { t = float2(1.0 - ab.x, 1.0 - ab.y); }
        else if (u.rotation == 3u) { t = float2(1.0 - ab.y, ab.x); }
        float3 c = max(camera.sample(s, t).rgb, float3(0.0));
        if (u.maskMode == 0u) { return float4(c, 1.0); }
        // CAM-008-R2, R3: the person coverage where the picture is sampled (ab is upright, unmirrored here).
        float m = clamp(mask.sample(s, u.maskSpace == 1u ? ab : t).r, 0.0, 1.0);
        float a = u.maskMode == 1u ? m : 1.0 - m;
        return float4(c * a, a);
    }
    """
}

/// Matches `CamUniforms` in the shader (40 bytes; CAM-002's `mirror` took the padding word, CAM-008 adds
/// the mask mode and space).
struct CameraUniforms {
    var visible: SIMD2<Float>
    var offset: SIMD2<Float>
    var outputSize: SIMD2<Float>
    var rotation: UInt32
    var mirror: UInt32
    var maskMode: UInt32 = 0
    var maskSpace: UInt32 = 0

    init(geometry: CameraPictureGeometry, outputWidth: Int, outputHeight: Int) {
        visible = SIMD2(geometry.visibleWidth, geometry.visibleHeight)
        offset = SIMD2(geometry.offsetX, geometry.offsetY)
        outputSize = SIMD2(Float(max(outputWidth, 1)), Float(max(outputHeight, 1)))
        rotation = UInt32(geometry.rotation.rawValue / 90)
        mirror = geometry.mirrored ? 1 : 0
    }
}
#endif
