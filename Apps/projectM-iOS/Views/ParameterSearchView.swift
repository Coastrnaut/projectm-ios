// ParameterSearchView.swift — Settings › Search Parameters (UIX-009-R5 to R8; contracts/parameter-search.md S4).
//
// * `ParameterSearchLinkSection`: the Settings row (next to Modulation) that pushes the search.
// * `ParameterSearchView`: a searchable list over every MOD-001 parameter, whatever the visual on screen. An empty
//   query lists every parameter under its group; a query lists ranked rows; nothing matching says so. Choosing a
//   row opens the UIX-003 inspector over Settings for that ID (the visual is not changed).
// * UIX-010: Select turns on the selection mode (`ParameterResetSelectionViews`): rows become toggles, group headers
//   offer Select All, and the bottom bar resets the selection to defaults as one undo step; the toolbar carries
//   SCN-010's Undo and Redo. A reset or a refusal ends the mode; "Already at defaults" keeps it.
// Bodies stay small (Xcode 26 type-check budget).
import ParameterGraph
import SwiftUI

struct ParameterSearchLinkSection: View {
    let settings: AppSettings
    let open: (ParameterID) -> Void
    /// UIX-010: the reset's one undo step and its announcement (nil in previews).
    var history: SceneHistoryCoordinator? = nil
    var announcer: AccessibilityAnnouncer? = nil

    var body: some View {
        Section {
            NavigationLink {
                ParameterSearchView(settings: settings, open: open, history: history, announcer: announcer)
            } label: {
                Text("Search Parameters")
            }
            .accessibilityIdentifier("parameterSearchLink")
        } footer: {
            Text("Find any visual setting by its name, its section or its unit, and open it in the inspector.")
        }
    }
}

struct ParameterSearchView: View {
    let settings: AppSettings
    let open: (ParameterID) -> Void
    var history: SceneHistoryCoordinator? = nil
    var announcer: AccessibilityAnnouncer? = nil
    @State private var query = ""
    @State private var selecting = false
    @State private var selection = ParameterResetSelection()
    @State private var status: String?

    private var trimmedQueryIsEmpty: Bool { ParameterSearch.words(query).isEmpty }

    var body: some View {
        List {
            if trimmedQueryIsEmpty { indexSections } else { resultSection }
        }
        .accessibilityIdentifier("parameterSearch")   // on the list only: the reset bar keeps its own identifiers
        .navigationTitle("Search Parameters")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Name, group or unit"))
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .toolbar { toolbarItems }
        .safeAreaInset(edge: .bottom) { resetBar }
    }

    // MARK: UIX-010 selection mode

    @ToolbarContentBuilder private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(selecting ? "Done" : "Select") { setSelecting(!selecting) }
                .accessibilityIdentifier("parameterReset.select")
        }
        if let history {
            ToolbarItem(placement: .topBarTrailing) { SceneUndoRedoButtons(history: history) }   // UIX-010-R10
        }
    }

    @ViewBuilder private var resetBar: some View {
        if selecting {
            ParameterResetBar(selection: selection, status: status, reset: resetSelection)
        }
    }

    private func setSelecting(_ on: Bool) {
        selecting = on
        selection.clear()
        status = nil
    }

    private func resetSelection() {
        let result: ParameterBatchResetResult = ParameterBatchReset.reset(selection.ids, settings: settings, history: history)
        if result.outcome != .refused { announcer?.announce(result.message, kind: .parameter) }   // the lock announces its own refusal
        if result.outcome == .alreadyAtDefaults {
            status = result.message
        } else {
            setSelecting(false)
        }
    }

    private func isResettable(_ id: ParameterID) -> Bool { ParameterBatchReset.isResettable(id, settings: settings) }

    private func resettableIDs(_ section: ParameterSearchSection) -> [ParameterID] {
        section.rows.map(\.id).filter { (id: ParameterID) -> Bool in isResettable(id) }
    }

    private func header(_ section: ParameterSearchSection) -> some View {
        let ids: [ParameterID] = resettableIDs(section)
        return ParameterResetSectionHeader(section: section, resettable: ids, allSelected: selection.allSelected(ids),
                                           setAll: { (on: Bool) -> Void in selection.setAll(ids, selected: on) })
    }

    @ViewBuilder private func row(_ row: ParameterSearchRow) -> some View {
        if selecting {
            ParameterResetToggleRow(row: row, resettable: isResettable(row.id), selected: selection.contains(row.id),
                                    toggle: { () -> Void in selection.toggle(row.id) })
        } else {
            rowButton(row)
        }
    }

    private var indexSections: some View {
        let sections: [ParameterSearchSection] = ParameterSearchRows.sections(settings: settings, visual: settings.visual)
        return ForEach(sections) { (section: ParameterSearchSection) in
            Section {
                ForEach(section.rows) { (r: ParameterSearchRow) in row(r) }
            } header: {
                if selecting { header(section) } else { Text(section.title) }
            }
        }
    }

    @ViewBuilder private var resultSection: some View {
        let rows: [ParameterSearchRow] = ParameterSearchRows.rows(query, settings: settings, visual: settings.visual)
        if rows.isEmpty {
            emptyState
        } else {
            Section {
                ForEach(rows) { (r: ParameterSearchRow) in row(r) }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ParameterSearchRows.emptyTitle).font(.headline)
            Text(ParameterSearchRows.emptyHint).font(.footnote).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("parameterSearchEmpty")
    }

    private func rowButton(_ row: ParameterSearchRow) -> some View {
        Button { open(row.id) } label: { ParameterSearchRowLabel(row: row) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.name)
            .accessibilityValue(row.accessibilityValue)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("parameterSearchResult.\(row.id.rawValue)")
    }
}

private struct ParameterSearchRowLabel: View {
    let row: ParameterSearchRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).foregroundStyle(Color.primary)   // ACC-004: label colour, not the tint
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(row.value).monospacedDigit().foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String { row.onScreen ? row.group + " · On screen" : row.group }
}
