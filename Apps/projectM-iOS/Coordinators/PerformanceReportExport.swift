// PerformanceReportExport.swift — PERF-012 (specs/209-perf-012-performance-report, R1, R2; contract
// performance-report-export.md C2, C3; research PERF-012-D6): Settings → Performance → Export performance report.
//
// * Only the user's tap exports. The report is built and encoded at that moment, written as a temporary REC-012 share
//   copy (`<tmp>/Sharing/<UUID>/projectM-performance-<UTC>.json`) and handed to the system share sheet; every outcome
//   deletes the copy. The app sends nothing anywhere and stores nothing.
// * A failed build or write shows the REC-012 failure notice and no sheet.
// * DEBUG `-uitestShareSimulation`: the section shows the two simulation buttons instead of the sheet (REC-012-R14).
import Diagnostics
import Foundation
import Observation

@MainActor
@Observable
final class PerformanceReportExport {
    static let title = "Export performance report"
    static let footer = "Saves a JSON file with frame times, dropped frames, thermal, Low Power and power profile "
        + "changes, render scale and memory counters, and opens the share sheet. It holds no media, names, text or "
        + "addresses. Frame times are measured while the performance overlay is shown."

    private(set) var request: CaptureShareCoordinator.Request?
    private(set) var notice: String?
    private(set) var lastOutcome: ShareOutcome?
    let simulation: Bool

    @ObservationIgnored let store: ShareFileStore
    @ObservationIgnored private let build: @MainActor (Date) throws -> Data

    init(store: ShareFileStore = ShareFileStore(), simulation: Bool = CaptureShareCoordinator.simulationFromArguments(),
         build: @escaping @MainActor (Date) throws -> Data) {
        self.store = store
        self.simulation = simulation
        self.build = build
    }

    /// The Export button: builds the report now and offers its copy; false when one is already offered or it failed.
    @discardableResult
    func export(now: Date = Date()) -> Bool {
        guard request == nil else { return false }
        do {
            let data: Data = try build(now)
            let url: URL = try store.makeCopy(data: data, named: DiagnosticsExporter.performanceReportName(for: now))
            request = CaptureShareCoordinator.Request(id: UUID(), kind: .performanceReport, url: url)
            notice = nil
            return true
        } catch {
            notice = ShareFileStore.failureNotice
            return false
        }
    }

    /// The sheet closed: the copy is deleted (REC-012-R4, R5).
    func finish(_ outcome: ShareOutcome) {
        guard let request else { return }
        store.remove(request.url)
        self.request = nil
        lastOutcome = outcome
        notice = outcome.notice
    }
}
