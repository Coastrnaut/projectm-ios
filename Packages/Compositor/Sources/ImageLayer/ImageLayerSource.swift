// ImageLayerSource.swift — a still image as a CMP-001 layer (MED-001-R9, R10; research MED-001-D6,
// D7; contracts/image-layer.md "Layer source").
//
// Setting `content` starts one load on a background serial queue: a bounded read of the stored
// file, the decoder (`ImageDecoding`, the MED-014 seam), a mipmapped `.rgba8Unorm_srgb` texture
// (so the sampler returns linear light) filled with the straight-alpha pixels, and a blit that
// builds the mip chain (no shimmer when a 4096 px copy is shown on a phone). The result goes into a
// slot guarded by an unfair lock, tagged with the content's generation so a stale load is dropped.
// `render` never loads: it takes the slot only when its lock is free this instant (otherwise it
// keeps the texture it holds), and throws `.notReady` until there is a texture, so the compositor
// shows the transparent fallback while loading, with no content or after a failure. The shader
// maps each output point through `ImagePictureGeometry` (CMP-006 fit; fill by default), samples, and multiplies
// by alpha: the picture is linear premultiplied (CMP-001-R2); outside the image (fit) it is
// transparent. Not Sendable: the compositor's thread (the main thread in the app) sets `content`
// and renders; `onStateChange` is called on the main queue.
// CMP-013 (ADR-0040): the picture depends only on the held image, the fit and the picture size, so the
// layer declares itself still (`LayerRenderCaching`): content = the load generation of the held image,
// parameters = a fit generation. The dependency read takes the slot exactly as `render` does, so the
// generation reported is never newer than what `render` draws. A reused frame still counts in `framesShown`;
// `renderCount` counts actual renders.
// MED-006 (specs/127-med-006-image-slideshow, contract C3): `preload` decodes the next slide ahead into a
// one-entry prepared slot; setting `content` to that URL adopts it synchronously, so a slide change is a
// cut that renders once (no transparent frame) and changes the cache key exactly once.
import Foundation

/// What the photo layer shows.
public enum ImageLayerContent: Sendable, Equatable {
    case none
    /// A stored copy on the device (MED-001-R3); read with the import limits.
    case file(URL)
}

/// The photo layer's state (data-model "ImageLayerContent / ImageLayerState").
public enum ImageLayerState: Sendable, Equatable {
    case empty
    case loading
    case ready(width: Int, height: Int)
    case failed(ImageImportError)
}

#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal
import os

public final class ImageLayerSource: LayerSource, LayerFitting, LayerRenderCaching {
    public let layerName = "photo"
    public let fallback = LayerFallback.transparent
    public let device: MTLDevice
    /// The fit drawn while `fit` is nil (fill unless the init chose another).
    public let mode: ImageScaleMode
    /// CMP-006: the stack entry's fit (set by the compositor; nil: `mode` at the centre). Shown from
    /// the next frame; the image is not reloaded.
    public var fit: LayerFit? {
        didSet { if fit != oldValue { fitGeneration &+= 1 } }   // CMP-013: a parameter change
    }
    private let decoder: any ImageDecoding
    private let limits: ImageImportLimits
    private let loads = DispatchQueue(label: "MED-001 image load", qos: .userInitiated)
    private let slot = ImageLoadSlot()
    private var pipeline: MTLRenderPipelineState?
    private var sampler: MTLSamplerState?
    /// The texture drawn last frame (render side only).
    private var held: MTLTexture?
    /// CMP-013: the load generation of `held`, and the fit's generation.
    private var heldGeneration: UInt64 = 0
    private var fitGeneration: UInt64 = 0
    /// Frames that showed the image (diagnostics, tests), including frames whose picture was reused.
    public private(set) var framesShown = 0
    /// CMP-013: frames that drew the image (render calls that succeeded).
    public private(set) var renderCount = 0
    /// Called on the main actor after every state change.
    public var onStateChange: (@MainActor @Sendable (ImageLayerState) -> Void)? {
        get { slot.lock.withLockUnchecked { $0.handler } }
        set { slot.lock.withLockUnchecked { $0.handler = newValue } }
    }

