# Contract: layer sources and the compositor (CMP-001)

The render boundary for every later visual row (CMP-002…015, MED, CAM, OUT, REC, SCN). Package
`Packages/Compositor`, module `Compositor` (ADR-0012; research CMP-001-D1 to D8). Swift 6, strict
concurrency. Types marked *Metal* exist only when `canImport(Metal) && !COMPOSITOR_NO_METAL`.

## Pictures (CMP-001-R1, R2, R6; research CMP-001-D2)

`LayerPictureDescriptor { width, height, format: .rgba16Float, colorSpace: .linearSRGB,
alpha: .premultiplied, origin: .topLeft }` describes every picture a layer receives. On Metal:
pixel format `rgba16Float`, storage `.private`, usage `[.renderTarget, .shaderRead, .shaderWrite]`.

- The compositor creates pictures, before the first frame and when the output size changes,
  exactly once per change; at a steady size it creates nothing.
- A source draws the **whole** picture every frame (clear first; transparent is
  `(0, 0, 0, 0)`), linear premultiplied values, row 0 at the top.
- A source MUST NOT keep a reference to a picture after `render` returns, nor read it on a later
  frame (with *last good frame* the compositor alternates two pictures).

## Context (CMP-001-R3, R4; research CMP-001-D3)

```swift
public struct LayerFrameContext: Sendable, Equatable {
    public var presentationTimeNanoseconds: UInt64   // monotonic, never decreasing
    public var frameIndex: UInt64                    // 0, 1, 2… per composited frame
    public var frameDuration: Double                 // seconds, 0…0.1; 0 on frame 0
    public var outputWidth: Int, outputHeight: Int   // pixels
    public var contentScale: Double                  // pixels per point (1 when unknown)
    public var reduceFlashing: Bool                  // FR-072
}

public struct LayerAudioContext {                   // plain values; valid during the call only
    public var frame: AnalysisFrame?                 // ANL-016-R2 metadata of the latest frame
    public var bands: UnsafeBufferPointer<Float>     // its bands, 0…1, at most 128
    public var events: UnsafeBufferPointer<AnalysisEvent>  // since the previous frame, oldest first, ≤ 64
    public var droppedEvents: Int                    // events not delivered (oldest dropped)
    public static let empty: LayerAudioContext
}
```

`LayerAudioBuffer` (preallocated) fills a context: `update(from: AnalysisSubscription)` or
`set(frame:bands:events:)`; `context` returns the value to pass to `composite`.

## Layer source (*Metal*; CMP-001-R1, R5, R7, R11)

```swift
public protocol LayerSource: AnyObject {
    var layerName: String { get }                         // diagnostics only
    var fallback: LayerFallback { get }                   // .transparent or .lastGoodFrame
    var compositeSettings: LayerCompositeSettings { get } // default: opacity 1, .normal, .identity
    func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError)
    func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer,
                frame: LayerFrameContext, audio: LayerAudioContext) throws(LayerSourceError)
}
```

- `prepare` is called once before the first frame and once per size change, on the compositor's
  thread; the source may create its own working resources there (and only there).
- `render` encodes into `commandBuffer` (the caller commits); it MUST NOT commit, wait for the GPU,
  allocate, lock with unbounded wait, log or do I/O. Throwing means "do not show what this frame
  drew"; the compositor shows the declared fallback.
- A source knows nothing about other layers, the compositor's output, projectM, ANGLE, capture or
  the app. A source may own an engine (the projectM layer) as long as nothing of it crosses the
  protocol.
- One layer object appears at most once in a compositor.

`LayerSourceError`: `.notReady`, `.frameSkipped`, `.unsupportedPicture(LayerPictureDescriptor)`,
`.resourceUnavailable(String)`, `.engineFailure(String)`.

## Compositor (*Metal*; CMP-001-R6 to R10, R15)

```swift
public final class Compositor {
    public init(device: MTLDevice, layers: [any LayerSource]) throws(CompositorError)
    public var layerCount: Int { get }
    /// One frame into `output` (any of .bgra8Unorm_srgb, .rgba16Float, .bgra8Unorm, .rgba8Unorm;
    /// render-target usage). Returns false and encodes nothing for a 0-sized output.
    public func composite(into output: MTLTexture, commandBuffer: MTLCommandBuffer,
                          presentationTimeNanoseconds: UInt64, contentScale: Double,
                          reduceFlashing: Bool, audio: LayerAudioContext) -> Bool
    public func outcome(ofLayer index: Int) -> LayerOutcome   // the last frame's
    public var pictureAllocations: Int { get }                // tests, diagnostics
    public func retryUnavailableLayers()
    public func resetFlashHistory()                           // a new scene (FX-019-R11)
}
```

Per frame, in order: frame clock → for each layer bottom to top: render into its free picture →
outcome (`.rendered`, `.fallbackTransparent(error)`, `.fallbackLastGood(error)`,
`.unavailable(error)`) → accumulate with premultiplied "over" into the composite (`rgba16Float`,
cleared to transparent) → `CompositeFlashGuard` (compute: 17 areas, both signals, envelope
`.forReduceFlashing(reduceFlashing)`) → output pass `rgb × gain, a`. Not Sendable: one thread drives
a compositor and its layers.

`CompositorError`: `.noCommandQueue`, `.pipelineUnavailable(String)`,
`.duplicateLayer(index: Int)`, `.unsupportedCompositeSettings(index: Int)`.

## Adapters

- `SpectrumLayerSource` (module `SpectrumLayers`): `init(device:generator:glow:)` with any
  `SpectrumTextureGenerator` built for `rgba16Float`; bands from `audio.bands`; frame duration and
  Reduce flashing from the frame context; fallback `.lastGoodFrame`; a skipped frame throws
  `.frameSkipped`. Glow: an FX-001 `BloomEffect` in an `EffectChain`, with the generator's
  `downstreamLuminance` set as the app host does.
- `ProjectMLayerSource` (module `ProjectMLayer`, package `ANGLERendering`): its own EGL context and
  engine on ANGLE's Metal display; requires `EGL_ANGLE_metal_texture_client_buffer` and
  `EGL_ANGLE_metal_shared_event_sync` (checked at init, else
  `ProjectMLayerError.missingExtension(name)`); `attach(pcm:)` like `ANGLERenderer`; `loadPreset`;
  fallback `.lastGoodFrame`. Per frame: the engine renders into a GL framebuffer over the layer's
  `bgra8Unorm` texture, ANGLE signals a shared event, the compositor's command buffer waits for it,
  and a pass flips the picture upright, decodes sRGB and writes opaque linear pixels. It restores the
  caller's EGL binding after each call.
