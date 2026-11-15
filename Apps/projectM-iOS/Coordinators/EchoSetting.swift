// EchoSetting.swift — FX-010: Echo as the user sets it in Settings → Echo (FX-010-R12, R13;
// specs/297-fx-010-echo-feedback, contracts/echo-feedback.md C6; ADR-0108).
//
// One global visual setting: `settings.echo.enabled` (Bool, absent → off), `settings.echo.count` (number, absent/NaN
// → 3, rounded, above 4 → 4), `settings.echo.delay` (Double seconds, absent/NaN → 0.1, out of range → the nearest
// bound) and `settings.echo.decay` (Double, absent/NaN → 0.6, clamped). Values are written only when changed. Every
// change calls `onChange`, through which `AppCoordinator` hands the effective value (ACC-012 limited) to the
// compositor-backed visuals (Camera, Photo, Video, Text). Scenes and effect-chain presets with an `fx.echo` entry set
// these values when opened.
import Compositor
import FlashSafety
import Foundation
import Observation

@MainActor
@Observable
final class EchoSetting {
    static let enabledKey = "settings.echo.enabled"
    static let countKey = "settings.echo.count"
    static let delayKey = "settings.echo.delay"
    static let decayKey = "settings.echo.decay"
    static let allKeys: [String] = [enabledKey, countKey, delayKey, decayKey]
    /// The slider's range (a stored 0 reads as off through `EchoFeedback`, the slider starts at 1).
    static let countSliderRange: ClosedRange<Double> = 1...Double(EchoFeedback.cap)

    @ObservationIgnored private let defaults: UserDefaults
    /// Called after every change with the new (valid) value.
    @ObservationIgnored var onChange: ((EchoFeedback) -> Void)?

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            onChange?(feedback)
        }
    }

    /// 0…4 echoes (the cap).
    var count: Int {
        didSet {
            let valid: Int = EchoFeedback.clampCount(count)
            if valid != count {
                count = valid   // re-enters once with the valid value
                return
            }
            guard count != oldValue else { return }
            defaults.set(count, forKey: Self.countKey)
            onChange?(feedback)
        }
    }

    /// Seconds between stored frames, 0.01…0.5.
    var delaySeconds: Double {
        didSet {
            let valid: Double = EchoFeedback.clampDelay(delaySeconds)
            if valid != delaySeconds || delaySeconds.isNaN {
                delaySeconds = valid
                return
            }
            guard delaySeconds != oldValue else { return }
            defaults.set(delaySeconds, forKey: Self.delayKey)
            onChange?(feedback)
        }
    }

    /// Each echo's strength relative to the one before, 0.1…0.9.
    var decay: Double {
        didSet {
            let valid: Double = EchoFeedback.clampDecay(decay)
            if valid != decay || decay.isNaN {
                decay = valid
                return
            }
            guard decay != oldValue else { return }
            defaults.set(decay, forKey: Self.decayKey)
            onChange?(feedback)
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = Self.readBool(defaults, Self.enabledKey)
        count = EchoFeedback.clampCount(Self.readDouble(defaults, Self.countKey, Double(EchoFeedback.defaultCount)))
        delaySeconds = EchoFeedback.clampDelay(Self.readDouble(defaults, Self.delayKey, EchoFeedback.defaultDelay))
        decay = EchoFeedback.clampDecay(Self.readDouble(defaults, Self.decayKey, EchoFeedback.defaultDecay))
    }

    /// The user's value (before ACC-012's cap).
    var feedback: EchoFeedback {
        EchoFeedback(isEnabled: isEnabled, count: count, delaySeconds: delaySeconds, decay: decay)
    }

    /// What the compositors apply under `clamp` (ACC-012; research FX-010-D9).
    func effective(clamp: SafetyClamp) -> EchoFeedback { feedback.limited(by: clamp) }

    /// Sets every value from a scene or preset entry (each setter keeps its range rule).
    func apply(_ value: EchoFeedback) {
        if count != value.count { count = value.count }
        if delaySeconds != value.delaySeconds { delaySeconds = value.delaySeconds }
        if decay != value.decay { decay = value.decay }
        isEnabled = value.isEnabled
    }

    // MARK: - Slider values (Double)

    var countValue: Double {
        get { Double(count) }
        set { count = EchoFeedback.clampCount(newValue) }
    }

    var delayMilliseconds: Double {
        get { delaySeconds * 1000 }
        set { delaySeconds = newValue.rounded() / 1000 }
    }

    /// Only a real Bool counts (a stored number or string reads as off).
    private static func readBool(_ defaults: UserDefaults, _ key: String) -> Bool {
        guard let number = defaults.object(forKey: key) as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return false
        }
        return number.boolValue
    }

    /// Absent, not a number or a Bool → `fallback` (NaN is handled by the clamp).
    private static func readDouble(_ defaults: UserDefaults, _ key: String, _ fallback: Double) -> Double {
        guard let number = defaults.object(forKey: key) as? NSNumber else { return fallback }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return fallback }
        return number.doubleValue
    }

    // MARK: - Readouts (typed steps)

    /// "3".
    static func countText(_ count: Int) -> String { String(count) }

    /// "100 ms" (whole milliseconds).
    static func delayText(_ seconds: Double) -> String {
        let ms: Int = Int((seconds * 1000).rounded())
        return String(ms) + " ms"
    }

    /// "0.60".
    static func decayText(_ decay: Double) -> String {
        decay.formatted(.number.precision(.fractionLength(2)))
    }
}
