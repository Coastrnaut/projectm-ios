// PowerProfileSection.swift — PERF-008-R1: Settings → Power (after the performance overlay toggle).
//
// Three rows (Standard, Follow Low Power Mode, Battery saver) built like the recording countdown rows: buttons with a
// checkmark on the selected one, identifiers `powerProfile.<raw>`. Strings come from `PowerProfileSetting`.
import Rendering
import SwiftUI

struct PowerProfileSection: View {
    @Bindable var setting: PowerProfileSetting

    var body: some View {
        Section {
            ForEach(PowerProfile.allCases, id: \.self) { (profile: PowerProfile) in
                PowerProfileRow(setting: setting, profile: profile)
            }
        } header: {
            Text(PowerProfileSetting.sectionTitle)
        } footer: {
            Text(PowerProfileSetting.footer)
        }
    }
}

private struct PowerProfileRow: View {
    @Bindable var setting: PowerProfileSetting
    let profile: PowerProfile

    var body: some View {
        let selected: Bool = setting.profile == profile
        Button {
            setting.profile = profile
        } label: {
            HStack {
                Text(profile.title)
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
        .accessibilityLabel(profile.title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("powerProfile." + profile.rawValue)
    }
}
