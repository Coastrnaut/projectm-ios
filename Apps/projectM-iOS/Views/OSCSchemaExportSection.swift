// OSCSchemaExportSection.swift — OSC-010 (contract osc-schema-export.md C2): the last section of OSC Routes,
// "Export routes…". The button builds the route schema and presents the system share sheet (REC-012
// `ActivitySharePresenter`, placed behind the button so the iPad popover points at it). DEBUG
// `-uitestShareSimulation`: two buttons deliver the outcome and a probe carries the generated text, instead of the
// out-of-process sheet. Works whether OSC is on or off; needs no permission.
import SwiftUI

struct OSCSchemaExportSection: View {
    var routes: OSCRoutesCoordinator
    @State private var export: OSCSchemaExportCoordinator?

    var body: some View {
        Section {
            if let export { OSCSchemaExportRows(export: export) }
        } footer: {
            Text(OSCSchemaExportCoordinator.footer)
        }
        .onAppear {
            if export == nil { export = OSCSchemaExportCoordinator(routes: routes) }
        }
    }
}

private struct OSCSchemaExportRows: View {
    @Bindable var export: OSCSchemaExportCoordinator

    var body: some View {
        exportButton
        if let notice = export.notice {
            Text(notice)
                .font(.footnote)
                .accessibilityIdentifier("oscSchemaExport.notice")
        }
        #if DEBUG
        if export.simulation { simulationRows }
        #endif
    }

    private var exportButton: some View {
        Button(OSCSchemaExportCoordinator.title) { export.export() }
            .accessibilityIdentifier("oscSchemaExport")
            .background {
                if !export.simulation {
                    ActivitySharePresenter(request: export.request, kind: .oscSchema) { (outcome: ShareOutcome) in
                        export.finish(outcome)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
    }

    #if DEBUG
    @ViewBuilder private var simulationRows: some View {
        if export.request != nil {
            let text: String = export.lastText ?? ""
            Text("Generated routes file")
                .font(.caption2)
                .accessibilityIdentifier("oscSchemaExport.probe")
                .accessibilityValue(text)
            Button("Simulate share completed") { export.finish(.completed) }
                .accessibilityIdentifier("simulateShareCompleted")
            Button("Simulate share cancelled") { export.finish(.cancelled) }
                .accessibilityIdentifier("simulateShareCancelled")
        }
    }
    #endif
}
