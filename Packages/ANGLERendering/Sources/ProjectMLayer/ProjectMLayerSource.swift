// ProjectMLayerSource.swift — projectM as a compositor layer (CMP-001-R13; ADR-0013 decision 7;
// research CMP-001-D5, D8; contracts/layer-source.md "Adapters").
//
// * Its own EGL context (and 1 × 1 placeholder pbuffer) on ANGLE's Metal display, and its own engine.
//   It requires `EGL_ANGLE_metal_texture_client_buffer` and `EGL_ANGLE_metal_shared_event_sync`,
//   checked in the display's extension string at init.
// * `prepare`: a `bgra8Unorm` Metal texture of the picture's size (the layer's own working resource),
//   wrapped as an EGL image (`EGL_METAL_TEXTURE_ANGLE`) and bound to a GL framebuffer; the engine's
//   viewport follows.
// * `render`: feeds PCM (one `NormalizedPCMReader` read, like `ANGLERenderer`), the engine renders
//   into that framebuffer, ANGLE signals an `MTLSharedEvent` (an `EGL_SYNC_METAL_SHARED_EVENT_ANGLE`
//   sync) and flushes; the compositor's command buffer waits for the event on the GPU (no CPU wait),
//   then a pass flips the picture upright (GL row 0 is Metal row 0, research CMP-001-D5), decodes the
//   engine's sRGB-encoded output to linear and writes it opaque into the compositor's picture.
// * The caller's EGL binding is restored after every call, so the full-screen renderer on the same
//   thread is unaffected. Nothing here knows other layers, the analysis bus or capture
//   (Constitution VI); PCM goes in through the bridge's documented call (Constitution VIII). Flash
//   limiting: the compositor's composite guard (research CMP-001-D8).
// Per frame this file allocates nothing (the PCM scratch and the sync attributes are preallocated);
// ANGLE creates its own sync object. Not Sendable: the compositor's thread drives it.
import AudioCore
import CANGLE
import Compositor
import Foundation
import Metal
import ProjectMBridge

public enum ProjectMLayerError: Error, Equatable, Sendable {
    /// No ANGLE Metal display, config or context.
    case displayUnavailable
    /// The pinned ANGLE build does not report this extension.
    case missingExtension(String)
    /// The engine could not be created in the layer's context.
    case engineUnavailable
    /// The conversion pass could not be built; the text is the system's.
    case pipelineUnavailable(String)
}

public final class ProjectMLayerSource: LayerSource {
    public static let requiredExtensions = ["EGL_ANGLE_metal_texture_client_buffer", "EGL_ANGLE_metal_shared_event_sync"]

    public let layerName = "projectM"
    public let fallback = LayerFallback.lastGoodFrame

    /// Tests: draw a fixed GL pattern instead of the engine's frame (the picture's bottom-left
    /// quadrant encoded 0.5 red, the rest encoded blue).
    var drawsTestPattern = false

    private let device: MTLDevice
    private let display: EGLDisplay
    private let context: EGLContext
    private let placeholder: EGLSurface
    private var engine: ProjectMEngine?
    private let event: MTLSharedEvent
    private var signalValue: UInt64 = 0
    private let syncAttributes: UnsafeMutablePointer<EGLAttrib>
    private var pendingSync: EGLSync?
    private let pipeline: MTLRenderPipelineState
    private var reader: (any NormalizedPCMReader)?
    private let pcm: UnsafeMutablePointer<Float>
    private let maxFrames = Int(ProjectMEngine.maxSamplesPerFrame)

    private var texture: MTLTexture?
    private var image: EGLImage?
    private var framebuffer: UInt32 = 0
    private var glTexture: UInt32 = 0
    private var width = 0
    private var height = 0

