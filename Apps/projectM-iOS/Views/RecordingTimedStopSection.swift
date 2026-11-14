// RecordingTimedStopSection.swift — REC-008-R9 (specs/180-rec-008-timed-stop, contract C3): Settings → Stop recording after.
//
// Five rows (Off, 10 seconds, 30 seconds, 1 minute, 5 minutes) built like the frame-rate rows: buttons with a checkmark on the selected
// one, identifiers `recordingTimedStop.<raw>`. Strings come from `RecordingTimedStopSetting`.
import SwiftUI

struct RecordingTimedStopSection: View {
    @Bindable var setting: RecordingTimedStopSetting

    var body: some View {
        Section {
            ForEach(RecordingTimedStopLength.allCases, id: \.self) { (length: RecordingTimedStopLength) in
                RecordingTimedStopRow(setting: setting, length: length)
            }
        } header: {
            Text(RecordingTimedStopSetting.sectionTitle)
        } footer: {
            Text(RecordingTimedStopSetting.footer)
        }
    }
}

private struct RecordingTimedStopRow: View {
    @Bindable var setting: RecordingTimedStopSetting
    let length: RecordingTimedStopLength

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
        .accessibilityIdentifier("recordingTimedStop." + length.rawValue)
    }
}
