// StarfieldOptions.swift — VIS-016-R8, R11: the starfield's Settings rows (Speed: Slow/Medium/Fast; Stars: 100…2000 in
// steps of 100), shown under the Visual list when Starfield is chosen. Its own view so SettingsView's body stays small.
import SwiftUI
import VisualGenerators

struct StarfieldOptions: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Picker("Speed", selection: $settings.starfieldSpeed) {
            ForEach(StarfieldSpeed.allCases, id: \.self) { (speed: StarfieldSpeed) in Text(speed.title).tag(speed) }
        }
        .segmentedUnlessAccessibilitySize()   // ACC-006-R1
        .accessibilityLabel("Speed")
        .accessibilityIdentifier("starfieldSpeedPicker")
        Stepper(value: $settings.starfieldDensity, in: StarfieldConfiguration.settingsDensityRange,
                step: StarfieldConfiguration.settingsDensityStep) {
            Text("Stars: \(settings.starfieldDensity)")
        }
        .accessibilityLabel("Stars")
        .accessibilityValue("\(settings.starfieldDensity)")
        .accessibilityIdentifier("starfieldDensityStepper")
    }
}
