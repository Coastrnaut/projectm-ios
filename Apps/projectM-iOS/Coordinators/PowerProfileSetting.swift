// PowerProfileSetting.swift — PERF-008-R1, R6, R7: the power profile preference (Settings → Performance;
// specs/201-perf-008-battery-saver, contract power-profile.md).
//
// One String, key `settings.performance.powerProfile` (`standard`, `followLowPowerMode`, `batterySaver`; absent or
// unknown → Standard; nothing stored until changed). A preference, not a device capability: backed up with the
// library settings (FILE-005 `includedKeys`), erased with the Settings category, removed by `-uitestResetNotice`.
//
// Applying a profile writes the process-wide `PowerProfileState`, which every frame loop re-reads through
// `QualityGovernor.current()`, and emits one "Power profile" signpost. It holds no reference to the capture
// manager, the transport or any source, so a profile change cannot change the audio source state (R5).
import Diagnostics
import Foundation
import Observation
import Rendering

@MainActor
@Observable
final class PowerProfileSetting {
    static let key = "settings.performance.powerProfile"
    static let sectionTitle = "Power"
    static let footer = "Battery saver limits the visualization to 30 fps at a lower resolution and skips background warm-ups. Follow Low Power Mode does this only while Low Power Mode is on. Audio is never affected."

    @ObservationIgnored private let defaults: UserDefaults

    var profile: PowerProfile {
        didSet {
            defaults.set(profile.rawValue, forKey: Self.key)
            apply()
        }
    }

    init(defaults: UserDefaults) {
        if ProcessInfo.processInfo.arguments.contains("-uitestResetNotice") {
            defaults.removeObject(forKey: Self.key)   // the UI-test reset: Standard
        }
        self.defaults = defaults
        profile = Self.stored(in: defaults)
        apply()
    }

    /// The stored profile, Standard when absent or unknown.
    static func stored(in defaults: UserDefaults) -> PowerProfile {
        PowerProfile(stored: defaults.string(forKey: key))
    }

    /// Makes the profile active for every frame loop and warm-up (posts the change notification when it changed).
    private func apply() {
        guard PowerProfileState.current != profile else { return }
        PowerProfileState.current = profile
        DiagnosticsLog.powerProfile(Self.summary(profile))
    }

    /// The signpost summary: the profile and its battery-saver budget (no user content).
    static func summary(_ profile: PowerProfile) -> String {
        let budget: PowerBudget = profile.budget(lowPower: true)
        return profile.rawValue + " cap " + String(budget.maxFramesPerSecond) + " fps scale " + String(budget.renderScaleCap)
    }

    /// PERF-008-R9: the overlay line while the active budget is not Standard's (nil otherwise).
    static func overlayLine(profile: PowerProfile, lowPower: Bool) -> String? {
        let budget: PowerBudget = profile.budget(lowPower: lowPower)
        guard budget != .standard else { return nil }
        let scale: String = String(format: "%.2f", budget.renderScaleCap)
        return "power " + profile.title.lowercased() + " " + String(budget.maxFramesPerSecond) + " fps " + scale + "x"
    }
}
