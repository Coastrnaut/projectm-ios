// TrailsSection.swift — FX-009-R9: Settings → Trails (specs/130-fx-009-motion-feedback, contracts/motion-feedback.md).
//
// A toggle and, while on, a "Length" slider (the half-life) with its readout and ACC-005's `.accessibleParameter`
// (VoiceOver label, spoken "0.2 seconds", 0.05 s per swipe), plus a line when the safety settings shorten or stop the
// trails. The footer names the visuals that show trails and the safety caps. Each row is its own small view.
import Compositor
import FlashSafety
import SwiftUI

/// ACC-005 spec of the Length slider (range from `MotionFeedback`, the MOD-001 single source; 9 swipes end to end).
@MainActor
enum TrailsParameterSpecs {
    static let length = AccessibleParameterSpec(id: "trailsLengthSlider", label: "Length", range: MotionFeedback.halfLifeRange,
                                                step: 0.05, unit: .seconds)
}

struct TrailsSection: View {
    @Bindable var setting: MotionFeedbackSetting
    let clamp: SafetyClamp

    static let header = "Trails"
    static let toggleTitle = "Trails"
    static let footer = "Moving things leave trails that fade by half every Length. Shown on the Camera, Photo, Video and Text visuals, on an external display, in recordings and in still captures. Each new scene starts without trails. The sensory safety profile and Reduce flashing shorten them, and the flash limiter judges the picture with trails."

    /// ACC-005: the real setting's write path (the view and tests use the same function).
    static func target(_ setting: MotionFeedbackSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.halfLifeSeconds },
                        set: { (value: Double) -> Void in setting.halfLifeSeconds = value })
    }

    var body: some View {
        Section {
            Toggle(Self.toggleTitle, isOn: $setting.isEnabled)
                .accessibilityIdentifier("trailsToggle")
            if setting.isEnabled {
                TrailsLengthRow(value: $setting.halfLifeSeconds, target: Self.target(setting))
                TrailsCapNote(text: MotionFeedbackSetting.capText(user: setting.feedback, effective: setting.effective(clamp: clamp)))
            }
        } header: {
            Text(Self.header)
        } footer: {
            Text(Self.footer)
        }
    }
}

/// The Length slider with its title and readout.
private struct TrailsLengthRow: View {
    @Binding var value: Double
    let target: ParameterTarget

    var body: some View {
        let spec: AccessibleParameterSpec = TrailsParameterSpecs.length
        let valueID: String = spec.id + "Value"
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(spec.label)
                Spacer()
                Text(MotionFeedbackSetting.halfLifeText(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(valueID)
            }
            .accessibilityElement(children: .contain)
            Slider(value: $value, in: spec.range)
                .accessibleParameter(spec, target: target)
        }
    }
}

/// "Your safety settings shorten Trails to 0.13 s." (nothing when they do not).
private struct TrailsCapNote: View {
    let text: String

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("trailsCapNote")
        }
    }
}
