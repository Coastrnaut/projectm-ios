// TextLayerSource.swift — a styled message as a CMP-001 layer (MED-009-R8, R9, R17; research
// MED-009-D3; contracts/text-layer.md "Layer source").
//
// Setting `spec`, or a new picture size in `prepare`, starts one rasterization on a background
// serial queue: `TextRasterizer` draws the canvas, its pixels are converted once to linear
// premultiplied half floats and uploaded into an `.rgba16Float` texture of the canvas's size. The
// result goes into a slot guarded by an unfair lock, tagged with a generation so a stale result is
// dropped. `render` never draws text: it takes the slot only when its lock is free this instant
// (otherwise it keeps the texture it holds), clears the picture with an empty render pass and blits
// the texture to the canvas's place; it throws `.notReady` while there is no texture for this picture
// size, so the compositor shows the transparent fallback. No Metal source (SHD-011): a clear and a
// blit need no shader. An empty message drops the texture at once. Not Sendable: the compositor's
// thread sets `spec` and renders; `onStateChange` is called on the main actor.
// CMP-013 (ADR-0040): the picture depends only on the held upload (and the picture size, in the cache key),
// so the layer declares itself still (`LayerRenderCaching`) with content = the held upload's serial (bumped
// every time the slot's upload is replaced or dropped). The dependency read takes the slot exactly as
// `render` does. A reused frame still counts in `framesShown`; `renderCount` counts actual renders.

/// The text layer's state (data-model "TextLayerState").
public enum TextLayerState: Sendable, Equatable {
    /// No text to draw.
    case empty
    /// A rasterization is running (a previous rendering may still be shown).
    case drawing
    /// The shown rendering: its canvas size and pixel checksum.
    case ready(width: Int, height: Int, checksum: UInt64)
    /// The rendering or its upload failed; the text says which.
    case failed(String)
}

#if canImport(Metal) && !COMPOSITOR_NO_METAL && canImport(CoreText)
import Compositor
import Foundation
import Metal
import os

public final class TextLayerSource: LayerSource, LayerRenderCaching {
    public let layerName = "text"
    public let fallback = LayerFallback.transparent
    public let device: MTLDevice
    private let work = DispatchQueue(label: "MED-009 text rasterization", qos: .userInitiated)
    private let slot = TextRenderSlot()
    /// The upload drawn last frame (render side only).
    private var held: TextUpload?
    /// CMP-013: the slot's upload serial of `held`.
    private var heldSerial: UInt64 = 0
    /// The last prepared picture size.
    private var pictureSize: (width: Int, height: Int)?
    /// Frames that showed the text (diagnostics, tests), including frames whose picture was reused.
    public private(set) var framesShown = 0
    /// CMP-013: frames that drew the text (render calls that succeeded).
    public private(set) var renderCount = 0

    public init(device: MTLDevice) {
        self.device = device
    }

    /// Called on the main actor after every state change.
    public var onStateChange: (@MainActor @Sendable (TextLayerState) -> Void)? {
        get { slot.lock.withLockUnchecked { $0.handler } }
        set { slot.lock.withLockUnchecked { $0.handler = newValue } }
    }

    /// The current state (read under the slot's lock; not for the render path).
    public var state: TextLayerState { slot.lock.withLockUnchecked { $0.state } }

    /// The CPU rendering behind the newest upload (tests, DEBUG diagnostics).
    public var lastRendering: TextRendering? { slot.lock.withLockUnchecked { $0.upload?.rendering } }

    /// What the layer draws; may change at any time (R17).
    public var spec: TextOverlaySpec = .default {
        didSet {
            guard spec != oldValue else { return }
            startRasterization()
        }
    }

    /// Tests only: returns when every rasterization started so far has finished.
    public func waitUntilRendered() { work.sync {} }

