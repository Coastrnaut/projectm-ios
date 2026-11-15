// ReactionDiffusionOptions.swift — VIS-012-R13: reaction diffusion's Settings rows (Preset, Pattern, Seed 0…9999,
// Speed 1…16 iterations per step), shown under the Visual list when Reaction Diffusion is chosen. Its own view so
// SettingsView's body stays small. A preset, pattern or seed change re-seeds the grid; Speed does not.
import SwiftUI
import VisualGenerators

struct ReactionDiffusionOptions: View {
    @Bindable var settings: AppSettings

    private var presetPicker: some View {
        Picker("Preset", selection: $settings.reactionPreset) {
            ForEach(ReactionDiffusionPreset.allCases, id: \.self) { (preset: ReactionDiffusionPreset) in
                Text(preset.title).tag(preset)
            }
        }
        .accessibilityIdentifier("reactionPresetPicker")
    }

    private var patternPicker: some View {
        Picker("Seed pattern", selection: $settings.reactionPattern) {
            ForEach(ReactionDiffusionPattern.allCases, id: \.self) { (pattern: ReactionDiffusionPattern) in
                Text(pattern.title).tag(pattern)
            }
        }
        .accessibilityIdentifier("reactionPatternPicker")
    }

    private var seedStepper: some View {
        Stepper(value: $settings.reactionSeed, in: ReactionDiffusion.seedRange) {
            Text("Seed: \(settings.reactionSeed)")
        }
        .accessibilityLabel("Seed")
        .accessibilityValue("\(settings.reactionSeed)")
        .accessibilityIdentifier("reactionSeedStepper")
    }

    private var speedStepper: some View {
        Stepper(value: $settings.reactionSpeed, in: ReactionDiffusion.speedRange) {
            Text("Speed: \(settings.reactionSpeed)")
        }
        .accessibilityLabel("Speed")
        .accessibilityValue("\(settings.reactionSpeed) steps per frame")
        .accessibilityIdentifier("reactionSpeedStepper")
    }

    var body: some View {
        presetPicker
        patternPicker
        seedStepper
        speedStepper
    }
}
