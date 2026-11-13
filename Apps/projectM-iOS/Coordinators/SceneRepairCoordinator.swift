// SceneRepairCoordinator.swift — the repair report before a scene opens, in the app (SCN-012-R8 to
// R10; contracts/scene-repair-report.md R3; research SCN-012-D5, D6).
//
// * One pending request at a time. A newer request (another show step, Reopen) replaces a pending one
//   and runs its cancel first, so the open closure always belongs to the latest step.
// * Open with repairs: SCN-012's `repairing(with:)` over the request's document, handed to the
//   request's `open`. Nothing is written: the stored file stays as it is (Clarifications Q2).
// * Open as is: only when the report has no errors. Cancel (labelled Close when the scene cannot
//   open): nothing is applied.
// * Openers: show cues (ShowCoordinator) and PERF-010 Reopen (AppCoordinator). The scene archive
//   import result carries its report for the SCN-014 screen; the launch restore stays silent.
// Main actor; the report and repairs are pure (SceneFormat) and small (scenes ≤ 1 MiB).
import Foundation
import Observation
import ParameterGraph
import SceneFormat
import UIKit

/// A scene waiting for the user's choice.
struct SceneRepairRequest: Identifiable {
    let id = UUID()
    /// "Cue 2 · Build", "Last scene".
    let title: String
    let report: SceneRepairReport
    /// nil for a refusal (nothing can open).
    let document: SceneDocument?
    /// Applies the chosen document (repaired or as stored).
    let open: @MainActor (SceneDocument) -> Void
    let cancel: @MainActor () -> Void

    init(title: String, report: SceneRepairReport, document: SceneDocument?,
         open: @escaping @MainActor (SceneDocument) -> Void = { (_: SceneDocument) in },
         cancel: @escaping @MainActor () -> Void = {}) {
        self.title = title
        self.report = report
        self.document = document
        self.open = open
        self.cancel = cancel
    }

    var canOpenWithRepairs: Bool { document != nil && report.canOpenWithRepairs }
    var canOpenAsIs: Bool { document != nil && report.canOpenAsIs }
    /// "Close" when the scene cannot open at all, else "Cancel".
    var cancelTitle: String { canOpenWithRepairs || canOpenAsIs ? "Cancel" : "Close" }
}

@MainActor
@Observable
final class SceneRepairCoordinator {
    private(set) var pending: SceneRepairRequest?

    @ObservationIgnored private let registry: ParameterRegistry?
    /// Which photo and video are stored now (repairs drop the ones that are not).
    @ObservationIgnored var availability: () -> StoredMediaAvailability = { StoredMediaAvailability(photos: [], videos: []) }
    @ObservationIgnored var announce: (String) -> Void = { (message: String) in
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    init(registry: ParameterRegistry?) {
        self.registry = registry
    }

    /// Shows `request`, cancelling a pending one.
    func present(_ request: SceneRepairRequest) {
        if let previous = pending {
            pending = nil
            previous.cancel()
        }
        pending = request
        announce("\(request.title): \(request.report.statusText).")
    }

    /// Open with repairs; false when the request offers none.
    @discardableResult
    func openWithRepairs() -> Bool {
        guard let request = pending, request.canOpenWithRepairs, let document = request.document, let registry else { return false }
        pending = nil
        request.open(document.repairing(with: request.report, registry: registry, assets: availability()))
        return true
    }

    /// Open as is; false when the report has errors.
    @discardableResult
    func openAsIs() -> Bool {
        guard let request = pending, request.canOpenAsIs, let document = request.document else { return false }
        pending = nil
        request.open(document)
        return true
    }

    func cancel() {
        guard let request = pending else { return }
        pending = nil
        request.cancel()
    }
}
