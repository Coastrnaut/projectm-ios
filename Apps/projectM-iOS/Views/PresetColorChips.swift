// PresetColorChips.swift — PRE-004: the browser's colour chips (spec PRE-004-R7, R9; contract C5).
// Shown only when listed presets have colours. Each chip: a decorative swatch, the family's name and
// its count; Selected for VoiceOver when chosen. "Clear" deselects all colours. A caption says how
// many presets have colours so far (they are learned from thumbnails as rows are browsed).
import PresetLibrary
import SwiftUI

struct PresetColorChipRow: View {
    let presets: PresetCoordinator

    var body: some View {
        let filter: PresetColorFilter = presets.colorFilter
        let chips: [(family: PresetColorFamily, count: Int)] = filter.chips
        if !chips.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                chipScroller(chips)
                Text(PresetCoordinator.colorCoverageText(filter.presetCount))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("presetColorCoverage")
            }
        }
    }

    private func chipScroller(_ chips: [(family: PresetColorFamily, count: Int)]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(chips, id: \.family) { (chip: (family: PresetColorFamily, count: Int)) in
                    chipButton(chip.family, count: chip.count)
                }
                if !presets.activeColors.isEmpty { clearChip }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter by colour")
        .accessibilityIdentifier("presetColorChips")
    }

    private func chipButton(_ family: PresetColorFamily, count: Int) -> some View {
        let selected: Bool = presets.isSelected(color: family)
        let value: String = count == 1 ? "1 preset" : "\(count) presets"
        let traits: AccessibilityTraits = selected ? .isSelected : []
        let fill: Color = selected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.15)
        return Button { presets.toggleColor(family) } label: {
            HStack(spacing: 4) {
                swatch(family, selected: selected)
                Text(family.name).font(.footnote).foregroundStyle(Color.primary)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(fill, in: Capsule())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(family.name)
        .accessibilityValue(value)
        .accessibilityAddTraits(traits)
        .accessibilityIdentifier("presetColorChip.\(family.rawValue)")
    }

    private func swatch(_ family: PresetColorFamily, selected: Bool) -> some View {
        ZStack {
            Circle().fill(Self.swatchColor(family))
            Circle().strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
            if selected {
                Image(systemName: "checkmark").font(.system(size: 7, weight: .bold)).foregroundStyle(Self.checkColor(family))
            }
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }

    private var clearChip: some View {
        Button { presets.clearColors() } label: {
            Label("Clear", systemImage: "xmark.circle").font(.footnote)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Clear colour filter")
        .accessibilityIdentifier("presetColorClear")
    }

    static func swatchColor(_ family: PresetColorFamily) -> Color {
        switch family {
        case .red: Color(red: 0.86, green: 0.12, blue: 0.12)
        case .orange: Color(red: 1.0, green: 0.55, blue: 0.0)
        case .yellow: Color(red: 0.95, green: 0.85, blue: 0.1)
        case .green: Color(red: 0.15, green: 0.7, blue: 0.25)
        case .cyan: Color(red: 0.0, green: 0.78, blue: 0.82)
        case .blue: Color(red: 0.12, green: 0.3, blue: 0.9)
        case .purple: Color(red: 0.55, green: 0.2, blue: 0.85)
        case .pink: Color(red: 0.92, green: 0.3, blue: 0.65)
        case .white: Color(white: 0.97)
        case .grey: Color(white: 0.55)
        case .black: Color(white: 0.05)
        }
    }

    private static func checkColor(_ family: PresetColorFamily) -> Color {
        switch family {
        case .white, .yellow, .cyan: .black
        default: .white
        }
    }
}
