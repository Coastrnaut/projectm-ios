# Contract: post-processing effects (FX-001; adopted later by FX-002…FX-020, CMP-001)

Package `Packages/VisualGenerators`, target `VisualEffects` (depends only on the `VisualGenerators`
target). No dependency on projectM, capture, generators' internals, the app or its settings.

## PostProcessEffect (Metal platforms)

```swift
public protocol PostProcessEffect: AnyObject {
    /// Stable identifier (`fx.bloom`); never reused for another effect.
    var identifier: EffectIdentifier { get }
    /// The only pixel format of `input` and `output`.
    var pixelFormat: MTLPixelFormat { get }
    /// True when encode would reproduce the input exactly; the chain then skips the effect.
    var isPassThrough: Bool { get }
    /// Creates or resizes working textures for an output of width × height. Allocates only when the
    /// size changed; cheap otherwise. Must be called before `encode` for that size.
    func prepare(width: Int, height: Int) throws(VisualGeneratorError)
    /// Encodes input → output (same size, same pixel format) into `commandBuffer`, which the caller
    /// commits. Returns false, encoding nothing, when the sizes or formats do not match the prepared
    /// ones. `input` and `output` must be different textures.
    func encode(input: MTLTexture, output: MTLTexture, commandBuffer: MTLCommandBuffer) -> Bool
}
```

Guarantees:

1. **Color**: linear light, premultiplied alpha, in and out. `bgra8Unorm_srgb` targets are decoded
   on read and encoded on write by the GPU; `rgba16Float` is linear and may exceed 1.
2. **Ownership**: the caller owns `input`, `output` and the command buffer; the effect owns its
   pipelines and working textures (`.private`). `output` may be `framebufferOnly` (a drawable):
   effects write it only from a render pass. `input` needs `.shaderRead`.
3. **Real-time**: per frame no texture, buffer, pipeline or Swift heap allocation; small uniforms go
   through `setBytes`. Not Sendable: one thread drives an effect.
4. **Determinism**: identical input, parameters and size give identical output bits on one device.
5. **Pass-through**: when `isPassThrough`, `encode` copies the input exactly (blit, or a copy render
   pass when `output.isFramebufferOnly`).
6. **Failure**: `init` throws `VisualGeneratorError.pipelineUnavailable` or
   `.unsupportedPixelFormat`; never a crash. Callers render without the effect (FX-001-R13).
7. **Luminance**: an effect that changes brightness offers a `FrameLuminanceTransfer` (target
   `VisualGenerators`) bounding its output luminance for flat colors, so Reduce flashing can limit
   the composited frame (FX-001-R10).

## EffectChain (Metal platforms)

```swift
public final class EffectChain {
    public init(device: MTLDevice, pixelFormat: MTLPixelFormat, effects: [any PostProcessEffect]) throws(VisualGeneratorError)
    public var effects: [any PostProcessEffect] { get }   // order of application
    public var activeEffectCount: Int { get }              // effects not pass-through
    public func prepare(width: Int, height: Int) throws(VisualGeneratorError)
    /// `source` draws the frame into the texture it is given (the output itself when every effect
    /// is pass-through, else the chain's source image) and returns false to skip the frame.
    public func encode(output: MTLTexture, commandBuffer: MTLCommandBuffer,
                       source: (MTLTexture) -> Bool) -> Bool
}
```

- No active effect: `source(output)` only (zero extra GPU work; VIS-001's picture bit for bit).
- One active effect: `source(A)`, effect A → output. Two or more: ping-pong between A and B, the last
  effect writes `output`.
- `A` and `B` are `.private` textures in `pixelFormat` with `.renderTarget | .shaderRead`, created by
  `prepare` when the size changes (B only when two or more effects are present).

## Bloom

`BloomEffect(device:pixelFormat:parameters:)`; `pixelFormat` ∈ {`bgra8Unorm_srgb`,
`rgba16Float`}; `parameters: BloomParameters` settable between frames (CPU-only update);
`plan: BloomPlan?` after `prepare`. Algorithm and bounds: research.md FX-001-D3.

## Chain description (all platforms, for FX-020)

```json
{ "formatVersion": 1,
  "effects": [ { "id": "fx.bloom",
                 "parameters": { "enabled": true, "intensity": 0.5, "radius": 0.02,
                                 "threshold": 0.7, "knee": 0.5 } } ] }
```

Decoding clamps parameters, keeps unknown ids as `.unknown`, and rejects `formatVersion > 1` and
more than 16 effects.
