// QualityGovernor.swift — thermal and low-power adaptation (task T100; FR-049).
//
// Maps the device's thermal state and Low Power Mode to render settings: a lower frame-rate cap
// first, then a lower render scale, never below 30 fps. Its only inputs are those two signals, so the
// audio state, labels and controls cannot change because of it (FR-049).
//
// | Thermal  | Low Power off       | Low Power on        |
// | nominal  | 60 fps, scale 1.0   | 30 fps, scale 1.0   |
// | fair     | 60 fps, scale 1.0   | 30 fps, scale 1.0   |
// | serious  | 30 fps, scale 1.0   | 30 fps, scale 1.0   |
// | critical | 30 fps, scale 0.75  | 30 fps, scale 0.75  |
//
// PERF-003 (specs/173-perf-003-adaptive-quality, research PERF-003-D6): with `adaptiveEffects` (the visual has an
// adaptable effect switched on, which the effect quality ladder lowers first) the serious state keeps 60 fps; the
// critical state and Low Power cap as above. Without it the table is unchanged.
//
// PERF-008 (specs/201-perf-008-battery-saver, R3): the user's power profile adds a `PowerBudget` ceiling. The result
// is the per-value minimum of the table above and the budget (never below 30 fps); the overloads without a budget
// keep Standard, so the table above is unchanged for them. `current()` uses the active profile (`PowerProfileState`).
import Foundation
import QuartzCore

public enum ThermalLevel: CaseIterable, Sendable {
    case nominal, fair, serious, critical

    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .serious
        }
    }
}

public struct QualitySettings: Equatable, Sendable {
    /// Frame-rate cap (30 or 60; the floor is always 30, FR-049).
    public var maxFramesPerSecond: Int
    /// Fraction of the display scale used for the drawable (1.0 = native resolution).
    public var renderScale: Double

    public init(maxFramesPerSecond: Int, renderScale: Double) {
        self.maxFramesPerSecond = maxFramesPerSecond
        self.renderScale = renderScale
    }

    public static let full = QualitySettings(maxFramesPerSecond: 60, renderScale: 1.0)

    /// For CADisplayLink: at least 30 fps, at most the cap.
    public var frameRateRange: CAFrameRateRange {
        let cap = Float(max(30, maxFramesPerSecond))
        return CAFrameRateRange(minimum: 30, maximum: cap, preferred: cap)
    }
}

public enum QualityGovernor {
    public static let minimumFramesPerSecond = 30

    public static func settings(thermal: ThermalLevel, lowPower: Bool) -> QualitySettings {
        settings(thermal: thermal, lowPower: lowPower, adaptiveEffects: false)
    }

    /// PERF-003-R7: effects step down before the frame rate; the serious-state cap is deferred to the effect ladder.
    public static func settings(thermal: ThermalLevel, lowPower: Bool, adaptiveEffects: Bool) -> QualitySettings {
        settings(thermal: thermal, lowPower: lowPower, adaptiveEffects: adaptiveEffects, budget: .standard)
    }

    /// PERF-008-R3: the thermal/Low Power result capped by the power budget, per value; the governor can lower further
    /// but never above the budget, and never below the 30 fps floor. Caps do not compound (0.75 and 0.75 stay 0.75).
    public static func settings(thermal: ThermalLevel, lowPower: Bool, adaptiveEffects: Bool,
                                budget: PowerBudget) -> QualitySettings {
        var settings = systemSettings(thermal: thermal, lowPower: lowPower, adaptiveEffects: adaptiveEffects)
        let fps: Int = min(settings.maxFramesPerSecond, budget.maxFramesPerSecond)
        settings.maxFramesPerSecond = max(minimumFramesPerSecond, fps)
        settings.renderScale = min(settings.renderScale, budget.renderScaleCap)
        return settings
    }

    /// The notifications after which `current()` may change: thermal state, Low Power Mode and the power profile.
    public static let changeNotifications: [Notification.Name] = [
        ProcessInfo.thermalStateDidChangeNotification,
        Notification.Name.NSProcessInfoPowerStateDidChange,
        PowerProfileState.didChangeNotification,
    ]

    private static func systemSettings(thermal: ThermalLevel, lowPower: Bool, adaptiveEffects: Bool) -> QualitySettings {
        var settings = QualitySettings.full
        let thermalCap: Bool = adaptiveEffects ? thermal == .critical : (thermal == .serious || thermal == .critical)
        if lowPower || thermalCap {
            settings.maxFramesPerSecond = minimumFramesPerSecond
        }
        if thermal == .critical {
            settings.renderScale = 0.75
        }
        return settings
    }

    /// The settings for this device right now.
    public static func current() -> QualitySettings {
        let info = ProcessInfo.processInfo
        let lowPower = info.isLowPowerModeEnabled
        return settings(thermal: ThermalLevel(info.thermalState), lowPower: lowPower, adaptiveEffects: false,
                        budget: PowerProfileState.budget(lowPower: lowPower))
    }
}
