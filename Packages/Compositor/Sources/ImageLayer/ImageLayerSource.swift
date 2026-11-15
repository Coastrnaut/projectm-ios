// ImageLayerSource.swift — a still image as a CMP-001 layer (MED-001-R9, R10; research MED-001-D6,
// D7; contracts/image-layer.md "Layer source").
//
// Setting `content` starts one load on a background serial queue: a bounded read of the stored
// file, the decoder (`ImageDecoding`, the MED-014 seam), a mipmapped `.rgba8Unorm_srgb` texture
// (so the sampler returns linear light) filled with premultiplied texels (`PremultipliedSRGB`: the sRGB
// encoding of linear colour × alpha, so filtering and mips never pull the colour of transparent texels
// into soft edges), and a blit that builds the mip chain (no shimmer when a 4096 px copy is shown on a
// phone). The result goes into a
// slot guarded by an unfair lock, tagged with the content's generation so a stale load is dropped.
// `render` never loads: it takes the slot only when its lock is free this instant (otherwise it
// keeps the texture it holds), and throws `.notReady` until there is a texture, so the compositor
// shows the transparent fallback while loading, with no content or after a failure. The shader
// maps each output point through `ImagePictureGeometry` (CMP-006 fit; fill by default) and samples: the
// sample is already linear premultiplied (CMP-001-R2); outside the image (fit) it is
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
// PERF-005 (specs/179-perf-005-prewarm-scheduler, R11): `prewarmedTexture` is a lookup the app's prewarm scheduler
// answers. When `content` becomes a file that the prepared slot does not hold, a texture the lookup returns is
// adopted synchronously (ready at once, no load of this layer's own). `decodeStored` and `makeLayerTexture` are the
// two halves of a load, so the scheduler can decode off the main thread and upload inside its graphics gate;
// `loadsStarted` counts the loads this layer started itself.
// MED-007 (specs/251-med-007-ken-burns, contract K2; research MED-007-D1 to D6): `kenBurns` pans and zooms the picture
// from a start to an end crop rectangle. The crop is the content the fit places (pixel-accurate drawn as fit), and
// outside it is transparent. A `KenBurnsPlayhead` counts the frame clock's durations from the first drawn frame of the
// held picture (restarted by a new picture or a new movement), so the first frame shows exactly the start rectangle
// and the frame reaching the duration exactly the end. `reduceMotion` holds the start. While moving, the layer
// declares a time dependency (never cached); holding, it is still again, its parameter generation changing with the
// fit, the movement, the duration and Reduce Motion.
// MED-008 (specs/257-med-008-animated-images, contract A2; research MED-008-D5 to D8): a stored animation (APNG, GIF,
// HEICS, WebP) loads as an `AnimatedPicture` whose frame 0 is the held picture. Each render advances a second playhead
// (the same frame-time counter, unbounded) and draws the frame `AnimationTimeline.frameIndex` picks (frame 0 under
// Reduce Motion; the Reduce flashing timeline while the frame context's `reduceFlashing` is on); a frame not decoded yet leaves the last drawn
// frame on screen and is requested with the one after it. While animating the layer declares a time dependency. The
// prepared slot (MED-006) carries an animation too; a prewarmed still (PERF-005) is adopted at once and the file is then
// probed on the load queue, attaching its animation for the same generation.
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
        didSet { if fit != oldValue { parameterGeneration &+= 1 } }   // CMP-013: a parameter change
    }
    /// MED-007: the pan and zoom (nil: none). A different movement restarts from its start rectangle.
    public var kenBurns: KenBurnsMotion? {
        didSet {
            guard kenBurns != oldValue else { return }
            parameterGeneration &+= 1
            playhead.restart()
        }
    }
    /// MED-007-R8: the movement's duration when set (the slideshow's dwell); nil: the movement's own. A change keeps
    /// the elapsed time.
    public var kenBurnsDurationNanoseconds: UInt64? {
        didSet { if kenBurnsDurationNanoseconds != oldValue { parameterGeneration &+= 1 } }
    }
    /// MED-007-R7: Reduce Motion holds the start rectangle.
    public var reduceMotion = false {
        didSet {
            guard reduceMotion != oldValue else { return }
            parameterGeneration &+= 1
            playhead.restart()
        }
    }
    /// MED-007: elapsed time of the movement (render side).
    public private(set) var playhead = KenBurnsPlayhead()
    /// MED-008: elapsed time of the animation (render side; the same counter, never saturating in practice).
    public private(set) var animationPlayhead = KenBurnsPlayhead()
    /// MED-008-R8: the decoded-frame budget of each animation this layer loads.
    public let animationBudgetBytes: Int
    /// MED-008: the animation of the held picture (render side), and the frame drawn last.
    private var heldAnimation: AnimatedPicture?
    private var drawnFrame: MTLTexture?
    /// MED-008: the animation frame drawn last (diagnostics, tests; 0 for a still).
    public private(set) var shownFrameIndex = 0
    private let decoder: any ImageDecoding
    private let limits: ImageImportLimits
    private let loads = DispatchQueue(label: "MED-001 image load", qos: .userInitiated)
    private let slot = ImageLoadSlot()
    private var pipeline: MTLRenderPipelineState?
    private var sampler: MTLSamplerState?
    /// The texture drawn last frame (render side only).
    private var held: MTLTexture?
    /// CMP-013: the load generation of `held`, and the generation of the parameters drawn with (fit; MED-007's
    /// movement, duration and Reduce Motion).
    private var heldGeneration: UInt64 = 0
    private var parameterGeneration: UInt64 = 0
    /// Frames that showed the image (diagnostics, tests), including frames whose picture was reused.
    public private(set) var framesShown = 0
    /// CMP-013: frames that drew the image (render calls that succeeded).
    public private(set) var renderCount = 0
    /// PERF-005: a texture decoded ahead for a URL (the prewarm cache), taken when `content` becomes that URL.
    public var prewarmedTexture: ((URL) -> MTLTexture?)?
    /// PERF-005: loads this layer started itself (content changes that were neither prepared nor prewarmed).
    public var loadsStarted: Int { slot.lock.withLockUnchecked { $0.loadsStarted } }
    /// PERF-005: content changes served by `prewarmedTexture`.
    public private(set) var prewarmedAdoptions = 0
    /// Called on the main actor after every state change.
    public var onStateChange: (@MainActor @Sendable (ImageLayerState) -> Void)? {
        get { slot.lock.withLockUnchecked { $0.handler } }
        set { slot.lock.withLockUnchecked { $0.handler = newValue } }
    }

    public init(device: MTLDevice, decoder: any ImageDecoding = ImageIODecoder(), limits: ImageImportLimits = .standard,
                mode: ImageScaleMode = .fill, animationBudgetBytes: Int = AnimatedFrameBudget.current) {
        self.device = device
        self.animationBudgetBytes = animationBudgetBytes
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
            heldAnimation = nil
            drawnFrame = nil
            animationPlayhead.restart()
            let generation: UInt64 = slot.lock.withLockUnchecked { s in
                s.generation &+= 1
                s.texture = nil
                s.animation = nil
                s.state = content == .none ? .empty : .loading
                return s.generation
            }
            heldGeneration = generation   // CMP-013: the dropped image's key never matches again
            playhead.restart()   // MED-007-R5: a new picture starts at the start rectangle
            // MED-006-R9: a slide decoded ahead by `preload` is adopted now, so the next frame draws it.
            if case .file(let url) = content, slot.adoptPrepared(url, generation: generation) {
                slot.notify()
                return
            }
            // PERF-005-R11: a picture the prewarm scheduler decoded ahead is adopted now.
            if case .file(let url) = content, let texture = prewarmedTexture?(url) {
                slot.lock.withLockUnchecked { s in
                    guard s.generation == generation else { return }
                    s.texture = texture
                    s.state = .ready(width: texture.width, height: texture.height)
                }
                prewarmedAdoptions += 1
                slot.notify()
                attachAnimation(url, generation: generation)   // MED-008-D8
                return
            }
            slot.notify()
            guard case .file(let url) = content else { return }
            let slot = self.slot, device = self.device, decoder = self.decoder, limits = self.limits
            let budget: Int = animationBudgetBytes
            slot.lock.withLockUnchecked { $0.loadsStarted += 1 }
            loads.async {
                let result: Result<LoadedPicture, ImageImportError> = slot.takePrepared(url).map {
                    (picture: LoadedPicture) -> Result<LoadedPicture, ImageImportError> in .success(picture)
                } ?? Self.load(url, device: device, decoder: decoder, limits: limits, budget: budget)
                let stored: Bool = slot.lock.withLockUnchecked { s in
                    guard s.generation == generation else { return false }   // a newer content won
                    switch result {
                    case .success(let picture):
                        s.texture = picture.texture
                        s.animation = picture.animation
                        s.state = .ready(width: picture.texture.width, height: picture.texture.height)
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
        let budget: Int = animationBudgetBytes
        loads.async {
            guard case .success(let picture) = Self.load(url, device: device, decoder: decoder, limits: limits,
                                                         budget: budget) else { return }
            slot.lock.withLockUnchecked { s in
                if s.preparedToken == token, s.preparedURL == url { s.preparedTexture = picture }
            }
        }
    }

    /// MED-008-D8: after a prewarmed still was adopted, probes the file and attaches its animation (same generation).
    private func attachAnimation(_ url: URL, generation: UInt64) {
        let slot = self.slot, device = self.device, limits = self.limits
        let budget: Int = animationBudgetBytes
        loads.async {
            guard let data = try? ImageSanitizer.readBounded(url, limits: limits),
                  let animation = try? AnimatedPicture.make(data, device: device, budget: budget, limits: limits) else { return }
            let stored: Bool = slot.lock.withLockUnchecked { s in
                guard s.generation == generation else { return false }
                s.texture = animation.frame0
                s.animation = animation
                s.state = .ready(width: animation.frame0.width, height: animation.frame0.height)
                return true
            }
            if stored { slot.notify() }
        }
    }

    /// MED-008: frames of the held animation (0: a still or nothing). Read under the slot's lock.
    public var animationFrameCount: Int { slot.lock.withLockUnchecked { $0.animation?.frameCount ?? 0 } }

    /// MED-008: the held animation's frame cache (nil: no animation).
    public var animationCacheStatistics: AnimatedFrameCacheStatistics? {
        slot.lock.withLockUnchecked { $0.animation }?.statistics
    }

    /// The URL in the prepared slot (tests, diagnostics).
    public var preparedURL: URL? { slot.lock.withLockUnchecked { $0.preparedURL } }

    /// True when the prepared slot holds a decoded texture for `url`.
    public func isPrepared(_ url: URL) -> Bool {
        slot.lock.withLockUnchecked { $0.preparedURL == url && $0.preparedTexture != nil }
    }

    /// Tests only: returns when every load started so far, and every frame decode it requested, has finished.
    public func waitUntilLoaded() {
        loads.sync {}
        let animations: [AnimatedPicture] = slot.lock.withLockUnchecked { s in
            [s.animation, s.preparedTexture?.animation].compactMap { (a: AnimatedPicture?) -> AnimatedPicture? in a }
        }
        for animation in animations { animation.waitUntilIdle() }
    }

    /// Reads, decodes and uploads one stored copy (background queue). MED-008: an animation loads as its frame 0 and
    /// its `AnimatedPicture`.
    static func load(_ url: URL, device: MTLDevice, decoder: any ImageDecoding, limits: ImageImportLimits,
                     budget: Int = AnimatedFrameBudget.current) -> Result<LoadedPicture, ImageImportError> {
        do throws(ImageImportError) {
            let data = try ImageSanitizer.readBounded(url, limits: limits)
            if let animation = try AnimatedPicture.make(data, device: device, budget: budget, limits: limits) {
                return .success(LoadedPicture(texture: animation.frame0, animation: animation))
            }
            let image = try decoder.decode(data, limits: limits)
            guard let texture = makeTexture(image, device: device) else { return .failure(.damaged) }
            return .success(LoadedPicture(texture: texture, animation: nil))
        } catch {
            return .failure(error)
        }
    }

    /// PERF-005: the CPU half of a load: a bounded read of the stored copy and the decode (any thread).
    public static func decodeStored(_ url: URL, decoder: any ImageDecoding = ImageIODecoder(),
                                    limits: ImageImportLimits = .standard) -> Result<DecodedImage, ImageImportError> {
        do throws(ImageImportError) {
            let data = try ImageSanitizer.readBounded(url, limits: limits)
            return .success(try decoder.decode(data, limits: limits))
        } catch {
            return .failure(error)
        }
    }

    /// PERF-005: the GPU half of a load: the layer's mipmapped texture for a decoded picture (nil on failure).
    public static func makeLayerTexture(_ image: DecodedImage, device: MTLDevice) -> MTLTexture? {
        makeTexture(image, device: device)
    }

    /// PERF-005: the memory a layer texture of `width` × `height` holds with its mip chain (RGBA8, about 4/3).
    public static func textureBytes(width: Int, height: Int) -> Int {
        var total = 0
        var w = max(1, width), h = max(1, height)
        while true {
            total += w * h * 4
            if w == 1 && h == 1 { break }
            w = max(1, w / 2)
            h = max(1, h / 2)
        }
        return total
    }

    /// MED-008: `mipmapped` false for animation frames (one level, no GPU blit).
    static func makeTexture(_ image: DecodedImage, device: MTLDevice, mipmapped: Bool = true) -> MTLTexture? {
        guard image.width >= 1, image.height >= 1, image.pixels.count == image.width * image.height * 4 else { return nil }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: image.width,
                                                         height: image.height, mipmapped: mipmapped)
        d.usage = [.shaderRead]
        d.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: d) else { return nil }
        texture.label = "MED-001 photo"
        let texels: [UInt8] = PremultipliedSRGB.pixels(image)
        texels.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
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
        guard let still = held, let pipeline, let sampler else { throw .notReady }
        let image: MTLTexture = animationFrame(frame: frame) ?? still
        let geometry: ImagePictureGeometry = pictureGeometry(image: image, picture: picture, frame: frame)
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

    /// Where the image lands this frame: the fit, and with Ken Burns the crop of this frame (advancing the playhead).
    private func pictureGeometry(image: MTLTexture, picture: MTLTexture, frame: LayerFrameContext) -> ImagePictureGeometry {
        let chosen: LayerFit = fit ?? LayerFit(mode: mode)
        guard let crop = kenBurnsCrop(frame: frame) else {
            let placement = LayerFitPlacement(contentWidth: image.width, contentHeight: image.height, outputWidth: picture.width,
                                              outputHeight: picture.height, fit: chosen)
            return ImagePictureGeometry(placement)
        }
        let size: (width: Int, height: Int) = ImagePictureGeometry.cropContentSize(crop, imageWidth: image.width, imageHeight: image.height)
        let cropFit: LayerFit = chosen.mode == .pixelAccurate ? LayerFit(mode: .fit, anchor: chosen.anchor) : chosen
        let placement = LayerFitPlacement(contentWidth: size.width, contentHeight: size.height, outputWidth: picture.width,
                                          outputHeight: picture.height, fit: cropFit)
        return ImagePictureGeometry(placement, crop: crop)
    }

    /// MED-007: the movement's duration (the override, else the movement's own).
    private var kenBurnsLimit: UInt64 {
        kenBurnsDurationNanoseconds ?? kenBurns?.durationNanoseconds ?? 0
    }

    /// MED-007: this frame's crop (nil without Ken Burns). Reduce Motion: the start; otherwise the playhead advances.
    private func kenBurnsCrop(frame: LayerFrameContext) -> KenBurnsRect? {
        guard let motion = kenBurns else { return nil }
        if reduceMotion { return motion.start }
        let limit: UInt64 = kenBurnsLimit
        let elapsed: UInt64 = playhead.advance(frameDuration: frame.frameDuration, limit: limit)
        return motion.crop(elapsedNanoseconds: elapsed, durationNanoseconds: limit)
    }

    /// MED-007: the picture changes from frame to frame (running, not reduced, not yet at the end).
    public var isKenBurnsMoving: Bool {
        guard let motion = kenBurns, !reduceMotion, !motion.isStill else { return false }
        return !playhead.isFinished(limit: kenBurnsLimit)
    }

    /// MED-008: this frame's animation frame (nil: no animation, or frame 0 is drawn from `held`). Advances the
    /// animation playhead; a frame not decoded yet keeps the last drawn one and is requested with the one after it.
    private func animationFrame(frame: LayerFrameContext) -> MTLTexture? {
        guard let animation = heldAnimation else { return nil }
        let timeline: AnimationTimeline = animation.timeline(reduceFlashing: frame.reduceFlashing)   // MED-008-R4
        var index = 0
        if !reduceMotion {
            let elapsed: UInt64 = animationPlayhead.advance(frameDuration: frame.frameDuration, limit: .max)
            index = timeline.frameIndex(elapsedNanoseconds: elapsed)
        }
        if let texture = animation.texture(at: index) {
            drawnFrame = texture
            shownFrameIndex = index
        } else {
            animation.request(index)
        }
        animation.request(index + 1 < animation.frameCount ? index + 1 : 0)
        return drawnFrame
    }

    /// MED-008: the held picture is an animation that plays (more than one frame, Reduce Motion off).
    public var isAnimating: Bool {
        guard let animation = heldAnimation else { return false }
        return animation.frameCount > 1 && !reduceMotion
    }

    /// The newest loaded image, when the slot's lock is free this instant (otherwise the held one stays).
    private func takeNewest() {
        if let newest: (MTLTexture?, UInt64, AnimatedPicture?) = slot.lock.withLockIfAvailableUnchecked({
            ($0.texture, $0.generation, $0.animation)
        }) {
            if newest.1 != heldGeneration || newest.0 !== held {
                playhead.restart()   // MED-007-R5
                animationPlayhead.restart()   // MED-008: a new picture starts at frame 0
                drawnFrame = nil
                shownFrameIndex = 0
            }
            held = newest.0
            heldGeneration = newest.1
            heldAnimation = newest.2
        }
    }

    /// CMP-013: still (the held image's load generation and the parameter generation), except while a Ken Burns
    /// movement runs (MED-007-R6: time).
    public var renderDependencies: LayerRenderDependencies {
        takeNewest()
        if isKenBurnsMoving || isAnimating {   // MED-008-R10
            return LayerRenderDependencies(time: true, contentGeneration: heldGeneration, parameterGeneration: parameterGeneration)
        }
        return .still(content: heldGeneration, parameters: parameterGeneration)
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
        float4 bounds;   // MED-007: the drawable part of the image (min x, min y, max x, max y)
        float2 visible;
        float2 offset;
        float2 outputSize;
    };

    // Output point (0...1, top-left) -> image coordinate (ImagePictureGeometry.textureCoordinate).
    // The texture is sRGB and holds premultiplied texels (PremultipliedSRGB), so the sample is linear
    // premultiplied light; colour is clamped to [0, alpha]. Outside the image (fit mode), or outside a Ken Burns crop
    // (MED-007), nothing is drawn.
    fragment float4 img_picture(ImgOut in [[stage_in]], texture2d<float> image [[texture(0)]],
                                sampler s [[sampler(0)]], constant ImgUniforms &u [[buffer(0)]]) {
        float2 p = in.position.xy / u.outputSize;
        float2 t = u.offset + p * u.visible;
        if (any(t < u.bounds.xy) || any(t > u.bounds.zw)) { return float4(0.0); }
        float4 c = image.sample(s, t);
        float a = clamp(c.a, 0.0, 1.0);
        return float4(clamp(c.rgb, float3(0.0), float3(a)), a);
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
        /// MED-008: the animation of `texture` (nil: a still).
        var animation: AnimatedPicture?
        /// MED-006: the slide decoded ahead (`preload`); MED-008: with its animation.
        var preparedURL: URL?
        var preparedTexture: LoadedPicture?
        var preparedToken: UInt64 = 0
        /// PERF-005: loads started by `content` changes.
        var loadsStarted = 0
    }
    let lock = OSAllocatedUnfairLock(uncheckedState: State())

    /// Moves a prepared texture for `url` into the slot under `generation`; false when none is ready.
    func adoptPrepared(_ url: URL, generation: UInt64) -> Bool {
        lock.withLockUnchecked { s in
            guard s.generation == generation, s.preparedURL == url, let picture = s.preparedTexture else { return false }
            s.texture = picture.texture
            s.animation = picture.animation
            s.state = .ready(width: picture.texture.width, height: picture.texture.height)
            s.preparedURL = nil
            s.preparedTexture = nil
            return true
        }
    }

    /// The prepared picture for `url`, taken out of the prepared slot (load queue).
    func takePrepared(_ url: URL) -> LoadedPicture? {
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

/// A loaded picture: the texture drawn as the still (frame 0 of an animation) and its animation (MED-008).
struct LoadedPicture: @unchecked Sendable {
    let texture: MTLTexture
    let animation: AnimatedPicture?
}

/// Matches `ImgUniforms` in the shader (48 bytes: a float4, three float2, padding).
struct ImageUniforms {
    var bounds: SIMD4<Float>
    var visible: SIMD2<Float>
    var offset: SIMD2<Float>
    var outputSize: SIMD2<Float>

    init(geometry: ImagePictureGeometry, outputWidth: Int, outputHeight: Int) {
        bounds = SIMD4(geometry.minX, geometry.minY, geometry.maxX, geometry.maxY)
        visible = SIMD2(geometry.visibleWidth, geometry.visibleHeight)
        offset = SIMD2(geometry.offsetX, geometry.offsetY)
        outputSize = SIMD2(Float(max(outputWidth, 1)), Float(max(outputHeight, 1)))
    }
}
#endif