    public init(device: MTLDevice, decoder: any ImageDecoding = ImageIODecoder(), limits: ImageImportLimits = .standard,
                mode: ImageScaleMode = .fill) {
        self.device = device
        self.decoder = decoder
        self.limits = limits
        self.mode = mode
    }

    /// The current state (read under the slot's lock; not for the render path).
    public var state: ImageLayerState { slot.lock.withLockUnchecked { $0.state } }

    /// The content shown. Setting it drops the current image at once (the next frame is transparent)
    /// and, for a file, starts its load.
    public var content: ImageLayerContent = .none {
        didSet {
            guard content != oldValue else { return }
            held = nil
            let generation: UInt64 = slot.lock.withLockUnchecked { s in
                s.generation &+= 1
                s.texture = nil
                s.state = content == .none ? .empty : .loading
                return s.generation
            }
            heldGeneration = generation   // CMP-013: the dropped image's key never matches again
            // MED-006-R9: a slide decoded ahead by `preload` is adopted now, so the next frame draws it.
            if case .file(let url) = content, slot.adoptPrepared(url, generation: generation) {
                slot.notify()
                return
            }
            slot.notify()
            guard case .file(let url) = content else { return }
            let slot = self.slot, device = self.device, decoder = self.decoder, limits = self.limits
            loads.async {
                let result: Result<MTLTexture, ImageImportError> = slot.takePrepared(url).map {
                    (texture: MTLTexture) -> Result<MTLTexture, ImageImportError> in .success(texture)
                } ?? Self.load(url, device: device, decoder: decoder, limits: limits)
                let stored: Bool = slot.lock.withLockUnchecked { s in
                    guard s.generation == generation else { return false }   // a newer content won
                    switch result {
                    case .success(let texture):
                        s.texture = texture
                        s.state = .ready(width: texture.width, height: texture.height)
                    case .failure(let error):
                        s.state = .failed(error)
                    }
                    return true
                }
                if stored { slot.notify() }
            }
        }
    }

    /// MED-006-R9 (contract C3): decodes `url` on the load queue into the prepared slot (one entry; a
    /// newer preload replaces it). Changes neither `content`, `state` nor the drawn picture; setting
    /// `content` to `url` later adopts the decoded texture at once. A failed decode leaves nothing.
    public func preload(_ url: URL) {
        let token: UInt64 = slot.lock.withLockUnchecked { s in
            if s.preparedURL == url { return 0 }   // already prepared or in flight
            s.preparedToken &+= 1
            s.preparedURL = url
            s.preparedTexture = nil
            return s.preparedToken
        }
        guard token != 0 else { return }
        let slot = self.slot, device = self.device, decoder = self.decoder, limits = self.limits
        loads.async {
            guard case .success(let texture) = Self.load(url, device: device, decoder: decoder, limits: limits) else { return }
            slot.lock.withLockUnchecked { s in
                if s.preparedToken == token, s.preparedURL == url { s.preparedTexture = texture }
            }
        }
    }

    /// The URL in the prepared slot (tests, diagnostics).
    public var preparedURL: URL? { slot.lock.withLockUnchecked { $0.preparedURL } }

    /// True when the prepared slot holds a decoded texture for `url`.
    public func isPrepared(_ url: URL) -> Bool {
        slot.lock.withLockUnchecked { $0.preparedURL == url && $0.preparedTexture != nil }
    }

    /// Tests only: returns when every load started so far has finished.
    public func waitUntilLoaded() { loads.sync {} }

    /// Reads, decodes and uploads one stored copy (background queue).
    static func load(_ url: URL, device: MTLDevice, decoder: any ImageDecoding,
                     limits: ImageImportLimits) -> Result<MTLTexture, ImageImportError> {
        do throws(ImageImportError) {
            let data = try ImageSanitizer.readBounded(url, limits: limits)
            let image = try decoder.decode(data, limits: limits)
            guard let texture = makeTexture(image, device: device) else { return .failure(.damaged) }
            return .success(texture)
        } catch {
            return .failure(error)
        }
    }

