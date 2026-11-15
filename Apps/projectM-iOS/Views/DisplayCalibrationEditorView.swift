// DisplayCalibrationEditorView.swift — OUT-009-T11 (spec specs/268-out-009-output-color-calibration, contract C5): the
// full-screen colour calibration editor opened from Settings › External Display › Color calibration… (OUT-007's
// editor pattern). Four sliders (Gamma, Red, Green, Blue) with ACC-005's `.accessibleParameter` (one step per
// VoiceOver swipe, spoken value), readouts, Reset (disabled at the identity) and a footer naming what is not
// calibrated. Every change applies live to a connected display (`ExternalOutputSetting.calibration`); nothing here
// touches scenes. Each row is a small typed property (Xcode 26 type-check budget).
import Compositor
import SwiftUI

/// ACC-005 specs of the four sliders (ranges and step from `DisplayCalibration`).
@MainActor
enum DisplayCalibrationParameterSpecs {
    static let gamma = AccessibleParameterSpec(id: "calibrationGamma", label: "Gamma", range: DisplayCalibration.gammaRange,
                                               step: DisplayCalibration.step * 5, unit: .number(decimals: 2))
    static let red = AccessibleParameterSpec(id: "calibrationRed", label: "Red", range: DisplayCalibration.trimRange,
                                             step: DisplayCalibration.step * 5, unit: .multiplier)
    static let green = AccessibleParameterSpec(id: "calibrationGreen", label: "Green", range: DisplayCalibration.trimRange,
                                               step: DisplayCalibration.step * 5, unit: .multiplier)
    static let blue = AccessibleParameterSpec(id: "calibrationBlue", label: "Blue", range: DisplayCalibration.trimRange,
                                              step: DisplayCalibration.step * 5, unit: .multiplier)

    enum Channel: CaseIterable { case gamma, red, green, blue }

    static func spec(_ channel: Channel) -> AccessibleParameterSpec {
        switch channel {
        case .gamma: gamma
        case .red: red
        case .green: green
        case .blue: blue
        }
    }

    static func value(_ channel: Channel, _ c: DisplayCalibration) -> Double {
        switch channel {
        case .gamma: c.gamma
        case .red: c.red
        case .green: c.green
        case .blue: c.blue
        }
    }

    /// Rounded to the 0.01 grid so slider positions store short values.
    static func setting(_ channel: Channel, _ value: Double, in c: DisplayCalibration) -> DisplayCalibration {
        let v: Double = (value / DisplayCalibration.step).rounded() * DisplayCalibration.step
        switch channel {
        case .gamma: return c.with(gamma: v)
        case .red: return c.with(red: v)
        case .green: return c.with(green: v)
        case .blue: return c.with(blue: v)
        }
    }

    static func target(_ channel: Channel, _ setting: ExternalOutputSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in value(channel, setting.calibration) },
                        set: { (v: Double) -> Void in setting.calibration = Self.setting(channel, v, in: setting.calibration) })
    }
}

struct DisplayCalibrationEditorView: View {
    @Bindable var setting: ExternalOutputSetting
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                slidersSection
                probe
            }
            .navigationTitle(ExternalOutputSetting.calibrationEditorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { doneItem }
        }
    }

    private var doneItem: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done", action: onDone)
                .accessibilityIdentifier("calibrationDone")
        }
    }

    private var slidersSection: some View {
        Section {
            ForEach(DisplayCalibrationParameterSpecs.Channel.allCases, id: \.self) { (channel: DisplayCalibrationParameterSpecs.Channel) in
                row(channel)
            }
            Button("Reset", role: .destructive) { setting.calibration = .identity }
                .disabled(setting.calibration.isIdentity)
                .accessibilityIdentifier("calibrationReset")
        } footer: {
            Text(ExternalOutputSetting.calibrationFooter)
        }
    }

    private func binding(_ channel: DisplayCalibrationParameterSpecs.Channel) -> Binding<Double> {
        let target: ParameterTarget = DisplayCalibrationParameterSpecs.target(channel, setting)
        return Binding<Double>(get: { () -> Double in target.get() }, set: { (v: Double) -> Void in target.set(v) })
    }

    private func row(_ channel: DisplayCalibrationParameterSpecs.Channel) -> some View {
        let spec: AccessibleParameterSpec = DisplayCalibrationParameterSpecs.spec(channel)
        let value: Double = DisplayCalibrationParameterSpecs.value(channel, setting.calibration)
        let text: String = value.formatted(.number.precision(.fractionLength(2)))
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(spec.label)
                Spacer()
                Text(text)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(spec.id + "Value")
            }
            .accessibilityElement(children: .contain)
            Slider(value: binding(channel), in: spec.range, step: DisplayCalibration.step)
                .accessibleParameter(spec, target: DisplayCalibrationParameterSpecs.target(channel, setting))
        }
    }

    /// DEBUG (UI tests): the coordinator's `calibrationSummary` while the editor covers the visualizer's probe.
    @ViewBuilder private var probe: some View {
        #if DEBUG
        let stored: String = setting.calibration.stored   // observed: re-renders on every change
        let summary: String = setting.external?.calibrationSummary ?? "none"
        let text: String = stored + "|" + summary
        Text(text)
            .font(.caption2)
            .frame(height: 1)
            .opacity(0.01)
            .accessibilityIdentifier("calibrationProbe")
            .accessibilityValue(text)
        #endif
    }
}
