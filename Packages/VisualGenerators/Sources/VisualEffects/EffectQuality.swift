// EffectQuality.swift — the adaptive effect quality ladder (PERF-003-R1 to R5, R9, R12;
// specs/173-perf-003-adaptive-quality, contracts/effect-quality-ladder.md C1; research PERF-003-D4, D5).
//
// Three ordered levels: Full (today's glow), Reduced (fewer blur taps, a coarser glow image where the halo
// allows; `BloomPlan`), Minimal (the glow pass is skipped). The ladder is stepped once per frame with an injected
// monotonic time, the thermal state, Low Power and PERF-002's budget signal:
// * floor: nominal/fair → Full, serious → Reduced, critical → Minimal; Low Power → at least Reduced. A floor
//   above the target applies at once;
// * a budget that stays over for `overBudgetHold` (3 s) lowers one step (never below Minimal);
// * `recoveryHold` (10 s) of good conditions (target above the floor, budget not over) raises one step;
// * the glow never jumps: a change fades the glow weight to 0 over `fadeDuration` (0.4 s), switches the applied
//   level at zero and fades back in; a change mid-fade reverses from the current weight.
// The weight only ever lowers the glow (it multiplies the intensity after the ACC-012 clamp), so the flash safety
// envelope, Reduce flashing and the clamp see the glow actually drawn and are never relaxed (PERF-003-R8).
// Pure Swift arithmetic on stored values: no allocation, lock or clock read; deterministic; runs on Linux.

/// How much effect work a frame may spend; higher raw values are cheaper.
public enum EffectQualityLevel: Int, CaseIterable, Comparable, Sendable {
    case full = 0
    case reduced = 1
    case minimal = 2

    public var label: String {
        switch self {
        case .full: return "full"
        case .reduced: return "reduced"
        case .minimal: return "minimal"
        }
    }

    public static func < (lhs: EffectQualityLevel, rhs: EffectQualityLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    /// One step cheaper (Minimal stays Minimal).
    var cheaper: EffectQualityLevel { EffectQualityLevel(rawValue: min(rawValue + 1, 2)) ?? .minimal }
    /// One step richer (Full stays Full).
    var richer: EffectQualityLevel { EffectQualityLevel(rawValue: max(rawValue - 1, 0)) ?? .full }
}

/// The device's thermal state as the ladder sees it (the app maps `ProcessInfo.ThermalState`).
public enum EffectThermalState: Int, CaseIterable, Sendable {
    case nominal, fair, serious, critical

    public var label: String {
        switch self {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        }
    }

    /// "serious" → .serious; nil for anything else.
    public init?(label: String) {
        guard let match = Self.allCases.first(where: { (state: EffectThermalState) -> Bool in state.label == label }) else { return nil }
        self = match
    }
}

/// PERF-002's verdict as a ladder input: any flagged pass is `over`; no verdict (overlay off) is `unavailable`.
public enum EffectBudgetSignal: Sendable, Equatable {
    case unavailable
    case within
    case over
}

/// Why the level is below Full (the strongest input that explains it).
public enum EffectQualityReason: String, Sendable, Equatable {
    case thermal
    case lowPower = "low power"
    case budget
}

/// Hold and fade times in seconds (data-model.md).
public struct EffectQualityPolicy: Sendable, Equatable {
    public static let defaultOverBudgetHold: Double = 3
    public static let defaultRecoveryHold: Double = 10
    public static let defaultFadeDuration: Double = 0.4

    public let overBudgetHold: Double
    public let recoveryHold: Double
    public let fadeDuration: Double

    /// Non-finite or non-positive values read the defaults.
    public init(overBudgetHold: Double = EffectQualityPolicy.defaultOverBudgetHold,
                recoveryHold: Double = EffectQualityPolicy.defaultRecoveryHold,
                fadeDuration: Double = EffectQualityPolicy.defaultFadeDuration) {
        self.overBudgetHold = Self.valid(overBudgetHold, Self.defaultOverBudgetHold)
        self.recoveryHold = Self.valid(recoveryHold, Self.defaultRecoveryHold)
        self.fadeDuration = Self.valid(fadeDuration, Self.defaultFadeDuration)
    }

    public static let standard = EffectQualityPolicy()

