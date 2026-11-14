// SensorySafetySection.swift — ACC-012-R10, R12 (specs/121-acc-012-sensory-safety-profile, contract C3):
// Settings → Sensory safety.
//
// * A segmented picker: Standard, Reduced, Strict, Custom. Custom's controls appear only while Custom is
//   chosen (clarify Q3): flashes per second (stepper 1…3), brightness rise limit (slider, 0 = none) and
//   intensity limit (slider), both sliders VoiceOver-adjustable through ACC-005's `.accessibleParameter`.
// * A profile change is announced through the shared announcer (`safety` lane, ACC-004); nothing is
//   animated (the Custom rows appear instantly, so no MotionPolicy path is needed, ACC-001).
// * The footer explains the limits, that Reduce flashing still raises the flash limit, and that the app
//   has no haptics (ACC-012-R9).
// * DEBUG: `sensorySafetyProbe` shows what the clamp hands the native visual for the current glow
//   (`BloomParameters.limited(by:)`, the host's own function) and the flash envelope (UI tests).
// A view of its own, built in typed steps, so SettingsView's body stays small (CI's Xcode 26 budget).
import FlashSafety
import SwiftUI
import VisualEffects

struct SensorySafetySection: View {
    @Bindable var settings: AppSettings
    var announcer: AccessibilityAnnouncer?

    private static let footer = "Limits how often the picture may flash, how fast it may brighten, and how strong the glow and anything music drives may get. Reduced and Strict apply to every visual; projectM presets keep their own motion. Reduce flashing still applies its limits whatever you choose. The app uses no haptics."

    static let riseSpec = AccessibleParameterSpec(id: "sensorySafetyRiseSlider", label: "Brightness rise limit",
                                                  range: SensorySafetySetting.riseSliderRange, step: SensorySafetySetting.riseStep,
                                                  unit: .number(decimals: 2))
    static let intensitySpec = AccessibleParameterSpec(id: "sensorySafetyIntensitySlider", label: "Intensity limit",
                                                       range: SensorySafetyLimits.intensityRange, step: SensorySafetySetting.intensityStep,
                                                       unit: .percent(decimals: 0))

    /// ACC-005: the real custom settings.
    static func riseTarget(_ setting: SensorySafetySetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.riseLimitSliderValue },
                        set: { (value: Double) -> Void in setting.riseLimitSliderValue = value })
    }

    static func intensityTarget(_ setting: SensorySafetySetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.intensityLimit },
                        set: { (value: Double) -> Void in setting.intensityLimit = value })
    }

    /// "Sensory safety: Strict".
    static func announcement(for preset: SensorySafetyPreset) -> String {
        let prefix: String = "Sensory safety: "
        return prefix + preset.title
    }

    var body: some View {
        let setting: SensorySafetySetting = settings.sensorySafety
        Section {
            SensorySafetyPresetPicker(setting: setting)
            if setting.preset == .custom {
                SensorySafetyCustomControls(setting: setting)
            }
            #if DEBUG
            SensorySafetyProbe(settings: settings)
            #endif
        } header: {
            Text("Sensory safety")
        } footer: {
            Text(Self.footer)
        }
        .onChange(of: setting.preset) { (_: SensorySafetyPreset, new: SensorySafetyPreset) -> Void in
            announcer?.announce(Self.announcement(for: new), kind: .safety)
        }
    }
}

private struct SensorySafetyPresetPicker: View {
    @Bindable var setting: SensorySafetySetting

    var body: some View {
        Picker("Profile", selection: $setting.preset) {
            ForEach(SensorySafetyPreset.allCases, id: \.self) { (preset: SensorySafetyPreset) in
                Text(preset.title).tag(preset)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Sensory safety profile")
        .accessibilityIdentifier("sensorySafetyProfilePicker")
    }
}

private struct SensorySafetyCustomControls: View {
    @Bindable var setting: SensorySafetySetting

    var body: some View {
        let flashes: String = SensorySafetySetting.flashesText(setting.flashesPerSecond)
        let rise: String = SensorySafetySetting.riseText(setting.custom.riseLimitPerSecond)
        let intensity: String = SensorySafetySetting.intensityText(setting.intensityLimit)
        Stepper(value: $setting.flashesPerSecond, in: SensorySafetyLimits.flashesRange) {
            Text(flashes)
        }
        .accessibilityIdentifier("sensorySafetyFlashesStepper")
        SensorySafetySliderRow(title: "Brightness rise limit", value: rise, readoutID: "sensorySafetyRiseValue") {
            Slider(value: $setting.riseLimitSliderValue, in: SensorySafetySetting.riseSliderRange, step: SensorySafetySetting.riseStep)
                .accessibleParameter(SensorySafetySection.riseSpec, target: SensorySafetySection.riseTarget(setting))
        }
        SensorySafetySliderRow(title: "Intensity limit", value: intensity, readoutID: "sensorySafetyIntensityValue") {
            Slider(value: $setting.intensityLimit, in: SensorySafetyLimits.intensityRange, step: SensorySafetySetting.intensityStep)
                .accessibleParameter(SensorySafetySection.intensitySpec, target: SensorySafetySection.intensityTarget(setting))
        }
    }
}

private struct SensorySafetySliderRow<Control: View>: View {
    let title: String
    let value: String
    let readoutID: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(readoutID)
            }
            .accessibilityElement(children: .contain)
            control()
        }
    }
}

#if DEBUG
/// ACC-012-R12: what the clamp hands the native visual (UI tests).
private struct SensorySafetyProbe: View {
    let settings: AppSettings

    static func text(settings: AppSettings) -> String {
        let clamp: SafetyClamp = settings.safetyClamp
        let glow: Float = settings.glowParameters.limited(by: clamp).intensity
        let glowText: String = Double(glow).formatted(.number.precision(.fractionLength(2)))
        let flashes: String = String(clamp.limits.flashesPerSecond)
        let rise: String = clamp.limits.riseLimitPerSecond.map { (r: Double) -> String in
            r.formatted(.number.precision(.fractionLength(2)))
        } ?? "none"
        let intensity: String = clamp.limits.intensityLimit.formatted(.number.precision(.fractionLength(2)))
        let parts: [String] = ["glow " + glowText, "flashes " + flashes + "/s", "rise " + rise, "intensity " + intensity]
        return parts.joined(separator: " ")
    }

    var body: some View {
        let text: String = Self.text(settings: settings)
        Text(text)
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("sensorySafetyProbe")
            .accessibilityLabel(text)
    }
}
#endif
