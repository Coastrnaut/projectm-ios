// PowerProfile.swift — PERF-008: the user's power profile and the budgets it gives the governor
// (specs/201-perf-008-battery-saver, R1-R3, contract power-profile.md).
//
// | Profile                | Low Power off      | Low Power on       |
// | standard               | 60 fps, 1.0, warm  | 60 fps, 1.0, warm  |  (the governor's own Low Power rule still caps 30)
// | followLowPowerMode     | 60 fps, 1.0, warm  | 30 fps, 0.75, cold |
// | batterySaver           | 30 fps, 0.75, cold | 30 fps, 0.75, cold |
//
// "warm" = background warm-up allowed (SC-104 preset warm-up, PERF-005 media prewarm beyond the next cue).
// The budget is a ceiling: `QualityGovernor` takes the per-value minimum with its thermal/Low Power result.
// Nothing here knows about audio; a profile change cannot touch the capture state (R5).
import Foundation

public enum PowerProfile: String, CaseIterable, Sendable {
    case standard
    case followLowPowerMode
    case batterySaver

    public static let defaultProfile: PowerProfile = .standard

    /// The stored raw value, Standard when absent or unknown.
    public init(stored raw: String?) {
        self = raw.flatMap(PowerProfile.init(rawValue:)) ?? .defaultProfile
    }

    public var title: String {
        switch self {
        case .standard: "Standard"
        case .followLowPowerMode: "Follow Low Power Mode"
        case .batterySaver: "Battery saver"
        }
    }

    /// The budget for this profile with the system's Low Power Mode state.
    public func budget(lowPower: Bool) -> PowerBudget {
        switch self {
        case .standard: .standard
        case .followLowPowerMode: lowPower ? .batterySaver : .standard
        case .batterySaver: .batterySaver
        }
    }
}

/// Ceilings a profile puts on the render loop and background work.
public struct PowerBudget: Equatable, Sendable {
    public var maxFramesPerSecond: Int
    public var renderScaleCap: Double
    public var allowsBackgroundWarmUp: Bool

    public init(maxFramesPerSecond: Int, renderScaleCap: Double, allowsBackgroundWarmUp: Bool) {
        self.maxFramesPerSecond = maxFramesPerSecond
        self.renderScaleCap = renderScaleCap
        self.allowsBackgroundWarmUp = allowsBackgroundWarmUp
    }

    /// No ceiling beyond today's governor.
    public static let standard = PowerBudget(maxFramesPerSecond: 60, renderScaleCap: 1.0, allowsBackgroundWarmUp: true)
    /// PERF-008-D3: the FR-049 floor and the critical-state scale, no background warm-up.
    public static let batterySaver = PowerBudget(maxFramesPerSecond: 30, renderScaleCap: 0.75, allowsBackgroundWarmUp: false)
}

/// The process-wide active profile, read by `QualityGovernor.current()` (every frame loop) and the app's warm-ups.
/// The app's `PowerProfileSetting` writes it; a change posts `didChangeNotification` on the main thread.
public enum PowerProfileState {
    public static let didChangeNotification = Notification.Name("org.projectmios.PowerProfileDidChange")

    private static let lock = NSLock()
    nonisolated(unsafe) private static var value: PowerProfile = .defaultProfile

    public static var current: PowerProfile {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            let changed = value != newValue
            value = newValue
            lock.unlock()
            guard changed else { return }
            let post: @Sendable () -> Void = {
                NotificationCenter.default.post(name: didChangeNotification, object: nil)
            }
            if Thread.isMainThread { post() } else { DispatchQueue.main.async(execute: post) }
        }
    }

    /// The active profile's budget for a Low Power Mode state.
    public static func budget(lowPower: Bool) -> PowerBudget {
        current.budget(lowPower: lowPower)
    }
}