    static func makeTexture(_ image: DecodedImage, device: MTLDevice) -> MTLTexture? {
        guard image.width >= 1, image.height >= 1, image.pixels.count == image.width * image.height * 4 else { return nil }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: image.width,
                                                         height: image.height, mipmapped: true)
        d.usage = [.shaderRead]
        d.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: d) else { return nil }
        texture.label = "MED-001 photo"
        image.pixels.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            texture.replace(region: MTLRegionMake2D(0, 0, image.width, image.height), mipmapLevel: 0,
                            withBytes: bytes.baseAddress!, bytesPerRow: image.width * 4)
        }
        if texture.mipmapLevelCount > 1 {
            guard let queue = device.makeCommandQueue(), let commands = queue.makeCommandBuffer(),
                  let blit = commands.makeBlitCommandEncoder() else { return nil }
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()
            guard commands.status == .completed else { return nil }
        }
        return texture
    }

    public func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {
        if pipeline != nil { return }   // a size change keeps the decoded image (MED-001 edge cases)
        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            guard let vertex = library.makeFunction(name: "img_fullscreen"),
                  let fragment = library.makeFunction(name: "img_picture") else {
                throw LayerSourceError.resourceUnavailable("photo shader functions")
            }
            let d = MTLRenderPipelineDescriptor()
            d.label = "MED-001 photo"
            d.vertexFunction = vertex
            d.fragmentFunction = fragment
            d.colorAttachments[0].pixelFormat = LayerPictureDescriptor.metalPixelFormat
            pipeline = try device.makeRenderPipelineState(descriptor: d)
        } catch let error as LayerSourceError {
            throw error
        } catch {
            throw .resourceUnavailable("photo pipeline: \(error)")
        }
        let s = MTLSamplerDescriptor()
        s.minFilter = .linear
        s.magFilter = .linear
        s.mipFilter = .linear
        s.sAddressMode = .clampToEdge
        s.tAddressMode = .clampToEdge
        guard let state = device.makeSamplerState(descriptor: s) else {
            pipeline = nil
            throw .resourceUnavailable("photo sampler")
        }
        sampler = state
    }

    public func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                       audio: LayerAudioContext) throws(LayerSourceError) {
        takeNewest()
        guard let image = held, let pipeline, let sampler else { throw .notReady }
        let placement = LayerFitPlacement(contentWidth: image.width, contentHeight: image.height, outputWidth: picture.width,
                                          outputHeight: picture.height, fit: fit ?? LayerFit(mode: mode))
        let geometry = ImagePictureGeometry(placement)
        var uniforms = ImageUniforms(geometry: geometry, outputWidth: picture.width, outputHeight: picture.height)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = picture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { throw .frameSkipped }
        encoder.label = "MED-001 photo"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(image, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ImageUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        framesShown += 1
        renderCount += 1
    }

    /// The newest loaded image, when the slot's lock is free this instant (otherwise the held one stays).
    private func takeNewest() {
        if let newest: (MTLTexture?, UInt64) = slot.lock.withLockIfAvailableUnchecked({ ($0.texture, $0.generation) }) {
            held = newest.0
            heldGeneration = newest.1
        }
    }

    /// CMP-013: still; the held image's load generation and the fit generation.
    public var renderDependencies: LayerRenderDependencies {
        takeNewest()
        return .still(content: heldGeneration, parameters: fitGeneration)
    }

    public func renderReused(frame: LayerFrameContext) { framesShown += 1 }

    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct ImgOut { float4 position [[position]]; };

    vertex ImgOut img_fullscreen(uint vid [[vertex_id]]) {
        float2 p = float2(float((vid << 1) & 2), float(vid & 2));
        ImgOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return o;
    }

    struct ImgUniforms {
        float2 visible;
        float2 offset;
        float2 outputSize;
    };

    // Output point (0...1, top-left) -> image coordinate (ImagePictureGeometry.textureCoordinate).
    // The texture is sRGB, so the sample is linear light with straight alpha; multiplying by alpha
    // makes it premultiplied. Outside the image (fit mode) nothing is drawn.
    fragment float4 img_picture(ImgOut in [[stage_in]], texture2d<float> image [[texture(0)]],
                                sampler s [[sampler(0)]], constant ImgUniforms &u [[buffer(0)]]) {
        float2 p = in.position.xy / u.outputSize;
        float2 t = u.offset + p * u.visible;
        if (any(t < 0.0) || any(t > 1.0)) { return float4(0.0); }
        float4 c = image.sample(s, t);
        float a = clamp(c.a, 0.0, 1.0);
        return float4(max(c.rgb, float3(0.0)) * a, a);
    }
    """
}

extension ImageLayerSource {
    /// MED-010: the logo layer's library (`LogoLayerSource`), compiled from the module constant below; kept in
    /// this reviewed file so the Metal source stays inside METAL_SOURCE_ALLOWED (SHD-011).
    static func logoLibrary(device: MTLDevice) throws -> MTLLibrary {
        try device.makeLibrary(source: logoShaderSource, options: nil)
    }

    static let logoShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct LogoOut { float4 position [[position]]; };

    vertex LogoOut logo_fullscreen(uint vid [[vertex_id]]) {
        float2 p = float2(float((vid << 1) & 2), float(vid & 2));
        LogoOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return o;
    }

    struct LogoUniforms {
        float4 rect;     // x, y, width, height in output pixels (top-left origin)
        float4 params;   // opacity, unused × 3
    };

    // The texels are premultiplied linear light, so the sample is already "over"-ready; only the
    // opacity scales it. Outside the logo's rectangle nothing is drawn.
    fragment float4 logo_picture(LogoOut in [[stage_in]], texture2d<float> logo [[texture(0)]],
                                 sampler s [[sampler(0)]], constant LogoUniforms &u [[buffer(0)]]) {
        float2 t = (in.position.xy - u.rect.xy) / u.rect.zw;
        if (any(t < 0.0) || any(t > 1.0)) { return float4(0.0); }
        float4 c = logo.sample(s, t);
        float a = clamp(c.a, 0.0, 1.0);
        float3 rgb = clamp(c.rgb, float3(0.0), float3(a));
        return float4(rgb, a) * u.params.x;
    }
    """
}