    private static func valid(_ value: Double, _ fallback: Double) -> Double {
        value.isFinite && value > 0 ? value : fallback
    }
}

/// The ladder (contract C1). One per frame loop; not Sendable: one thread steps it.
public final class EffectQualityLadder {
    public let policy: EffectQualityPolicy
    /// The level the inputs ask for.
    public private(set) var target: EffectQualityLevel = .full
    /// The level the glow is drawn at.
    public private(set) var applied: EffectQualityLevel = .full
    /// 0…1; multiplies the clamped glow intensity.
    public private(set) var glowWeight: Float = 1
    /// Why the target is below Full (nil at Full).
    public private(set) var reason: EffectQualityReason?

    private var lastTime: Double?
    private var overBudgetTime: Double = 0
    private var goodTime: Double = 0

    public init(policy: EffectQualityPolicy = .standard) {
        self.policy = policy
    }

    /// The cheapest level the device state alone asks for.
    public static func floor(thermal: EffectThermalState, lowPower: Bool) -> EffectQualityLevel {
        max(thermalFloor(thermal), lowPower ? .reduced : .full)
    }

    static func thermalFloor(_ thermal: EffectThermalState) -> EffectQualityLevel {
        switch thermal {
        case .nominal, .fair: return .full
        case .serious: return .reduced
        case .critical: return .minimal
        }
    }

    /// Multiplier on the glow intensity: 0 at Minimal (the glow pass is skipped), else the fade weight.
    public var intensityFactor: Float { applied == .minimal ? 0 : glowWeight }

    /// A fade is running (the applied level differs from the target, or the weight is below 1).
    public var isTransitioning: Bool { applied != target || glowWeight < 1 }

    /// "effect quality full", "effect quality reduced (thermal)" (PERF-003-R10). Shows the target level, the one
    /// the inputs chose; during a fade the glow is moving toward it.
    public var overlayLine: String {
        guard let reason else { return "effect quality " + target.label }
        return "effect quality " + target.label + " (" + reason.rawValue + ")"
    }

    /// A fresh loop: the floor at once, full weight, no fade, cleared timers.
    public func start(thermal: EffectThermalState, lowPower: Bool) {
        let level: EffectQualityLevel = Self.floor(thermal: thermal, lowPower: lowPower)
        target = level
        applied = level
        glowWeight = 1
        lastTime = nil
        overBudgetTime = 0
        goodTime = 0
        updateReason(thermal: thermal, lowPower: lowPower)
    }

    /// One frame. `time` is monotonic seconds; a non-finite or earlier time changes nothing.
    public func step(time: Double, thermal: EffectThermalState, lowPower: Bool, budget: EffectBudgetSignal) {
        guard time.isFinite else { return }
        let dt: Double
        if let lastTime {
            guard time >= lastTime else { return }
            dt = time - lastTime
        } else {
            dt = 0
        }
        lastTime = time
        let floor: EffectQualityLevel = Self.floor(thermal: thermal, lowPower: lowPower)
        if floor > target {   // thermal and Low Power step-downs are immediate
            target = floor
            goodTime = 0
        }
        if budget == .over {
            overBudgetTime += dt
            if overBudgetTime >= policy.overBudgetHold {
                target = target.cheaper
                overBudgetTime = 0
            }
            goodTime = 0
        } else {
            overBudgetTime = 0
            if target > floor {
                goodTime += dt
                if goodTime >= policy.recoveryHold {
                    target = target.richer
                    goodTime = 0
                }
            } else {
                goodTime = 0
            }
        }
        advanceFade(dt)
        updateReason(thermal: thermal, lowPower: lowPower)
    }

    private func advanceFade(_ dt: Double) {
        let delta = Float(dt / policy.fadeDuration)
        if applied != target {
            glowWeight = max(0, glowWeight - delta)
            if glowWeight <= 0 {
                glowWeight = 0
                applied = target   // switched while the glow is at zero
            }
        } else if glowWeight < 1 {
            glowWeight = min(1, glowWeight + delta)
        }
    }

    private func updateReason(thermal: EffectThermalState, lowPower: Bool) {
        if target == .full {
            reason = nil
        } else if Self.thermalFloor(thermal) >= target {
            reason = .thermal
        } else if lowPower && EffectQualityLevel.reduced >= target {
            reason = .lowPower
        } else {
            reason = .budget
        }
    }
}
