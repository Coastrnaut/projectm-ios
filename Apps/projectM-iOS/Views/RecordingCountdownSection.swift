// RecordingCountdownSection.swift — REC-007-R9: Settings → Recording countdown.
//
// Four rows (Off, 3, 5, 10 seconds) built like the frame-rate rows: buttons with a checkmark on the selected
// one, identifiers `recordingCountdown.<raw>`. Strings come from `RecordingCountdownSetting`.
import SwiftUI

struct RecordingCountdownSection: View {
    @Bindable var setting: RecordingCountdownSetting

    var body: some View {
        Section {
            ForEach(RecordingCountdownLength.allCases, id: \.self) { (length: RecordingCountdownLength) in
                RecordingCountdownRow(setting: setting, length: length)
            }
        } header: {
            Text(RecordingCountdownSetting.sectionTitle)
        } footer: {
            Text(RecordingCountdownSetting.footer)
        }
    }
}

private struct RecordingCountdownRow: View {
    @Bindable var setting: RecordingCountdownSetting
    let length: RecordingCountdownLength

    var body: some View {
        let selected: Bool = setting.length == length
        Button {
            setting.length = length
        } label: {
            HStack {
                Text(length.title)
                    .foregroundStyle(Color.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(length.title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("recordingCountdown." + length.rawValue)
    }
}