    public init(device: MTLDevice) throws(ProjectMLayerError) {
        let platform: [EGLAttrib] = [EGLAttrib(EGL_PLATFORM_ANGLE_TYPE_ANGLE), EGLAttrib(EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE),
                                     EGLAttrib(EGL_NONE)]
        guard let display = eglGetPlatformDisplay(EGLenum(EGL_PLATFORM_ANGLE_ANGLE), nil, platform),
              eglInitialize(display, nil, nil) == EGL_TRUE else { throw .displayUnavailable }
        let extensions = eglQueryString(display, EGL_EXTENSIONS).map { String(cString: $0) } ?? ""
        let reported = Set(extensions.split(separator: " ").map(String.init))
        for name in Self.requiredExtensions where !reported.contains(name) { throw .missingExtension(name) }
        let attributes: [EGLint] = [EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
                                    EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_NONE]
        var config: EGLConfig?
        var count: EGLint = 0
        guard eglChooseConfig(display, attributes, &config, 1, &count) == EGL_TRUE, count > 0, let config else {
            throw .displayUnavailable
        }
        let contextAttributes: [EGLint] = [EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 0, EGL_NONE]
        let pbuffer: [EGLint] = [EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE]
        guard let context = eglCreateContext(display, config, nil, contextAttributes) else { throw .displayUnavailable }
        guard let placeholder = eglCreatePbufferSurface(display, config, pbuffer) else {
            eglDestroyContext(display, context)
            throw .displayUnavailable
        }
        guard let event = device.makeSharedEvent() else {
            eglDestroySurface(display, placeholder)
            eglDestroyContext(display, context)
            throw .pipelineUnavailable("shared event")
        }
        let built: MTLRenderPipelineState
        do {
            built = try Self.makePipeline(device: device)
        } catch {
            eglDestroySurface(display, placeholder)
            eglDestroyContext(display, context)
            throw error
        }
        self.device = device
        self.display = display
        self.context = context
        self.placeholder = placeholder
        self.event = event
        pipeline = built
        syncAttributes = .allocate(capacity: 7)
        syncAttributes.initialize(repeating: EGLAttrib(EGL_NONE), count: 7)
        pcm = .allocate(capacity: maxFrames * 2)
        pcm.initialize(repeating: 0, count: maxFrames * 2)
        withContext { engine = try? ProjectMEngine(glLoader: PMANGLELoadProc, userData: nil) }
        guard engine != nil else { throw .engineUnavailable }
    }

    deinit {
        withContext {
            if let pendingSync { eglDestroySync(display, pendingSync) }
            releasePicture()
            engine = nil   // destroyed while its context is current (bridge guarantee 3)
        }
        eglDestroySurface(display, placeholder)
        eglDestroyContext(display, context)
        syncAttributes.deinitialize(count: 7)
        syncAttributes.deallocate()
        pcm.deinitialize(count: maxFrames * 2)
        pcm.deallocate()
    }

    // MARK: - Engine controls

    /// The PCM the engine analyses, read once per frame (as `ANGLERenderer.attach(pcm:)`).
    public func attach(pcm reader: any NormalizedPCMReader) {
        self.reader = reader
    }

    public func loadPreset(atPath path: String, smooth: Bool = false) throws {
        try withContext { () throws -> Void in try engine?.loadPreset(atPath: path, smooth: smooth) }
    }

    public func loadPresetData(_ data: Data, smooth: Bool = false) throws {
        try withContext { () throws -> Void in try engine?.loadPresetData(data, smooth: smooth) }
    }

    public func setTextureSearchPaths(_ paths: [String]) {
        withContext { engine?.setTextureSearchPaths(paths) }
    }

    // MARK: - LayerSource

