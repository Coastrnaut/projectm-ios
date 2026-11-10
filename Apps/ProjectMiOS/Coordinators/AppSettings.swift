// AppSettings.swift — the user settings (task T103; FR-048, FR-072, FR-065).
//
// * Performance overlay: off by default (FR-048). Key `settings.performanceOverlay`.
// * Reduce flashing: until the user sets it, it follows the system Reduce Motion setting (FR-072:
//   on by default when Reduce Motion is on). Key `settings.reduceFlashing`; absent = follow.
// Both keys are "user settings" in the FR-065 list of what may be stored.
import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    static let performanceOverlayKey = "settings.performanceOverlay"
    static let reduceFlashingKey = "settings.reduceFlashing"
    static let allKeys = [performanceOverlayKey, reduceFlashingKey]

    @ObservationIgnored private let defaults: UserDefaults

    var showsPerformanceOverlay: Bool {
        didSet { defaults.set(showsPerformanceOverlay, forKey: Self.performanceOverlayKey) }
    }

    /// The user's choice; nil follows Reduce Motion.
    private(set) var reduceFlashingChoice: Bool?

    /// The system Reduce Motion setting (kept current by the app).
    var systemReduceMotion: Bool

    init(defaults: UserDefaults, systemReduceMotion: Bool) {
        self.defaults = defaults
        self.systemReduceMotion = systemReduceMotion
        showsPerformanceOverlay = defaults.bool(forKey: Self.performanceOverlayKey)
        reduceFlashingChoice = defaults.object(forKey: Self.reduceFlashingKey) as? Bool
    }

    /// What the renderer uses.
    var reduceFlashing: Bool {
        get { reduceFlashingChoice ?? systemReduceMotion }
        set {
            reduceFlashingChoice = newValue
            defaults.set(newValue, forKey: Self.reduceFlashingKey)
        }
    }

    var reduceFlashingFollowsSystem: Bool { reduceFlashingChoice == nil }

    /// Back to following Reduce Motion.
    func followSystemForReduceFlashing() {
        reduceFlashingChoice = nil
        defaults.removeObject(forKey: Self.reduceFlashingKey)
    }
}
