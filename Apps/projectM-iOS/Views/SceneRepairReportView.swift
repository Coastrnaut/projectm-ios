// SceneRepairReportView.swift — the repair report sheet (SCN-012-R2, R8, R13; contracts/
// scene-repair-report.md R4). Grouped entries (each group title is a VoiceOver heading, each entry one
// element), the status, and Open with repairs / Open as is / Cancel (Close when nothing can open).
// Only the buttons dismiss it (a swipe could not tell which request it dismissed when a newer step
// replaces the pending one). Dynamic Type: plain text styles, no fixed sizes.
import SceneFormat
import SwiftUI

struct SceneRepairReportView: View {
    let request: SceneRepairRequest
    let repair: SceneRepairCoordinator
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(request.report.statusText)
                        .font(.headline)
                        .accessibilityIdentifier("sceneRepairStatus")
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(request.report.groups, id: \.self) { (group: SceneRepairReport.Group) in
                    Section {
                        ForEach(Array(request.report.entries(in: group).enumerated()), id: \.offset) {
                            (item: (offset: Int, element: SceneRepairReport.Entry)) in
                            row(item.element)
                        }
                    } header: {
                        Text(group.title)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("sceneRepairGroup.\(group.rawValue)")
                    }
                }
                // ACC-006-R2: at accessibility sizes the three full-width buttons pinned below the list
                // left the entries too little room (audit 2026-11-13, AX5); they scroll with the report as
                // its last section instead.
                if typeSize.isAccessibilitySize {
                    Section { buttons }
                        .listRowInsets(EdgeInsets())
                }
            }
            .accessibilityIdentifier("sceneRepairReport")
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if !typeSize.isAccessibilitySize { buttons.background(.bar) }
            }
        }
    }

    private var summary: String {
        if request.document == nil || request.report.cannotOpen { return "This scene cannot open. Nothing has changed." }
        if !request.report.canOpenAsIs { return "This scene opens only with repairs. The saved scene is not changed." }
        return "Repairs apply to what is shown now; the saved scene is not changed."
    }

    private func row(_ entry: SceneRepairReport.Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.item).font(.subheadline.weight(.semibold))
            Text(entry.problem).font(.footnote)
            Text(entry.ifOpened).font(.footnote).foregroundStyle(.secondary)
            if !entry.actions.isEmpty {
                Text("Repair: " + entry.actions.map(\.title).joined(separator: ", "))
                    .font(.footnote.italic())
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var buttons: some View {
        VStack(spacing: 8) {
            if request.canOpenWithRepairs {
                Button { repair.openWithRepairs() } label: { Text("Open with repairs").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("sceneRepairOpenRepaired")
            }
            if request.canOpenAsIs {
                Button { repair.openAsIs() } label: { Text("Open as is").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("sceneRepairOpenAsIs")
            }
            Button(role: .cancel) { repair.cancel() } label: { Text(request.cancelTitle).frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("sceneRepairCancel")
        }
        .padding()
    }
}

extension View {
    /// Presents the pending repair report while `active` (research SCN-012-D5: the visualizer, or the
    /// Settings sheet while it is shown). The coordinator alone clears the request.
    func sceneRepairSheet(_ repair: SceneRepairCoordinator, active: Bool) -> some View {
        sheet(item: Binding(get: { () -> SceneRepairRequest? in active ? repair.pending : nil },
                            set: { (_: SceneRepairRequest?) in })) { (request: SceneRepairRequest) in
            SceneRepairReportView(request: request, repair: repair)
                .interactiveDismissDisabled()
        }
    }
}
