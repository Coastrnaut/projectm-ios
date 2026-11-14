// HapticPlayer.swift — ACC-007-T05: what plays a haptic beat pulse (specs/238-acc-007-haptic-beat-feedback;
// contract C3; research ACC-007-D1).
//
// * `HapticPlaying`: one call per pulse, on the main actor. Tests pass a fake that records the calls.
// * `ImpactHapticPlayer`: the system's `UIImpactFeedbackGenerator` (light, medium, heavy), one generator per
//   strength, created on the first pulse of that strength (so the app never creates one while the setting is
//   off, ACC-007-R2), prepared again after each pulse so the next one starts promptly.
// * `HapticHardware.supportsHaptics`: Core Haptics' capability query only (iPads and the simulator: false).
import CoreHaptics
import PerformanceControl
import UIKit

@MainActor
protocol HapticPlaying: AnyObject {
    /// Plays one pulse; `intensity` 0…1 (the sensory profile's intensity limit).
    func play(strength: HapticPulseStrength, intensity: Double)
}

@MainActor
final class ImpactHapticPlayer: HapticPlaying {
    private var generators: [HapticPulseStrength: UIImpactFeedbackGenerator] = [:]

    func play(strength: HapticPulseStrength, intensity: Double) {
        let generator: UIImpactFeedbackGenerator = generator(for: strength)
        generator.impactOccurred(intensity: CGFloat(min(max(intensity, 0), 1)))
        generator.prepare()
    }

    private func generator(for strength: HapticPulseStrength) -> UIImpactFeedbackGenerator {
        if let existing = generators[strength] { return existing }
        let style: UIImpactFeedbackGenerator.FeedbackStyle
        switch strength {
        case .light: style = .light
        case .medium: style = .medium
        case .strong: style = .heavy
        }
        let generator = UIImpactFeedbackGenerator(style: style)
        generators[strength] = generator
        return generator
    }
}

enum HapticHardware {
    /// Whether this hardware has a Taptic Engine (Core Haptics' capability query).
    static var supportsHaptics: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }

    /// Whether Settings enables the switch: the hardware, or DEBUG `-uitestHapticsAvailable` on the simulator
    /// (research D7: the switch can be tested; nothing is installed or played without real hardware).
    static var settingsAvailable: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitestHapticsAvailable") { return true }
        #endif
        return supportsHaptics
    }
}
