// ChannelSelectionSection.swift — AUD-009-R7, R8: Settings → Analysis Channel, right below AUD-008's
// "Audio Analysis" (input trim) section.
//
// A segmented picker Mix | Left | Right | Mid | Side with a readout of the selected mode's full name.
// VoiceOver reads the label "Analysis channel" and each segment's full name ("Stereo mix", …) (FR-070).
// The footer explains the modes and what they do not change. Strings come from
// `ChannelSelectionSetting.title(for:)`/`spokenName(for:)` and plain constants (no inline string
// arithmetic in modifiers).
import AudioCore
import SwiftUI

struct ChannelSelectionSection: View {
    @Bindable var selection: ChannelSelectionSetting

    private static let title = "Analysis channel"
    private static let header = "Analysis Channel"
    private static let footer = "Which part of the stereo signal the native visuals and tempo detection follow. Mix is both channels together (the default); Mid is what both channels share, Side is their difference. Mix, Left and Right look the same for a mono source. It doesn't change what you hear, what projectM receives or recordings."

    var body: some View {
        let valueText: String = ChannelSelectionSetting.spokenName(for: selection.mode)
        Section {
            HStack {
                Text(Self.title)
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("analysisChannelValue")
            }
            .accessibilityElement(children: .contain)
            Picker(Self.title, selection: $selection.mode) {
                ForEach(AnalysisChannelMode.allCases, id: \.self) { (mode: AnalysisChannelMode) in
                    let segmentTitle: String = ChannelSelectionSetting.title(for: mode)
                    let spoken: String = ChannelSelectionSetting.spokenName(for: mode)
                    Text(segmentTitle)
                        .accessibilityLabel(spoken)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(Self.title)
            .accessibilityIdentifier("analysisChannelPicker")
        } header: {
            Text(Self.header)
        } footer: {
            Text(Self.footer)
        }
    }
}
