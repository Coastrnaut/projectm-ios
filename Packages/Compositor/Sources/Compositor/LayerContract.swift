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

/// How a layer is combined with what is below it. CMP-003 adds opacity (premultiplied channels ×
/// opacity before the mode), CMP-005 transforms (`LayerTransform.swift`), CMP-004 the blend modes
/// (specs/099-cmp-004-blend-mode-library/contracts/blend-modes.md, ADR-0037): W3C Compositing and
/// Blending Level 1 separable functions with source-over, the function on sRGB-encoded straight
/// colours and the coverage in linear light. `LayerBlend` is the plain-Swift reference.
/// The raw value is the stable name (the scene format's `composite.blend`).
public enum LayerBlendMode: String, Sendable, Equatable, CaseIterable {
    /// Premultiplied "over" (B = Cs); drawn with fixed-function blending exactly as before CMP-004.
    case normal
    /// B = min(1, Cb + Cs) (separable, clamped; not Porter-Duff "plus").
    case add
    /// B = Cb + Cs − Cb·Cs.
    case screen
    /// B = Cb·Cs.
    case multiply
    /// B = HardLight(Cs, Cb): 2·Cb·Cs for Cb ≤ 0.5, else screen(Cs, 2·Cb − 1).
    case overlay
    /// B = |Cb − Cs|.
    case difference
}

public struct LayerCompositeSettings: Sendable, Equatable {
    /// 0…1 (clamped; non-finite reads 1).
    public var opacity: Double
    public var blendMode: LayerBlendMode
    public var transform: LayerTransform
    /// CMP-006: how the layer's content is fitted to the output; nil is the layer's own default
    /// (photo and video: fill at the centre). Read only by layers that adopt `LayerFitting`.
    public var fit: LayerFit?

    public init(opacity: Double = 1, blendMode: LayerBlendMode = .normal, transform: LayerTransform = .identity,
                fit: LayerFit? = nil) {
        self.opacity = opacity.isFinite ? min(max(opacity, 0), 1) : 1
        self.blendMode = blendMode
        self.transform = transform
        self.fit = fit
    }

    /// CMP-001 accepts only opacity 1, normal blending and the identity transform (CMP-001-R11).
    public var isSupportedByCMP001: Bool {
        opacity == 1 && blendMode == .normal && transform.isIdentity
    }

    /// What the compositor draws: any opacity (CMP-003), any transform (CMP-005) and every blend mode
    /// (CMP-004). Always true since CMP-004; kept so callers written against CMP-001 still compile.
    public var isSupportedByCompositor: Bool { true }
}

#if canImport(Metal) && !COMPOSITOR_NO_METAL
/// A render-to-texture source (CMP-001-R1). Driven by one thread, the compositor's (not Sendable).
public protocol LayerSource: AnyObject {
    /// For diagnostics only.
    var layerName: String { get }
    /// Read once when the compositor is built.
    var fallback: LayerFallback { get }
    /// Read once when the compositor is built; any opacity, transform and blend mode.
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

/// CMP-006: a layer whose content has its own pixel size (photo, video) and is fitted to the output.
/// The compositor sets `fit` from the stack entry when the layer is added and at every `apply`; the
/// layer computes `LayerFitPlacement` in `render` from the picture's size, so it shows the new fit
/// and any new output size from the next frame without reloading. nil: the layer's own default.
public protocol LayerFitting: AnyObject {
    var fit: LayerFit? { get set }
}

extension LayerSource {
    public var compositeSettings: LayerCompositeSettings { LayerCompositeSettings() }
}
#endif
