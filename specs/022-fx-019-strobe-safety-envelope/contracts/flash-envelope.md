# Contract: the flash-safety envelope (FX-019; ADR-0011)

Package `FlashSafety` (pure Swift, no dependencies). Every renderer that shows a picture applies
this envelope to every frame: Reduce flashing on → `.reduceFlashing`, off → `.alwaysOn`.

## Swift API

```swift
public struct FlashLevels: Sendable, Equatable { public var luminance, redness: Double }
public enum FlashZones { gridSide = 4, tileCount = 16, count = 17, wholeFrame = 16 }

public struct FlashEnvelopeConfiguration: Sendable, Equatable {
    window, luminanceThreshold, rednessThreshold, transitionBudget, riseRatePerSecond?, gateMargin, maxFrameTime
    static let reduceFlashing, alwaysOn
    static func forReduceFlashing(_ on: Bool) -> Self
}

public final class FlashEnvelope {            // one per picture; one thread; not Sendable
    init()
    func reset()                               // next frame starts clean (suspension, new visual)
    var lastGain: Float { get }
    // Levels scale linearly with the gain (projectM, reference for the GPU port): closed form.
    func gain(inputs: UnsafeBufferPointer<FlashLevels>, frameTime: Double,
              configuration: FlashEnvelopeConfiguration) -> Float
    // Levels are nondecreasing in the gain (native visuals with a background and a glow):
    // 24 bisection steps; `levels(g, out)` writes all 17 areas.
    func gain(frameTime: Double, configuration: FlashEnvelopeConfiguration,
              levels: (Float, UnsafeMutableBufferPointer<FlashLevels>) -> Void) -> Float
}

public enum FlashAnalysis { static func analyze(_ values: [Double], frameTimes: [Double], threshold: Double, window: Double) -> FlashReport }
public enum FlashColor { decodeSRGB, relativeLuminance, redness, tileLevels(rgba:width:height:into:) }
```

Guarantees for any input (finite or not) and any frame times:
1. 0 ≤ gain ≤ 1, so the output is never brighter than the input (FX-019-R5).
2. Measured on the output with `FlashAnalysis`, every area and signal has at most
   `transitionBudget` transitions in any window (FX-019-R6).
3. With a rise rate, every area's signal rises at most rate × clamped frame time per frame, plus
   nothing (the first frame after `reset` is shown as it is).
4. Deterministic: identical inputs give identical gains. No allocation per call.

## C API (`CFlashLimiter.h`)

```c
typedef struct PMFlashEnvelopeParameters {
    float frameTime;            // clamped by the caller to 0…maxFrameTime
    float window;
    float luminanceThreshold, rednessThreshold;
    float gateMargin;
    float riseRatePerSecond;    // < 0: no rate limit
    int transitionBudget;       // 2…6
} PMFlashEnvelopeParameters;

void PMFlashLimiterFinish(PMFlashLimiter *, unsigned int targetFramebuffer, const PMFlashEnvelopeParameters *);
float PMFlashLimiterLastGain(PMFlashLimiter *);   // tests: reads back one texel
```

`Begin` keeps the envelope state across size changes; `Reset` starts clean. Rendering's
`FlashEnvelopeConfiguration.limiterParameters(frameTime:)` builds the struct.

## Native transfer extension

`FrameLuminanceTransfer.outputRedness(ofFlatColor:) -> Double` (default: the color's redness):
an upper bound of the redness one unit of area of that color contributes after downstream stages,
nondecreasing when the color is scaled up. `BloomLuminanceModel` returns own + intensity ×
redness(thresholded color).
