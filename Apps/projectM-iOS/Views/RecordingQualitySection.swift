// RecordingQualitySection.swift — REC-005-R1, R5, R9: Settings → Recording quality.
//
// One row per profile (Draft, Standard, High, Max): the title, what it records on this screen (size, codec,
// bit rate, frame rate) or, disabled, why it cannot; a checkmark on the selected one. The footer is the
// documented profile table. Rows are buttons (not a Picker) so an unavailable profile stays visible and
// disabled with its reason. Strings come from `RecordingQualitySetting` and FrameRecording.
import FrameRecording
import SwiftUI

struct RecordingQualitySection: View {
    @Bindable var setting: RecordingQualitySetting

    var body: some View {
        Section {
            ForEach(RecordingQualityProfile.allCases, id: \.self) { (profile: RecordingQualityProfile) in
                RecordingQualityRow(setting: setting, profile: profile)
            }
        } header: {
            Text(RecordingQualitySetting.sectionTitle)
        } footer: {
            footer
        }
    }

    private var footer: some View {
        let table: String = RecordingQualitySetting.tableText
        let note: String = RecordingQualitySetting.footer
        return Text(table + "\n" + note)
    }
}

private struct RecordingQualityRow: View {
    @Bindable var setting: RecordingQualitySetting
    let profile: RecordingQualityProfile

    var body: some View {
        let availability: RecordingProfileAvailability = setting.availability(profile)
        let selected: Bool = setting.profile == profile
        let enabled: Bool = availability.plan != nil
        Button {
            setting.select(profile)
        } label: {
            content(availability: availability, selected: selected)
        }
        .disabled(!enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(setting.rowLabel(profile))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("recordingQuality." + profile.rawValue)
    }

    private func content(availability: RecordingProfileAvailability, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.title)
                    .foregroundStyle(availability.plan != nil ? Color.primary : Color.secondary)
                Text(detail(availability))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

    private func detail(_ availability: RecordingProfileAvailability) -> String {
        switch availability {
        case .available(let plan): plan.summary
        case .unavailable(let reason): reason.text
        }
    }
}
