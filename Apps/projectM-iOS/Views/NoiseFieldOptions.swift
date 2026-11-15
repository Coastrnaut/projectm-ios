// NoiseFieldOptions.swift — VIS-013-R4, R9: the noise field's Settings rows (Frequency, Octaves, Seed with New Seed),
// shown under the Visual list when Noise Field is chosen. Its own view so SettingsView's body stays small.
// New Seed takes the next seed of SHD-006's deterministic `NoiseSeedSequence` (research VIS-013-D6): the same sequence
// on every install, never the system random source; its counter lives for the session only.
import ProceduralMaterials
import VisualGenerators
import SwiftUI

/// The session's New Seed sequence (main actor; not stored).
@MainActor
enum NoiseFieldSeeds {
    static var sequence = NoiseSeedSequence()

    /// The next seed that differs from `current`.
    static func next(after current: Int) -> Int { sequence.next(after: current) }
}

struct NoiseFieldOptions: View {
    @Bindable var settings: AppSettings

    var body: some View {
        frequencyPicker
        octavesStepper
        seedRow
    }

    private var frequencyPicker: some View {
        Picker("Frequency", selection: $settings.noiseFieldFrequency) {
            ForEach(NoiseFieldFrequency.allCases, id: \.self) { (frequency: NoiseFieldFrequency) in Text(frequency.title).tag(frequency) }
        }
        .segmentedUnlessAccessibilitySize()   // ACC-006-R1
        .accessibilityLabel("Frequency")
        .accessibilityIdentifier("noiseFieldFrequencyPicker")
    }

    private var octavesStepper: some View {
        Stepper(value: $settings.noiseFieldOctaves, in: NoiseFieldConfiguration.octaveRange) {
            Text("Octaves: \(settings.noiseFieldOctaves)")
        }
        .accessibilityLabel("Octaves")
        .accessibilityValue("\(settings.noiseFieldOctaves)")
        .accessibilityIdentifier("noiseFieldOctavesStepper")
    }

    private var seedRow: some View {
        HStack {
            Text("Seed \(String(settings.noiseFieldSeed))")
                .accessibilityIdentifier("noiseFieldSeedLabel")
            Spacer()
            Button("New Seed") { settings.noiseFieldSeed = NoiseFieldSeeds.next(after: settings.noiseFieldSeed) }
                .accessibilityIdentifier("noiseFieldNewSeedButton")
        }
    }
}
