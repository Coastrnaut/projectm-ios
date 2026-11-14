# Contract: effect quality ladder (PERF-003)

## C1 `EffectQualityLadder`

```swift
public final class EffectQualityLadder {
    public init(policy: EffectQualityPolicy = .standard)
    public func start(thermal: EffectThermalState, lowPower: Bool)
    public func step(time: Double, thermal: EffectThermalState, lowPower: Bool, budget: EffectBudgetSignal)
    public private(set) var target: EffectQualityLevel
    public private(set) var applied: EffectQualityLevel
    public private(set) var glowWeight: Float
    public var intensityFactor: Float { get }
    public private(set) var reason: EffectQualityReason?
    public var overlayLine: String { get }   // "effect quality full" / "effect quality reduced (thermal)"
    public static func floor(thermal: EffectThermalState, lowPower: Bool) -> EffectQualityLevel
}
```

No allocation in `step`; deterministic for the same input sequence.

## C2 Bloom quality

- `BloomPlan(parameters:width:height:quality:)`; `.full` equals `BloomPlan(parameters:width:height:)`.
- `BloomEffect.quality`: a change rebuilds the plan once; `.minimal` → `isPassThrough`.
- `BloomEffect.encodedPassCount`: compute dispatches + render passes encoded so far (3 + 1 per glow frame).

## C3 Governor

`QualityGovernor.settings(thermal:lowPower:adaptiveEffects:)`: `adaptiveEffects == false` equals the
two-argument call; `true` caps to 30 fps only under Low Power or at critical.

## C4 App

- `NativeSpectrumHost.effectBudget: EffectBudgetSignal` (set by the coordinator once a second while the overlay runs; `.unavailable` otherwise).
- `NativeSpectrumHost.effectQualityLine: String`, `effectQualityLevel`, `effectQualityReason`.
- DEBUG `-uitestThermalState <nominal|fair|serious|critical>` overrides the thermal input of the ladder and the governor.
- The overlay's lines (native visual shown) end with `effect quality <level>[ (<reason>)]`.
