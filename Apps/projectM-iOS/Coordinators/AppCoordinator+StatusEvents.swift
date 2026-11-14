// AppCoordinator+StatusEvents.swift — the app's status events (ACC-011; contract
// specs/100-acc-011-captioned-status-events/contracts/status-events.md C1).
//
// * `connectStatusEvents()` (from init): the router drops system rows while the scene is not active
//   (ACC-011-R10); the route coordinator (X5) and the repair coordinator (X26) announce through it.
// * `announceSourceStatus()`: one text per source change (ACC-011-R5, research D2). Called by both the
//   state and the stop-reason `.onChange`; when both fire for one change the second text is identical
//   and ACC-004's gate drops it.
import Foundation

extension AppCoordinator {
    func connectStatusEvents() {
        statusEvents.isActive = { [weak self] () -> Bool in self?.appIsActive ?? true }
        routes.announce = { [weak self] (spoken: String) -> Void in
            guard let self else { return }
            let shown: String = self.routes.explanation ?? spoken
            self.statusEvents.post(StatusEventCatalog.route(explanation: shown, spoken: spoken))
        }
        sceneRepair.announce = { [weak self] (spoken: String) -> Void in
            self?.statusEvents.post(StatusEventCatalog.repairReport(spoken))
        }
    }

    /// X1-X3: the source changed (state, stop reason or a switch).
    func announceSourceStatus() {
        let event: StatusEvent = StatusEventCatalog.source(mode: manager.activeMode, state: manager.state,
                                                           signal: testSignalName, switching: manager.switchingTo != nil,
                                                           reason: manager.stopReason)
        statusEvents.post(event)
    }

    /// X24: the recovery offer appeared (once per launch; the card decides when).
    func announceRecoveryOffer() {
        statusEvents.post(StatusEventCatalog.recoveryOffer(title: recovery.title, message: recovery.message))
    }
}
