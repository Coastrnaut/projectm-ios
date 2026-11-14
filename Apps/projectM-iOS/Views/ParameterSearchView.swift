// ParameterSearchView.swift — Settings › Search Parameters (UIX-009-R5 to R8; contracts/parameter-search.md S4).
//
// * `ParameterSearchLinkSection`: the Settings row (next to Modulation) that pushes the search.
// * `ParameterSearchView`: a searchable list over every MOD-001 parameter, whatever the visual on screen. An empty
//   query lists every parameter under its group; a query lists ranked rows; nothing matching says so. Choosing a
//   row opens the UIX-003 inspector over Settings for that ID (the visual is not changed).
// Bodies stay small (Xcode 26 type-check budget).
import ParameterGraph
import SwiftUI

struct ParameterSearchLinkSection: View {
    let settings: AppSettings
    let open: (ParameterID) -> Void

    var body: some View {
        Section {
            NavigationLink {
                ParameterSearchView(settings: settings, open: open)
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
    @State private var query = ""

    private var trimmedQueryIsEmpty: Bool { ParameterSearch.words(query).isEmpty }

    var body: some View {
        List {
            if trimmedQueryIsEmpty { indexSections } else { resultSection }
        }
        .navigationTitle("Search Parameters")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Name, group or unit"))
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .accessibilityIdentifier("parameterSearch")
    }

    private var indexSections: some View {
        let sections: [ParameterSearchSection] = ParameterSearchRows.sections(settings: settings, visual: settings.visual)
        return ForEach(sections) { (section: ParameterSearchSection) in
            Section(section.title) {
                ForEach(section.rows) { (row: ParameterSearchRow) in rowButton(row) }
            }
        }
    }

    @ViewBuilder private var resultSection: some View {
        let rows: [ParameterSearchRow] = ParameterSearchRows.rows(query, settings: settings, visual: settings.visual)
        if rows.isEmpty {
            emptyState
        } else {
            Section {
                ForEach(rows) { (row: ParameterSearchRow) in rowButton(row) }
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
