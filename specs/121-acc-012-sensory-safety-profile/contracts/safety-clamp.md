# Contract: Safety clamp (ACC-012)

## C1 SafetyClamp (FlashSafety, public)

```swift
public struct SafetyClamp: Sendable, Equatable {
    public static let standard: SafetyClamp
    public init(profile: SensorySafetyProfile, reduceFlashingSetting: Bool)
    public let limits: SensorySafetyLimits          // effective, after precedence
    public let reducesFlashing: Bool                 // setting || flash limit stricter than Standard
    public var flashConfiguration: FlashEnvelopeConfiguration
    public var flashLimitsOverride: FlashEnvelopeConfiguration?   // nil = renderer keeps forReduceFlashing(reducesFlashing)
    public var isIdentity: Bool                      // Standard limits and Reduce flashing off
    public func intensity(_ value: Float, maximum: Float) -> Float          // limit 1 → value unchanged
    public func modulated(manual: Double, modulated: Double) -> Double      // limit 1 → modulated unchanged
    public func speed(_ value: Double, cap: Double) -> Double               // limit 1 → value unchanged
}
```

Precedence: the effective flash limit is the stricter of the profile's and (when the Reduce flashing
setting is on) Reduced's; the intensity limit is the profile's.

## C2 Renderer inputs (the clamp point)

| Consumer | Input | Set by |
|---|---|---|
| Native generators (`FlashSafetyLimiter`) | `VisualFrameContext.flashLimits` (nil = `forReduceFlashing(reduceFlashing)`) | `NativeSpectrumHost.safetyClamp` |
| Native glow (`BloomEffect.parameters`, luminance model) | `glow` → MOD-002 → `modulated` → `intensity` | `NativeSpectrumHost.resolveEffectiveGlow()` |
| projectM (`ANGLERenderer`, GLSL envelope) | `flashLimits` | `AppCoordinator.applyReduceFlashing()` |
| Compositor final guard (camera, photo, video, text) | `Compositor.flashLimits` | same |
| SHD-002 graph layer | `intensityLimit` → `effectiveSpeed` before `GraphMotion.advance` | layer owner |

Every consumer with a nil override and limit 1 runs exactly today's code path.

## C3 Settings UI

Section "Sensory safety" (identifier `sensorySafetySection`): segmented picker `sensorySafetyProfilePicker`
(Standard, Reduced, Strict, Custom); while Custom, a flashes-per-second stepper
(`sensorySafetyFlashesStepper`), rise limit slider (`sensorySafetyRiseSlider`, 0 = none) and intensity
slider (`sensorySafetyIntensitySlider`), both with `.accessibleParameter`; help footer; DEBUG probe
`sensorySafetyProbe` with text "glow <rendered> flashes <f>/s rise <r|none> intensity <limit>". A profile
change is announced on the announcer's `safety` lane ("Sensory safety: Strict").
