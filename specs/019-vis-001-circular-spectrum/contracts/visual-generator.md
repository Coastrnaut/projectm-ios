# Contract: native visual generators (VIS-001; adopted later by CMP-001, VIS-002/003/006/020)

Package `Packages/VisualGenerators`, target `VisualGenerators`. No dependency on projectM, capture,
the app or its settings (VIS-001-R19).

## TextureGenerator (Metal platforms)

```swift
public struct VisualFrameContext: Sendable, Equatable {
    public var timeNanoseconds: UInt64      // monotonic; never wall-clock
    public var frameDuration: Double        // seconds since the previous frame (Reduce flashing)
    public var reduceFlashing: Bool
}

public protocol TextureGenerator: AnyObject {
    var pixelFormat: MTLPixelFormat { get }
    /// Encodes one frame that fully covers `target` (cleared to the configured background).
    /// Returns false when the frame was skipped (no free vertex buffer); nothing is encoded then.
    func encode(into target: MTLTexture, commandBuffer: MTLCommandBuffer,
                bands: UnsafeBufferPointer<Float>, context: VisualFrameContext) -> Bool
}
```

Guarantees:
1. **Ownership**: the caller owns the texture and the command buffer and commits it; the generator
   owns its pipeline and vertex buffers. One thread drives a generator (not Sendable).
2. **Format**: a target whose pixel format differs from `pixelFormat` is refused (`encode` returns false, nothing encoded; never a crash). Supported: `bgra8Unorm_srgb`
   (default) and `rgba16Float`. Colors are linear, premultiplied alpha; the background is written
   premultiplied (opaque black by default).
3. **Size**: any `target.width × target.height ≥ 1`; geometry is laid out for that size every frame,
   so a size change (rotation) needs no call.
4. **Time base**: `timeNanoseconds` is monotonic; the circular spectrum does not animate on its own,
   so equal bands give equal geometry whatever the time.
5. **Input**: band values normalized 0…1 (ANL-002-R8); sanitized per VIS-001-R8.
6. **Real-time**: no allocation, lock, log or I/O in the generator's own code per frame.
7. **Determinism**: identical configuration, bands, size and limiter state give identical geometry
   and vertex bytes.
8. **Failure**: `init` throws `VisualGeneratorError.pipelineUnavailable(String)` or
   `.unsupportedPixelFormat`; it never crashes. Callers fall back (VIS-001-R16).

## Circular spectrum

`CircularSpectrumGenerator(device:pixelFormat:configuration:)`, `configuration` settable between
frames (bar count changes without allocation). Shader source: the `shaderSource` constant, compiled by
`makeLibrary(source:options:)` in `init` (ADR-0009 decision 3). Geometry contract: data-model.md
(`CircularSpectrumLayout`), angle formula VIS-001-R3, radius unit VIS-001-R5.

## Band feed (target VisualBandFeed)

`LiveBandAnalyzer(barCount:)` → `start(reader: any NormalizedPCMReader)`, `stop()` (synchronous: the
timer is cancelled when it returns), `setBarCount(_:)`, `isRunning`, `output: BandFrameBuffer`;
`SpectrumBandFeed(barCount:)` → `pull(from:)`, `bands`, `setBarCount(_:)`, `reset()`. The reader must be an analysis tap (one consumer),
never projectM's ring. Runs only on its own queue.
