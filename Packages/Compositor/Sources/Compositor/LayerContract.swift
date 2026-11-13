// LayerContract.swift — the layer contract (CMP-001-R1, R5, R7, R8, R11; research CMP-001-D6, D7;
// contracts/layer-source.md "Layer source").
//
// CPU part (every host): fallbacks, typed errors, outcomes and composite settings. Metal part: the
// `LayerSource` protocol. A source draws a whole compositor-owned picture per frame from the frame
// and audio contexts it is given; it knows nothing about other layers, the output, projectM, ANGLE,
// capture or the app. Throwing from `render` means "do not show what this frame drew"; the
// compositor then shows the declared fallback and reports the error.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal
#endif

/// What the compositor shows for a layer whose frame failed.
public enum LayerFallback: Sendable, Equatable {
    /// Nothing of the layer for that frame.
    case transparent
    /// The layer's last successful picture (nothing before the first success).
    case lastGoodFrame
}

/// Why a layer did not produce a frame or a picture (typed throws: no allocation for the
/// payload-free cases).
public enum LayerSourceError: Error, Sendable, Equatable {
    /// Content not ready yet (loading, no input).
    case notReady
    /// This frame was skipped (e.g. no buffer free); the next may succeed.
    case frameSkipped
    /// The layer cannot draw pictures of this description.
    case unsupportedPicture(LayerPictureDescriptor)
    /// A GPU or system resource could not be created; the text names it.
    case resourceUnavailable(String)
    /// An engine the layer owns failed; the text is the engine's.
    case engineFailure(String)
}

/// What happened to one layer in the last frame.
public enum LayerOutcome: Sendable, Equatable {
    /// No frame composited yet (or the output was empty).
    case notRendered
    case rendered
    case fallbackTransparent(LayerSourceError)
    case fallbackLastGood(LayerSourceError)
    /// `prepare` failed; skipped until the next size change or `retryUnavailableLayers()`.
    case unavailable(LayerSourceError)

    /// True when this frame's own picture was composited.
    public var isShown: Bool { self == .rendered }
}

/// How a layer is combined with what is below it. CMP-001 composites with the identity values only;
/// CMP-003 (opacity), CMP-004 (blend modes) and CMP-005 (transforms) extend the compositor.
public enum LayerBlendMode: Sendable, Equatable {
    /// Premultiplied "over".
    case normal
}

/// A 2D affine transform in output pixels: x' = a·x + c·y + tx, y' = b·x + d·y + ty.
public struct LayerTransform: Sendable, Equatable {
    public var a, b, c, d, tx, ty: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }

    public static let identity = LayerTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
}

public struct LayerCompositeSettings: Sendable, Equatable {
    /// 0…1 (clamped; non-finite reads 1).
    public var opacity: Double
    public var blendMode: LayerBlendMode
    public var transform: LayerTransform

    public init(opacity: Double = 1, blendMode: LayerBlendMode = .normal, transform: LayerTransform = .identity) {
        self.opacity = opacity.isFinite ? min(max(opacity, 0), 1) : 1
        self.blendMode = blendMode
        self.transform = transform
    }

    /// CMP-001 accepts only opacity 1, normal blending and the identity transform (CMP-001-R11).
    public var isSupportedByCMP001: Bool {
        opacity == 1 && blendMode == .normal && transform == .identity
    }
}

#if canImport(Metal) && !COMPOSITOR_NO_METAL
/// A render-to-texture source (CMP-001-R1). Driven by one thread, the compositor's (not Sendable).
public protocol LayerSource: AnyObject {
    /// For diagnostics only.
    var layerName: String { get }
    /// Read once when the compositor is built.
    var fallback: LayerFallback { get }
    /// Read once when the compositor is built; CMP-001 accepts only the identity values.
    var compositeSettings: LayerCompositeSettings { get }
    /// Called once before the first frame and once per size change. The only place a source may
    /// create its own working resources.
    func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError)
    /// Draws the whole `picture` (clear first) into `commandBuffer`, which the caller commits. Must
    /// not commit, wait for the GPU, allocate, lock with unbounded wait, log or do I/O, and must not
    /// keep `picture`, `audio.bands` or `audio.events` after returning.
    func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                audio: LayerAudioContext) throws(LayerSourceError)
}

extension LayerSource {
    public var compositeSettings: LayerCompositeSettings { LayerCompositeSettings() }
}
#endif