    private func startRasterization() {
        let spec = self.spec
        let empty = spec.isEmpty
        let generation: UInt64 = slot.lock.withLockUnchecked { s in
            s.generation &+= 1
            if empty {
                s.upload = nil
                s.uploadSerial &+= 1
                s.state = .empty
            } else if pictureSize != nil {
                s.state = .drawing
            }
            if empty {   // dropped at once (CMP-013: with its serial, so no key matches it again)
                held = nil
                heldSerial = s.uploadSerial
            }
            return s.generation
        }
        slot.notify()
        guard !empty, let size = pictureSize else { return }
        let slot = self.slot, device = self.device
        work.async {
            let upload = Self.rasterize(spec, width: size.width, height: size.height, device: device)
            let stored: Bool = slot.lock.withLockUnchecked { s in
                guard s.generation == generation else { return false }   // a newer spec or size won
                switch upload {
                case .success(let u):
                    s.upload = u
                    s.uploadSerial &+= 1
                    s.state = .ready(width: u.rendering.width, height: u.rendering.height, checksum: u.rendering.checksum)
                case .failure(let message):
                    s.upload = nil
                    s.uploadSerial &+= 1
                    s.state = .failed(message.text)
                }
                return true
            }
            if stored { slot.notify() }
        }
    }

    struct Failure: Error { let text: String }

    /// Draws and uploads (background queue).
    static func rasterize(_ spec: TextOverlaySpec, width: Int, height: Int, device: MTLDevice) -> Result<TextUpload, Failure> {
        guard let rendering = TextRasterizer.render(spec, pictureWidth: width, pictureHeight: height) else {
            return .failure(Failure(text: "text could not be drawn"))
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: LayerPictureDescriptor.metalPixelFormat,
                                                         width: rendering.width, height: rendering.height, mipmapped: false)
        d.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: d) else { return .failure(Failure(text: "text texture")) }
        texture.label = "MED-009 text"
        let halves = rendering.linearHalfPixels()
        halves.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            texture.replace(region: MTLRegionMake2D(0, 0, rendering.width, rendering.height), mipmapLevel: 0,
                            withBytes: bytes.baseAddress!, bytesPerRow: rendering.width * 8)
        }
        return .success(TextUpload(texture: texture, rendering: rendering))
    }

    public func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {
        if let size = pictureSize, size == (picture.width, picture.height) { return }
        pictureSize = (picture.width, picture.height)
        startRasterization()
    }

    public func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                       audio: LayerAudioContext) throws(LayerSourceError) {
        takeNewest()
        guard let upload = held, upload.rendering.pictureWidth == picture.width,
              upload.rendering.pictureHeight == picture.height else { throw .notReady }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = picture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let clear = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { throw .frameSkipped }
        clear.label = "MED-009 text clear"
        clear.endEncoding()
        let r = upload.rendering
        let width = min(r.width, picture.width - r.x), height = min(r.height, picture.height - r.y)
        guard width > 0, height > 0 else { return }
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { throw .frameSkipped }
        blit.label = "MED-009 text"
        blit.copy(from: upload.texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: picture, destinationSlice: 0,
                  destinationLevel: 0, destinationOrigin: MTLOrigin(x: r.x, y: r.y, z: 0))
        blit.endEncoding()
        framesShown += 1
        renderCount += 1
    }

    /// The newest upload, when the slot's lock is free this instant (otherwise the held one stays).
    private func takeNewest() {
        if let newest: (TextUpload?, UInt64) = slot.lock.withLockIfAvailableUnchecked({ ($0.upload, $0.uploadSerial) }) {
            held = newest.0
            heldSerial = newest.1
        }
    }

    /// CMP-013: still; the held upload's serial.
    public var renderDependencies: LayerRenderDependencies {
        takeNewest()
        return .still(content: heldSerial)
    }

    public func renderReused(frame: LayerFrameContext) { framesShown += 1 }
}

/// One uploaded rendering.
struct TextUpload {
    let texture: MTLTexture
    let rendering: TextRendering
}

/// The rasterization result shared between the background queue and the render thread.
final class TextRenderSlot: Sendable {
    struct State {
        var generation: UInt64 = 0
        var upload: TextUpload?
        /// CMP-013: bumped whenever `upload` is replaced or dropped.
        var uploadSerial: UInt64 = 0
        var state: TextLayerState = .empty
        var handler: (@MainActor @Sendable (TextLayerState) -> Void)?
    }
    let lock = OSAllocatedUnfairLock(uncheckedState: State())

    /// Hands the state to the handler on the main actor, read when it is delivered (the last
    /// delivery is always the current state).
    func notify() {
        guard lock.withLockUnchecked({ $0.handler != nil }) else { return }
        Task { @MainActor [self] in
            let (state, handler) = lock.withLockUnchecked { ($0.state, $0.handler) }
            handler?(state)
        }
    }
}
#endif
