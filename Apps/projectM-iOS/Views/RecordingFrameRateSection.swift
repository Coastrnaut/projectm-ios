// RecordingFrameRateSection.swift — REC-006-R6, R9: Settings → Recording frame rate.
//
// Four rows (Profile default, 24, 30, 60 fps) built like REC-005's profile rows: buttons, not a Picker, so an
// unavailable rate stays visible and disabled with its reason; a checkmark on the selected one. Strings come
// from `RecordingQualitySetting` and FrameRecording.
import FrameRecording
import SwiftUI

struct RecordingFrameRateSection: View {
    @Bindable var setting: RecordingQualitySetting

    var body: some View {
        Section {
            ForEach(RecordingFrameRateChoice.allCases, id: \.self) { (choice: RecordingFrameRateChoice) in
                RecordingFrameRateRow(setting: setting, choice: choice)
            }
        } header: {
            Text(RecordingQualitySetting.frameRateSectionTitle)
        } footer: {
            Text(RecordingQualitySetting.frameRateFooter)
        }
    }
}

private struct RecordingFrameRateRow: View {
    @Bindable var setting: RecordingQualitySetting
    let choice: RecordingFrameRateChoice

    var body: some View {
        let availability: RecordingFrameRateAvailability = setting.availability(choice)
        let selected: Bool = setting.frameRate == choice
        Button {
            setting.select(choice)
        } label: {
            content(availability: availability, selected: selected)
        }
        .disabled(!availability.isAvailable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(setting.rowLabel(choice))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("recordingFrameRate." + choice.rawValue)
    }

    private func content(availability: RecordingFrameRateAvailability, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(setting.title(choice))
                    .foregroundStyle(availability.isAvailable ? Color.primary : Color.secondary)
                if let reason = availability.reason {
                    Text(reason.text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }
}
