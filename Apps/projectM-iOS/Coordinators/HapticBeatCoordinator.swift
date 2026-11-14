// HapticBeatCoordinator.swift — ACC-007: optional, bounded haptic pulses on selected beat events
// (specs/238-acc-007-haptic-beat-feedback; R1-R9; contract C3, C5; research ACC-007-D2, D5, D6).
//
// * Three local preferences (FILE-005 backed up, erased with Settings, `ALLOWED_KEYS`, removed by
//   `-uitestResetNotice`; never in scenes, cues, MIDI, OSC or modulation):
//   `settings.haptics.beatPulses` (Bool, absent → off), `settings.haptics.beatEvent` (beats/downbeats/kicks,
//   absent → beats), `settings.haptics.strength` (light/medium/strong, absent → medium). Written on change only.
// * Off (R2): no observer on SHOW-011's tempo poll (which keeps its 250 ms) and no call on the player, so no
//   haptic generator is ever created. On (on hardware with haptics): the observer hands every drained event to
//   `handle` on the main actor (40 ms poll, R7); without haptic hardware nothing is installed.
// * `handle` maps the event (C2), decides through `HapticPulseGate` (C1) with `playable` = app active, Low Power
//   Mode off, hardware haptics and an intensity limit above Strict's (R5, R6), and plays at the clamp's
//   intensity limit. All conditions and the clock are injected, so tests are deterministic.
import AnalysisFeatures
import AudioCore
import FlashSafety
import Foundation
import Observation
import PerformanceControl
import PerformanceControlAnalysis
import UIKit

/// What decides whether a pulse may play now (research ACC-007-D6).
struct HapticConditions {
    /// The hardware has haptics. Without them nothing is installed or played (R2, R6).
    var supportsHaptics: Bool
    var isAppActive: @MainActor () -> Bool
    var isLowPowerMode: () -> Bool
    /// Settings enables the switch (the hardware, or the DEBUG UI-test override, research D7).
    var settingsAvailable: Bool

    init(supportsHaptics: Bool, isAppActive: @escaping @MainActor () -> Bool, isLowPowerMode: @escaping () -> Bool,
         settingsAvailable: Bool? = nil) {
        self.supportsHaptics = supportsHaptics
        self.isAppActive = isAppActive
        self.isLowPowerMode = isLowPowerMode
        self.settingsAvailable = settingsAvailable ?? supportsHaptics
    }

    @MainActor static var system: HapticConditions {
        HapticConditions(supportsHaptics: HapticHardware.supportsHaptics,
                         isAppActive: { () -> Bool in UIApplication.shared.applicationState == .active },
                         isLowPowerMode: { () -> Bool in ProcessInfo.processInfo.isLowPowerModeEnabled },
                         settingsAvailable: HapticHardware.settingsAvailable)
    }
}

@MainActor
@Observable
final class HapticBeatCoordinator {
    static let enabledKey = "settings.haptics.beatPulses"
    static let choiceKey = "settings.haptics.beatEvent"
    static let strengthKey = "settings.haptics.strength"
    static let allKeys: [String] = [enabledKey, choiceKey, strengthKey]
    /// R5: at or below Strict's intensity limit no pulse plays.
    static let suppressingIntensityLimit: Double = SensorySafetyLimits.strict.intensityLimit

    static let sectionTitle = "Haptics"
    static let footer = "Short taps on the beat while a visual runs, at most 4 per second. They pause in Low Power Mode and in the background, follow the sensory safety profile and stop under Strict."
    static let noHardwareNote = "This device has no haptics."

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let player: () -> any HapticPlaying
    @ObservationIgnored private var madePlayer: (any HapticPlaying)?
    @ObservationIgnored private let conditions: HapticConditions
    @ObservationIgnored private let clamp: @MainActor () -> SafetyClamp
    @ObservationIgnored private let clock: () -> UInt64
    @ObservationIgnored private weak var tempo: TempoCoordinator?
    @ObservationIgnored private(set) var gate: HapticPulseGate

    var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            defaults.set(enabled, forKey: Self.enabledKey)
            gate.reset()
            updateObserver()
        }
    }

    var choice: HapticBeatChoice {
        didSet {
            guard choice != oldValue else { return }
            defaults.set(choice.rawValue, forKey: Self.choiceKey)
            gate.choice = choice   // the beat count is kept (contract C1)
        }
    }

    var strength: HapticPulseStrength {
        didSet {
            guard strength != oldValue else { return }
            defaults.set(strength.rawValue, forKey: Self.strengthKey)
        }
    }

    /// The Settings switch is enabled (the hardware has haptics).
    var isAvailable: Bool { conditions.settingsAvailable }

    /// The tempo poll's observer is installed: on, on hardware with haptics (R2, R6, R7).
    var observesAnalysis: Bool { enabled && conditions.supportsHaptics }

    /// `player` is called on the first pulse only (R2: nothing is created while off).
    init(defaults: UserDefaults, tempo: TempoCoordinator?, clamp: @escaping @MainActor () -> SafetyClamp,
         conditions: HapticConditions = .system, clock: @escaping () -> UInt64 = { MonotonicClock.nowNanoseconds() },
         player: @escaping () -> any HapticPlaying = { () -> any HapticPlaying in ImpactHapticPlayer() }) {
        if ProcessInfo.processInfo.arguments.contains("-uitestResetNotice") {
            for key in Self.allKeys { defaults.removeObject(forKey: key) }   // the UI-test reset: off, Beats, Medium
        }
        self.defaults = defaults
        self.player = player
        self.conditions = conditions
        self.clamp = clamp
        self.clock = clock
        self.tempo = tempo
        enabled = defaults.bool(forKey: Self.enabledKey)
        let storedChoice: HapticBeatChoice = defaults.string(forKey: Self.choiceKey).flatMap(HapticBeatChoice.init(rawValue:)) ?? .beats
        choice = storedChoice
        strength = defaults.string(forKey: Self.strengthKey).flatMap(HapticPulseStrength.init(rawValue:)) ?? .medium
        gate = HapticPulseGate(choice: storedChoice)
        updateObserver()
    }

    /// Installs the tempo poll's observer while on (with haptic hardware), removes it otherwise (R2, R7).
    private func updateObserver() {
        guard let tempo else { return }
        if observesAnalysis {
            tempo.analysisEventObserver = { [weak self] (event: AnalysisEvent) -> Void in self?.handle(event) }
        } else {
            tempo.analysisEventObserver = nil
        }
    }

    /// Whether a pulse may play now (R5, R6).
    var canPlayNow: Bool {
        guard conditions.supportsHaptics, conditions.isAppActive(), !conditions.isLowPowerMode() else { return false }
        return clamp().limits.intensityLimit > Self.suppressingIntensityLimit
    }

    /// One drained analysis event (contract C3).
    func handle(_ event: AnalysisEvent) {
        guard enabled, let cue = HapticCue(event) else { return }
        let playable: Bool = canPlayNow
        let decision: HapticPulseDecision = gate.consider(cue, eventNanoseconds: event.time.hostNanoseconds, now: clock(),
                                                          playable: playable)
        guard decision == .pulse else { return }
        let intensity: Double = clamp().limits.intensityLimit
        resolvedPlayer().play(strength: strength, intensity: intensity)
    }

    private func resolvedPlayer() -> any HapticPlaying {
        if let madePlayer { return madePlayer }
        let made: any HapticPlaying = player()
        madePlayer = made
        return made
    }
}