    public func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: picture.width, height: picture.height,
                                                         mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        guard let created = self.device.makeTexture(descriptor: d) else {
            throw .resourceUnavailable("projectM picture \(picture.width)×\(picture.height)")
        }
        created.label = "CMP-001 projectM picture"
        let ok = withContext { () -> Bool in
            releasePicture()
            guard let newImage = eglCreateImage(display, nil, EGLenum(EGL_METAL_TEXTURE_ANGLE),
                                                Unmanaged.passUnretained(created as AnyObject).toOpaque(), [EGLAttrib(EGL_NONE)]) else {
                return false
            }
            var name: UInt32 = 0
            let fbo = PMANGLECreateImageFramebuffer(newImage, &name)
            guard fbo != 0 else {
                eglDestroyImage(display, newImage)
                return false
            }
            image = newImage
            framebuffer = fbo
            glTexture = name
            engine?.setViewportWidth(picture.width, height: picture.height)
            return true
        }
        guard ok else { throw .resourceUnavailable("EGL image over the projectM picture (eglGetError 0x\(String(eglGetError(), radix: 16)))") }
        texture = created
        width = picture.width
        height = picture.height
    }

    public func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                       audio: LayerAudioContext) throws(LayerSourceError) {
        guard let texture, framebuffer != 0, picture.width == width, picture.height == height else { throw .notReady }
        let signaled = withContext { () -> Bool in
            if let pendingSync {   // the previous frame's sync; its signal is long submitted
                eglDestroySync(display, pendingSync)
                self.pendingSync = nil
            }
            if drawsTestPattern {
                PMANGLEClearRect(framebuffer, 0, 0, Int32(width), Int32(height), 0, 0, 1, 1)
                PMANGLEClearRect(framebuffer, 0, 0, Int32(width / 2), Int32(height / 2), 0.5, 0, 0, 1)
            } else if let engine {
                if let reader {
                    let frames = reader.read(into: pcm, maxFrames: maxFrames)
                    if frames > 0 { engine.addPCMInterleavedStereo(pcm, frames: UInt(frames)) }
                }
                engine.renderFrame(toFramebuffer: framebuffer)
            }
            signalValue += 1
            syncAttributes[0] = EGLAttrib(EGL_SYNC_METAL_SHARED_EVENT_OBJECT_ANGLE)
            syncAttributes[1] = EGLAttrib(bitPattern: Unmanaged.passUnretained(event as AnyObject).toOpaque())
            syncAttributes[2] = EGLAttrib(EGL_SYNC_METAL_SHARED_EVENT_SIGNAL_VALUE_LO_ANGLE)
            syncAttributes[3] = EGLAttrib(signalValue & 0xFFFF_FFFF)
            syncAttributes[4] = EGLAttrib(EGL_SYNC_METAL_SHARED_EVENT_SIGNAL_VALUE_HI_ANGLE)
            syncAttributes[5] = EGLAttrib(signalValue >> 32)
            syncAttributes[6] = EGLAttrib(EGL_NONE)
            pendingSync = eglCreateSync(display, EGLenum(EGL_SYNC_METAL_SHARED_EVENT_ANGLE), syncAttributes)
            PMANGLEFlush()
            return pendingSync != nil
        }
        guard signaled else { throw .engineFailure("EGL shared-event sync (eglGetError 0x\(String(eglGetError(), radix: 16)))") }
        commandBuffer.encodeWaitForEvent(event, value: signalValue)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = picture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            throw .resourceUnavailable("projectM conversion encoder")
        }
        encoder.label = "CMP-001 projectM layer"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    // MARK: - Internals

    /// Runs `body` with this layer's context current, then restores the caller's binding.
    private func withContext<T, E: Error>(_ body: () throws(E) -> T) throws(E) -> T {
        let previousDisplay = eglGetCurrentDisplay()
        let previousContext = eglGetCurrentContext()
        let previousDraw = eglGetCurrentSurface(EGL_DRAW)
        let previousRead = eglGetCurrentSurface(EGL_READ)
        eglMakeCurrent(display, placeholder, placeholder, context)
        defer {
            if let previousDisplay, previousContext != nil {
                eglMakeCurrent(previousDisplay, previousDraw, previousRead, previousContext)
            } else {
                eglMakeCurrent(display, nil, nil, nil)
            }
        }
        return try body()
    }

    /// Deletes the framebuffer, GL texture and EGL image (context current).
    private func releasePicture() {
        if framebuffer != 0 || glTexture != 0 { PMANGLEDeleteFramebuffer(framebuffer, glTexture) }
        framebuffer = 0
        glTexture = 0
        if let image { eglDestroyImage(display, image) }
        image = nil
        texture = nil
    }

    /// Flip (GL row 0 is Metal row 0), sRGB decode, opaque: the layer's picture convention.
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct FullScreenOut { float4 position [[position]]; };
    vertex FullScreenOut pm_fullscreen(uint vid [[vertex_id]]) {
        float2 p = float2(float((vid << 1) & 2), float(vid & 2));
        FullScreenOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return o;
    }
    fragment float4 pm_layer(FullScreenOut in [[stage_in]], texture2d<float, access::read> source [[texture(0)]]) {
        uint2 p = uint2(in.position.xy);
        uint h = source.get_height();
        float3 c = clamp(source.read(uint2(p.x, h - 1 - min(p.y, h - 1))).rgb, 0.0, 1.0);
        float3 linear = select(pow((c + 0.055) / 1.055, float3(2.4)), c / 12.92, c <= 0.04045);
        return float4(linear, 1.0);
    }
    """

    private static func makePipeline(device: MTLDevice) throws(ProjectMLayerError) -> MTLRenderPipelineState {
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let d = MTLRenderPipelineDescriptor()
            d.label = "CMP-001 projectM layer"
            d.vertexFunction = library.makeFunction(name: "pm_fullscreen")
            d.fragmentFunction = library.makeFunction(name: "pm_layer")
            d.colorAttachments[0].pixelFormat = LayerPictureDescriptor.metalPixelFormat
            return try device.makeRenderPipelineState(descriptor: d)
        } catch {
            throw .pipelineUnavailable(error.localizedDescription)
        }
    }
}
