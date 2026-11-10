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
        var settings = QualitySettings.full
        if lowPower || thermal == .serious || thermal == .critical {
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
        return settings(thermal: ThermalLevel(info.thermalState), lowPower: info.isLowPowerModeEnabled)
    }
}
