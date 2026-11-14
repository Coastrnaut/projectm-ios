// PerformanceReportSection.swift — PERF-012 (contract performance-report-export.md C2, C3): Settings → Performance →
// "Export performance report", after the performance overlay toggle and the power profile.
//
// The button builds the report and presents the system share sheet (REC-012 `ActivitySharePresenter`, placed behind
// the button so the iPad popover points at it). DEBUG `-uitestShareSimulation`: two buttons deliver the outcome and a
// probe reports the share copies left, instead of the out-of-process sheet.
import SwiftUI

struct PerformanceReportSection: View {
    @Bindable var export: PerformanceReportExport

    var body: some View {
        Section {
            exportButton
            if let notice = export.notice {
                Text(notice)
                    .font(.footnote)
                    .accessibilityIdentifier("performanceReport.notice")
            }
            #if DEBUG
            if export.simulation { simulationRows }
            #endif
        } footer: {
            Text(PerformanceReportExport.footer)
        }
    }

    private var exportButton: some View {
        Button(PerformanceReportExport.title) { export.export() }
            .accessibilityIdentifier("performanceReport.export")
            .background {
                if !export.simulation {
                    ActivitySharePresenter(request: export.request, kind: .performanceReport) { (outcome: ShareOutcome) in
                        export.finish(outcome)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
    }

    #if DEBUG
    @ViewBuilder private var simulationRows: some View {
        let value: String = "copies=" + String(export.store.fileCount()) + " last=" + (export.lastOutcome?.rawValue ?? "none")
        Text(value)
            .font(.caption2)
            .accessibilityIdentifier("performanceReport.probe")
            .accessibilityValue(value)
        if export.request != nil {
            Button("Simulate share completed") { export.finish(.completed) }
                .accessibilityIdentifier("simulateShareCompleted")
            Button("Simulate share cancelled") { export.finish(.cancelled) }
                .accessibilityIdentifier("simulateShareCancelled")
        }
    }
    #endif
}
