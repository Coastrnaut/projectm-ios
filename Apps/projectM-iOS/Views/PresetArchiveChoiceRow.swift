// PresetArchiveChoiceRow.swift — one conflict row of the preset archive preview with its own choice
// (roadmap FILE-004, specs/111-file-004-import-conflict-resolver; FILE-004-R1, R8; contract C4;
// research FILE-004-D8). The row's text says what clashes and what the install will do; three buttons
// below it ("Skip", "Keep both", "Replace") set this row's choice, the selected one with a checkmark
// and the selected trait. Everything stacks vertically and wraps, so the row works at the largest
// accessibility sizes; nothing animates. Small properties keep each body quick to type-check (CI's
// Xcode 26 limit).
import PresetLibrary
import SwiftUI

struct PresetArchiveChoiceRow: View {
    let entry: PresetArchivePlanEntry
    let disabled: Bool
    let choose: (PresetArchiveConflictPolicy) -> Void

    /// The order the buttons are shown in: the non-destructive choices first.
    static let order: [PresetArchiveConflictPolicy] = [.skip, .keepBoth, .replace]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            summary
            ForEach(Self.order, id: \.self) { (choice: PresetArchiveConflictPolicy) in
                choiceButton(choice)
            }
        }
        .padding(.vertical, 2)
    }

    private var summary: some View {
        let text: String = UserPresetsCoordinator.archiveEntryText(entry)
        let outcome: String = UserPresetsCoordinator.archiveInstallText(entry) ?? "Installed as it is."
        return VStack(alignment: .leading, spacing: 2) {
            Text(text)
            Text(outcome).font(.caption)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text + " " + outcome)
        .accessibilityIdentifier("archiveConflict:\(entry.incomingName)")
    }

    private func choiceButton(_ choice: PresetArchiveConflictPolicy) -> some View {
        let selected: Bool = entry.choice == choice
        let title: String = UserPresetsCoordinator.policyTitle(choice)
        return Button { choose(choice) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").accessibilityHidden(true)
                Text(title)
            }
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("archiveChoice:\(entry.incomingName):\(choice.rawValue)")
    }
}
