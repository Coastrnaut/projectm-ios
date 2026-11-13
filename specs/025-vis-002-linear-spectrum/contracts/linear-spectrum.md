# Contract: Linear spectrum generator (VIS-002)

Extends `specs/019-vis-001-circular-spectrum/contracts/visual-generator.md`; everything stated
there (frame context, pixel formats, premultiplied linear color, skipped frames, no per-frame
allocation) holds.

```swift
public protocol SpectrumTextureGenerator: TextureGenerator {
    var limiter: FlashSafetyLimiter { get }                         // VIS-001-R10, FX-019
    var downstreamLuminance: (any FrameLuminanceTransfer)? { get set } // FX-001-R10
    var barCount: SpectrumBarCount { get set }
}

public protocol FlashAreaLevelSource: AnyObject {                   // FX-019-R4
    func meanLevels<T: FrameLuminanceTransfer>(gain: Float, transfer: T,
                                               into out: UnsafeMutableBufferPointer<FlashLevels>)
}

public final class LinearSpectrumGenerator: SpectrumTextureGenerator {
    public init(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb,
                configuration: LinearSpectrumConfiguration = .init()) throws(VisualGeneratorError)
    public var configuration: LinearSpectrumConfiguration { get set }
    public let layout: LinearSpectrumLayout
}

public final class LinearSpectrumLayout: FlashAreaLevelSource {
    public func layout(values: UnsafeBufferPointer<Float>, frameTime: Double, width: Int, height: Int)
    public func bar(_ k: Int) -> LinearBarGeometry
    public func rectangles(ofBar k: Int) -> (bar: PixelRect?, cap: PixelRect?)
    public func tessellate(into: UnsafeMutablePointer<SpectrumVertex>, capacity: Int, gain: Float) -> Int
    public func resetPeaks()
}
```

Per frame (`encode`): Reduce-flashing slew (`limiter.limitValues`) → `layout(values:frameTime:…)`
(advances the peak caps) → `limiter.gain(for: layout, transfer:…)` over 17 areas, with the glow's
transfer when set → tessellate with that gain → `FlatShapePass` clears to the background and draws.
`CircularSpectrumGenerator` conforms to `SpectrumTextureGenerator` and `CircularSpectrumLayout` to
`FlashAreaLevelSource` without changing their behavior.