/// The load result shared between the background queue and the render thread.
final class ImageLoadSlot: Sendable {
    struct State {
        var generation: UInt64 = 0
        var texture: MTLTexture?
        var state: ImageLayerState = .empty
        var handler: (@MainActor @Sendable (ImageLayerState) -> Void)?
        /// MED-006: the slide decoded ahead (`preload`).
        var preparedURL: URL?
        var preparedTexture: MTLTexture?
        var preparedToken: UInt64 = 0
    }
    let lock = OSAllocatedUnfairLock(uncheckedState: State())

    /// Moves a prepared texture for `url` into the slot under `generation`; false when none is ready.
    func adoptPrepared(_ url: URL, generation: UInt64) -> Bool {
        lock.withLockUnchecked { s in
            guard s.generation == generation, s.preparedURL == url, let texture = s.preparedTexture else { return false }
            s.texture = texture
            s.state = .ready(width: texture.width, height: texture.height)
            s.preparedURL = nil
            s.preparedTexture = nil
            return true
        }
    }

    /// The prepared texture for `url`, taken out of the prepared slot (load queue).
    func takePrepared(_ url: URL) -> MTLTexture? {
        lock.withLockUnchecked { s in
            guard s.preparedURL == url, let texture = s.preparedTexture else { return nil }
            s.preparedURL = nil
            s.preparedTexture = nil
            return texture
        }
    }

    /// Hands the state to the handler on the main actor, read when it is delivered (so the last
    /// delivery is always the current state, whatever order the deliveries run in).
    func notify() {
        guard lock.withLockUnchecked({ $0.handler != nil }) else { return }
        Task { @MainActor [self] in
            let (state, handler) = lock.withLockUnchecked { ($0.state, $0.handler) }
            handler?(state)
        }
    }
}

/// Matches `ImgUniforms` in the shader (24 bytes).
struct ImageUniforms {
    var visible: SIMD2<Float>
    var offset: SIMD2<Float>
    var outputSize: SIMD2<Float>

    init(geometry: ImagePictureGeometry, outputWidth: Int, outputHeight: Int) {
        visible = SIMD2(geometry.visibleWidth, geometry.visibleHeight)
        offset = SIMD2(geometry.offsetX, geometry.offsetY)
        outputSize = SIMD2(Float(max(outputWidth, 1)), Float(max(outputHeight, 1)))
    }
}
#endif
