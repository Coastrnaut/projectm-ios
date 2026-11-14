// OSCRoutesView.swift — the OSC Routes screen (OSC-003-R6, R7, R10; specs/191-osc-003-parameter-routes,
// contracts/osc-routes.md R3). Opened from the OSC section in Settings: one row per allowlisted address with its
// target and an on/off toggle, the user's aliases (swipe to delete) and a small form to add one. Small views so
// each body stays under CI's type-check budget. Values are never shown or announced here.
import ParameterGraph
import PerformanceControl
import SwiftUI

struct OSCRoutesView: View {
    var routes: OSCRoutesCoordinator
    /// Messages to addresses not on the list since launch.
    var unknownCount: Int

    var body: some View {
        List {
            OSCRoutesListSection(routes: routes, unknownCount: unknownCount)
            OSCRouteAliasSection(routes: routes)
        }
        .navigationTitle("OSC Routes")
    }
}

private struct OSCRoutesListSection: View {
    var routes: OSCRoutesCoordinator
    var unknownCount: Int

    var body: some View {
        Section {
            ForEach(routes.rows) { (row: OSCRouteRow) in
                OSCRouteToggleRow(routes: routes, row: row)
            }
            LabeledContent("Ignored addresses", value: String(unknownCount))
                .accessibilityIdentifier("oscRoutesIgnored")
        } footer: {
            Text("Send one number from 0 to 1 to an address; it sets the parameter across its whole range. Addresses that are not listed here, or are turned off, are ignored.")
        }
    }
}

private struct OSCRouteToggleRow: View {
    var routes: OSCRoutesCoordinator
    let row: OSCRouteRow

    private var label: String {
        guard let origin = row.originText else { return row.target }
        return row.target + " · " + origin
    }

    var body: some View {
        Toggle(isOn: Binding(get: { () -> Bool in row.isEnabled },
                             set: { (on: Bool) -> Void in routes.setEnabled(on, address: row.address) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.address).font(.body.monospaced())
                Text(label).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(row.address + ", " + label)
        .accessibilityIdentifier(row.accessibilityIdentifier)
        .swipeActions {
            if row.origin == .userAlias {
                Button("Delete", role: .destructive) { routes.deleteAlias(address: row.address) }
            }
        }
    }
}

private struct OSCRouteAliasSection: View {
    var routes: OSCRoutesCoordinator
    @State private var address: String = ""
    @State private var target: ParameterID?

    private var chosen: ParameterID? { target ?? routes.routable.first?.id }

    var body: some View {
        Section {
            TextField("/fader/1", text: $address)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Alias address")
                .accessibilityIdentifier("oscAliasAddress")
            Picker("Parameter", selection: Binding(get: { () -> ParameterID? in chosen },
                                                   set: { (id: ParameterID?) -> Void in target = id })) {
                ForEach(routes.routable, id: \.id) { (descriptor: ParameterDescriptor) in
                    Text(routes.targetName(descriptor.id)).tag(Optional(descriptor.id))
                }
            }
            .accessibilityIdentifier("oscAliasParameter")
            Button("Add Alias", action: add)
                .disabled(address.isEmpty || chosen == nil)
                .accessibilityIdentifier("oscAliasAdd")
            if let error = routes.aliasError {
                Text(error).foregroundStyle(.red).accessibilityIdentifier("oscAliasError")
            }
        } header: {
            Text("Your aliases")
        } footer: {
            Text("Up to \(OSCRouteAliasRules.maximumUserAliases) addresses of your own, outside /projectm/. Swipe an alias to delete it.")
        }
    }

    private func add() {
        guard let chosen else { return }
        if routes.addAlias(address: address, parameter: chosen) { address = "" }
    }
}
