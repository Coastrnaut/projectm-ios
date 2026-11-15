// OSCSchemaExportCoordinator.swift — Settings › OSC › OSC Routes › "Export routes…" (OSC-010-R1, R4, R5, R7;
// specs/282-osc-010-osc-schema-export, contracts/osc-schema-export.md C2).
//
// * Only the user's tap exports. The Markdown schema (PerformanceControl `OSCSchemaExport`) is built at that moment
//   from the same `OSCRoutesCoordinator` the screen shows: its route table, disabled addresses and routable
//   descriptors, plus the OSC-001 test value's descriptor, the app version and the injected clock's time.
// * Nothing else is read: no settings store, peers, port or send destination is an input, so none can reach the file
//   (OSC-010-R5; OSCSchemaExportCoordinatorTests seeds them and scans the output).
// * The text is written as a REC-012 share copy (`<tmp>/Sharing/<UUID>/projectM-osc-routes-<UTC>Z.md`) and handed to
//   the system share sheet; every outcome deletes the copy. The app uploads nothing and stores nothing.
// * DEBUG `-uitestShareSimulation`: the section shows the simulation buttons and a probe with the generated text.
import Foundation
import Observation
import ParameterGraph
import PerformanceControl

@MainActor
@Observable
final class OSCSchemaExportCoordinator {
    static let title = "Export routes…"
    static let footer = "Saves a text file listing every OSC address above with its parameter, the number it takes and "
        + "the value range, and opens the share sheet. It holds no network addresses, ports or device names."

    private(set) var request: CaptureShareCoordinator.Request?
    private(set) var notice: String?
    private(set) var lastOutcome: ShareOutcome?
    /// The last generated document (DEBUG probe and tests); memory only.
    private(set) var lastText: String?
    let simulation: Bool

    @ObservationIgnored let store: ShareFileStore
    @ObservationIgnored private let routes: OSCRoutesCoordinator
    @ObservationIgnored private let appVersion: String
    @ObservationIgnored private let now: () -> Date

    init(routes: OSCRoutesCoordinator, store: ShareFileStore = ShareFileStore(),
         simulation: Bool = CaptureShareCoordinator.simulationFromArguments(),
         appVersion: String = UserPresetsCoordinator.bundleVersion(.main), now: @escaping () -> Date = { () -> Date in Date() }) {
        self.routes = routes
        self.store = store
        self.simulation = simulation
        self.appVersion = appVersion
        self.now = now
    }

    /// The document for the routes as they are now, at `seconds` since 1970.
    func document(exportedAt seconds: Int64) -> String {
        let descriptors: [ParameterDescriptor] = routes.routable + [OSCReceiverCatalog.testValueDescriptor]
        let rows: [OSCSchemaRow] = OSCSchemaExport.rows(table: routes.table, disabled: routes.disabled, descriptors: descriptors,
                                                        displayName: { [routes] (id: ParameterID) -> String in routes.targetName(id) })
        return OSCSchemaExport.document(rows: rows, appVersion: appVersion, exportedAt: seconds)
    }

    /// The Export button: builds the file now and offers it; false when one is already offered or the write failed.
    @discardableResult
    func export() -> Bool {
        guard request == nil else { return false }   // one sheet at a time
        let seconds: Int64 = Int64(now().timeIntervalSince1970.rounded(.down))
        let text: String = document(exportedAt: seconds)
        lastText = text
        do {
            let url: URL = try store.makeCopy(data: Data(text.utf8), named: OSCSchemaExport.fileName(exportedAt: seconds))
            request = CaptureShareCoordinator.Request(id: UUID(), kind: .oscSchema, url: url)
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
