// PresetEnergyChips.swift — PRE-005: the browser's motion chips (spec PRE-005-R8, R10; contract C5).
// Shown only when listed presets have a motion class. Each chip: a decorative symbol, the class name and
// its count; VoiceOver says "<Class> motion" and the count, Selected when chosen. "Clear" deselects all.
// A caption says how many presets have a class so far (learned from thumbnails as rows are browsed).
// Nothing animates (motion policy).
import PresetLibrary
import SwiftUI

struct PresetEnergyChipRow: View {
    let presets: PresetCoordinator

    var body: some View {
        let filter: PresetEnergyFilter = presets.energyFilter
        let chips: [(energy: PresetEnergy, count: Int)] = filter.chips
        if !chips.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                chipScroller(chips)
                Text(PresetCoordinator.energyCoverageText(filter.presetCount))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("presetEnergyCoverage")
            }
        }
    }

    private func chipScroller(_ chips: [(energy: PresetEnergy, count: Int)]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(chips, id: \.energy) { (chip: (energy: PresetEnergy, count: Int)) in
                    chipButton(chip.energy, count: chip.count)
                }
                if !presets.selectedEnergies.isEmpty { clearChip }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter by motion")
        .accessibilityIdentifier("presetEnergyChips")
    }

    private func chipButton(_ energy: PresetEnergy, count: Int) -> some View {
        let selected: Bool = presets.isSelected(energy: energy)
        let value: String = count == 1 ? "1 preset" : "\(count) presets"
        let traits: AccessibilityTraits = selected ? .isSelected : []
        let fill: Color = selected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.15)
        return Button { presets.toggleEnergy(energy) } label: {
            HStack(spacing: 4) {
                Image(systemName: selected ? "checkmark" : Self.symbol(energy))
                    .font(.caption2)
                    .accessibilityHidden(true)
                Text(energy.name).font(.footnote).foregroundStyle(Color.primary)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(fill, in: Capsule())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(energy.spokenName)
        .accessibilityValue(value)
        .accessibilityAddTraits(traits)
        .accessibilityIdentifier("presetEnergyChip.\(energy.rawValue)")
    }

    private var clearChip: some View {
        Button { presets.clearEnergies() } label: {
            Label("Clear", systemImage: "xmark.circle").font(.footnote)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Clear motion filter")
        .accessibilityIdentifier("presetEnergyClear")
    }

    static func symbol(_ energy: PresetEnergy) -> String {
        switch energy {
        case .calm: "water.waves"
        case .moderate: "wind"
        case .energetic: "bolt"
        }
    }
}
