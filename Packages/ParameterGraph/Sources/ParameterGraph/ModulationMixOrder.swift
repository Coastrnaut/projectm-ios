// ModulationMixOrder.swift — the order and clamping of the mix modes when several sources act on one
// parameter (MOD-011-R2 to R4; contract specs/178-mod-011-mix-modes/contracts/mix-order.md O1; ADR
// "modulation mix order").
//
// The order, for one parameter each frame:
//   1. Base b: the MIDI-003 live value while one exists, else the manual value (Settings, MOD-010 macro,
//      snapshot recall, undo). Modulation never writes it.
//   2. Layers in binding list order (the order added; the scene's `$.bindings` order), running value r₀ = b.
//      Layer i maps its source: mᵢ = range(curve(envelope(source))) (MOD-002 to MOD-005; LFOs are
//      `audio.lfo.<n>` sources, MOD-007), then combines:
//        replace   rᵢ = mᵢ
//        add       rᵢ = rᵢ₋₁ + mᵢ       (mᵢ is an offset within ± the parameter's span)
//        multiply  rᵢ = rᵢ₋₁ × mᵢ       (mᵢ is a factor within 0…1)
//      A non-finite result keeps rᵢ₋₁. Then rᵢ is clamped to the registry range — after every layer.
//   3. Integer parameters: rounded half away from zero and snapped to the step, once, at the end.
//   4. ACC-012's sensory safety clamp, last (applied by the caller: `GlowModulationOrder` for the glow).
// With one layer this is exactly MOD-002's formula, bit for bit.
//
// Pure, allocation-free, Foundation-free arithmetic.

public enum ModulationMixOrder {
    /// One layer: combines `running` with the layer's `mapped` value by `mode`, keeps `running` when the
    /// result is not finite, and clamps to `minimum…maximum` (contract O1 step 2).
    @inlinable
    public static func step(_ running: Double, mapped: Double, mode: ModulationMixMode,
                            minimum: Double, maximum: Double) -> Double {
        let combined: Double
        switch mode {
        case .replace: combined = mapped
        case .add: combined = running + mapped
        case .multiply: combined = running * mapped
        }
        let safe: Double = combined.isFinite ? combined : running
        return min(max(safe, minimum), maximum)
    }

    /// Folds `layers` (mapped value and mix mode, in list order) over `base` with a clamp after each
    /// layer (contract O1 step 2). No layers: `base` unchanged (not clamped).
    public static func fold(base: Double, layers: [(mapped: Double, mode: ModulationMixMode)],
                            minimum: Double, maximum: Double) -> Double {
        var running: Double = base
        for layer in layers {
            running = step(running, mapped: layer.mapped, mode: layer.mode, minimum: minimum, maximum: maximum)
        }
        return running
    }
}
