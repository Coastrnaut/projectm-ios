// ParameterResetSelectionViews.swift — the parameter list's selection mode (UIX-010-R1, R2, R8, R10;
// contracts/batch-reset.md B2).
//
// * `ParameterResetToggleRow`: a row as a checkbox. One VoiceOver element with the toggle trait, value
//   "Selected"/"Not selected", then group and value. Read-only rows are shown disabled.
// * `ParameterResetSectionHeader`: a group's title with "Select All" / "Deselect All" over its resettable rows.
// * `ParameterResetBar`: the status line and the counted "Reset N to Defaults" button (disabled at 0).
// Bodies stay small (Xcode 26 type-check budget). No animation.
import ParameterGraph
import SwiftUI

struct ParameterResetToggleRow: View {
    let row: ParameterSearchRow
    let resettable: Bool
    let selected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) { label }
            .disabled(!resettable)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.name)
            .accessibilityValue(spokenValue)
            .accessibilityAddTraits(.isToggle)
            .accessibilityHint(resettable ? "" : "Read only, can't be reset here")
            .accessibilityIdentifier("parameterResetToggle." + row.id.rawValue)
    }

    private var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(resettable ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).foregroundStyle(resettable ? Color.primary : Color.secondary)
                Text(row.group).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(row.value).monospacedDigit().foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var spokenValue: String {
        let state: String = selected ? "Selected" : "Not selected"
        return state + ", " + row.group + ", " + row.value
    }
}

struct ParameterResetSectionHeader: View {
    let section: ParameterSearchSection
    /// The section's resettable IDs; empty hides the button.
    let resettable: [ParameterID]
    let allSelected: Bool
    let setAll: (Bool) -> Void

    var body: some View {
        HStack {
            Text(section.title)
            Spacer(minLength: 8)
            if !resettable.isEmpty { selectAllButton }
        }
    }

    private var selectAllButton: some View {
        let title: String = allSelected ? "Deselect All" : "Select All"
        return Button(title) { setAll(!allSelected) }
            .font(.footnote)
            .textCase(nil)
            .accessibilityLabel(title + " " + section.title)
            .accessibilityIdentifier("parameterResetSelectAll." + section.id)
    }
}

struct ParameterResetBar: View {
    let selection: ParameterResetSelection
    let status: String?
    let reset: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if let status { statusText(status) }
            Button(action: reset) { Text(selection.buttonTitle).frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                .disabled(selection.count == 0)
                .accessibilityLabel(selection.buttonAccessibilityLabel)
                .accessibilityIdentifier("parameterReset.reset")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("parameterReset.status")
    }
}
