// LogoLayerSource.swift — the MED-010 logo as a CMP-001 layer (MED-010-R4 to R8; research MED-010-D2,
// D4, D5; contracts/logo-overlay.md C3).
//
// * Load: setting `content` starts one load on a background serial queue: a bounded read of the stored
//   copy (`LogoImport.limits`), the MED-014 decoder, `PremultipliedLinear.texels` (sRGB → linear × alpha
//   on the CPU) and a mipmapped `rgba16Float` texture whose mip chain is built from those premultiplied
//   texels. Filtering therefore never mixes the colour of transparent texels into soft edges (no dark
//   fringe at any scale). The slot, generations and main-actor notifications are MED-001's
//   `ImageLoadSlot`, so a stale load is dropped and `render` never waits for a lock.
// * Draw: the picture is cleared and the logo's rectangle (`LogoPlacement.rect`, output pixels) is drawn
//   by one full-screen triangle whose fragment maps each pixel centre into the logo (transparent
//   outside), samples trilinearly and multiplies the premultiplied colour by the opacity. Opacity 0
//   draws nothing. No logo, a load in flight or a failed load: `.notReady` (the transparent fallback).
// * CMP-013: the layer is still: content = the held image's load generation, parameters = a
//   placement generation, so it is drawn again only when the image, the placement or the picture
//   size changes.
// The shader is a module constant in ImageLayerSource.swift, one of the reviewed Metal source files (SHD-011,
// `check_compliance.py`'s METAL_SOURCE_ALLOWED), so no new file compiles Metal source.
// Not Sendable: the compositor's thread (the main thread in the app) sets `content`/`placement` and renders.
import Foundation

#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal
import os

public final class LogoLayerSource: LayerSource, LayerRenderCaching {
    public let layerName = "logo"
    public let fallback = LayerFallback.transparent
    public let device: MTLDevice
    private let decoder: any ImageDecoding
    private let limits: ImageImportLimits
    private let loads = DispatchQueue(label: "MED-010 logo load", qos: .userInitiated)
    private let slot = ImageLoadSlot()
    private var pipeline: MTLRenderPipelineState?
    private var sampler: MTLSamplerState?
    private var held: MTLTexture?
    private var heldGeneration: UInt64 = 0
    private var placementGeneration: UInt64 = 0
    /// Frames that showed the logo (including reused pictures).
    public private(set) var framesShown = 0
    /// CMP-013: frames that drew the logo.
    public private(set) var renderCount = 0

    /// Where and how strongly the logo is drawn; shown from the next frame (no reload).
    public var placement: LogoPlacement = .default {
        didSet { if placement != oldValue { placementGeneration &+= 1 } }
    }

    /// Called on the main actor after every state change.
    public var onStateChange: (@MainActor @Sendable (ImageLayerState) -> Void)? {
        get { slot.lock.withLockUnchecked { $0.handler } }
        set { slot.lock.withLockUnchecked { $0.handler = newValue } }
    }

    public init(device: MTLDevice, decoder: any ImageDecoding = ImageIODecoder(), limits: ImageImportLimits = LogoImport.limits) {
        self.device = device
        self.decoder = decoder
        self.limits = limits
    }

    public var state: ImageLayerState { slot.lock.withLockUnchecked { $0.state } }

    /// The logo shown. Setting it drops the current image at once and, for a file, starts its load.
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
            heldGeneration = generation
            slot.notify()
            guard case .file(let url) = content else { return }
            let slot = self.slot, device = self.device, decoder = self.decoder, limits = self.limits
            loads.async {
                let result: Result<MTLTexture, ImageImportError> = Self.load(url, device: device, decoder: decoder, limits: limits)
                let stored: Bool = slot.lock.withLockUnchecked { s in
                    guard s.generation == generation else { return false }
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

    /// Tests only: returns when every load started so far has finished.
    public func waitUntilLoaded() { loads.sync {} }

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

    /// A mipmapped `rgba16Float` texture of the premultiplied linear texels (research MED-010-D2).
    public static func makeTexture(_ image: DecodedImage, device: MTLDevice) -> MTLTexture? {
        let texels: [UInt16] = PremultipliedLinear.texels(image)
        guard image.width >= 1, image.height >= 1, !texels.isEmpty else { return nil }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: image.width,
                                                         height: image.height, mipmapped: true)
        d.usage = [.shaderRead]
        d.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: d) else { return nil }
        texture.label = "MED-010 logo"
        texels.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            texture.replace(region: MTLRegionMake2D(0, 0, image.width, image.height), mipmapLevel: 0,
                            withBytes: bytes.baseAddress!, bytesPerRow: image.width * 8)
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
        if pipeline != nil { return }
        do {
            let library = try ImageLayerSource.logoLibrary(device: device)   // the reviewed shader file (SHD-011)
            guard let vertex = library.makeFunction(name: "logo_fullscreen"),
                  let fragment = library.makeFunction(name: "logo_picture") else {
                throw LayerSourceError.resourceUnavailable("logo shader functions")
            }
            let d = MTLRenderPipelineDescriptor()
            d.label = "MED-010 logo"
            d.vertexFunction = vertex
            d.fragmentFunction = fragment
            d.colorAttachments[0].pixelFormat = LayerPictureDescriptor.metalPixelFormat
            pipeline = try device.makeRenderPipelineState(descriptor: d)
        } catch let error as LayerSourceError {
            throw error
        } catch {
            throw .resourceUnavailable("logo pipeline: \(error)")
        }
        let s = MTLSamplerDescriptor()
        s.minFilter = .linear
        s.magFilter = .linear
        s.mipFilter = .linear
        s.sAddressMode = .clampToEdge
        s.tAddressMode = .clampToEdge
        guard let state = device.makeSamplerState(descriptor: s) else {
            pipeline = nil
            throw .resourceUnavailable("logo sampler")
        }
        sampler = state
    }

    public func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                       audio: LayerAudioContext) throws(LayerSourceError) {
        takeNewest()
        guard let image = held, let pipeline, let sampler else { throw .notReady }
        let rect: LogoRect = placement.rect(logoWidth: image.width, logoHeight: image.height,
                                            outputWidth: picture.width, outputHeight: picture.height)
        var uniforms = LogoUniforms(rect: rect, opacity: placement.opacity)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = picture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { throw .frameSkipped }
        encoder.label = "MED-010 logo"
        if placement.opacity > 0, !rect.isEmpty {   // opacity 0 draws nothing (the picture stays clear)
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(image, index: 0)
            encoder.setFragmentSamplerState(sampler, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<LogoUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.endEncoding()
        framesShown += 1
        renderCount += 1
    }

    private func takeNewest() {
        if let newest: (MTLTexture?, UInt64) = slot.lock.withLockIfAvailableUnchecked({ ($0.texture, $0.generation) }) {
            held = newest.0
            heldGeneration = newest.1
        }
    }

    /// CMP-013: still; the held image's load generation and the placement generation.
    public var renderDependencies: LayerRenderDependencies {
        takeNewest()
        return .still(content: heldGeneration, parameters: placementGeneration)
    }

    public func renderReused(frame: LayerFrameContext) { framesShown += 1 }
}

/// Matches `LogoUniforms` in the shader (32 bytes).
struct LogoUniforms {
    var rect: SIMD4<Float>
    var params: SIMD4<Float>

    init(rect: LogoRect, opacity: Double) {
        self.rect = SIMD4(Float(rect.x), Float(rect.y), Float(max(rect.width, 1e-6)), Float(max(rect.height, 1e-6)))
        params = SIMD4(Float(opacity), 0, 0, 0)
    }
}
#endif
