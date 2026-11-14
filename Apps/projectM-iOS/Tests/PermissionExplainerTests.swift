// PermissionExplainerTests.swift — UIX-015-T05: the explain / prompt / denied / no-nag state machine per
// permission with an injected status (contract C2), the stored flags, the harness rule, the stand-in
// camera's status, the local network status and the catalog's fallbacks. In-memory UserDefaults
// suites; no UI, no camera, no network. Budget: well under 1 s for the file (owner rule 7).
import CameraLayer
import PerformanceControl
import XCTest
@testable import projectM_iOS

final class PermissionExplainerPolicyTests: XCTestCase {
    typealias P = PermissionExplainerPolicy

    func testDecisionTable() {
        let states: [PermissionState?] = [.notDetermined, .granted, .denied, .restricted, nil]
        for status in states {
            for explained in [false, true] {
                for suppressed in [false, true] {
                    let expected = status == .notDetermined && !explained && !suppressed
                    XCTAssertEqual(P.shouldExplain(status: status, explained: explained, suppressed: suppressed), expected,
                                   "\(String(describing: status)) explained \(explained) suppressed \(suppressed)")
                }
            }
        }
    }

    func testKeysOnlyForCameraAndLocalNetwork() {
        XCTAssertEqual(P.key(.camera), "permission.explained.camera")
        XCTAssertEqual(P.key(.localNetwork), "permission.explained.localNetwork")
        XCTAssertNil(P.key(.microphone), "the microphone keeps FR-005 (iOS's status is its flag)")
        XCTAssertNil(P.key(.screenCapture))
    }

    func testHarnessRule() {
        XCTAssertFalse(P.isSuppressed(arguments: ["-uitestCamera", "denied"], environment: [:], harness: false), "Release never suppresses")
        XCTAssertTrue(P.isSuppressed(arguments: ["-uitestCamera", "denied"], environment: [:], harness: true))
        XCTAssertTrue(P.isSuppressed(arguments: ["-autostart", "inAppPlayback"], environment: [:], harness: true))
        XCTAssertTrue(P.isSuppressed(arguments: [], environment: ["XCTestConfigurationFilePath": "x"], harness: true))
        XCTAssertTrue(P.isSuppressed(arguments: [], environment: ["PROJECTM_AUTORUN": "sc101"], harness: true))
        XCTAssertFalse(P.isSuppressed(arguments: ["-uitestCamera", "denied", P.testArgument], environment: ["XCTestConfigurationFilePath": "x"],
                                      harness: true), "the opt-in argument shows explainers")
        XCTAssertFalse(P.isSuppressed(arguments: [], environment: [:], harness: true), "a normal launch")
    }
}

final class PermissionStatusSourceTests: XCTestCase {
    func testStandInCameraStatus() {
        XCTAssertEqual(PermissionStatusSource.camera(scenario: .notDeterminedGrant), .notDetermined)
        XCTAssertEqual(PermissionStatusSource.camera(scenario: .notDeterminedDeny), .notDetermined)
        XCTAssertEqual(PermissionStatusSource.camera(scenario: .granted), .granted)
        XCTAssertEqual(PermissionStatusSource.camera(scenario: .denied), .denied)
        XCTAssertEqual(PermissionStatusSource.camera(scenario: .restricted), .restricted, "restricted: iOS cannot ask, no explainer")
        XCTAssertNil(PermissionStatusSource.camera(scenario: .unavailable), "no camera: iOS never asks, no explainer")
    }

    func testLocalNetworkStatus() {
        XCTAssertEqual(PermissionStatusSource.localNetwork(state: .off), .notDetermined)
        XCTAssertEqual(PermissionStatusSource.localNetwork(state: .listening(port: 9000)), .granted)
        XCTAssertEqual(PermissionStatusSource.localNetwork(state: .failed(port: 9000, .localNetworkDenied)), .denied)
        XCTAssertEqual(PermissionStatusSource.localNetwork(state: .failed(port: 9000, .portInUse)), .notDetermined)
    }
}

@MainActor
final class PermissionExplainerCoordinatorTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "UIX015-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testNotNowAsksNothingAndStoresNothing() {
        for permission in [AppPermission.camera, .localNetwork] {
            let coordinator = PermissionExplainerCoordinator(defaults: makeDefaults(), suppressed: false)
            var performed = 0
            coordinator.request(permission, status: .notDetermined) { performed += 1 }
            XCTAssertEqual(coordinator.pending, permission, "the explainer before iOS's prompt")
            XCTAssertEqual(performed, 0, "nothing starts (no prompt) while the explainer is shown")
            coordinator.notNow()
            XCTAssertNil(coordinator.pending)
            XCTAssertEqual(performed, 0, "Not now: no prompt")
            XCTAssertFalse(coordinator.isExplained(permission), "Not now stores nothing (R4)")
            coordinator.request(permission, status: .notDetermined) { performed += 1 }
            XCTAssertEqual(coordinator.pending, permission, "the next pick explains again (R4)")
        }
    }

    func testContinuePerformsOnceAndNeverExplainsAgain() {
        let defaults = makeDefaults()
        for permission in [AppPermission.camera, .localNetwork] {
            let coordinator = PermissionExplainerCoordinator(defaults: defaults, suppressed: false)
            var performed = 0
            coordinator.request(permission, status: .notDetermined) { performed += 1 }
            coordinator.continuePending()
            XCTAssertNil(coordinator.pending)
            XCTAssertEqual(performed, 1, "Continue goes ahead; iOS asks next")
            XCTAssertTrue(coordinator.isExplained(permission))
            // Denied afterwards (or the stand-in still says not asked): no explainer, ever (R6).
            for status in [PermissionState.denied, .notDetermined, .restricted] {
                coordinator.request(permission, status: status) { performed += 1 }
                XCTAssertNil(coordinator.pending, "\(permission) \(status): no nagging")
            }
            XCTAssertEqual(performed, 4)
            let relaunched = PermissionExplainerCoordinator(defaults: defaults, suppressed: false)
            relaunched.request(permission, status: .notDetermined) {}
            XCTAssertNil(relaunched.pending, "the flag is stored: no explainer after a relaunch")
        }
    }

    func testDecidedStatusesAndSuppressionGoAheadAtOnce() {
        let coordinator = PermissionExplainerCoordinator(defaults: makeDefaults(), suppressed: false)
        var performed = 0
        for status in [PermissionState.granted, .denied, .restricted] {
            coordinator.request(.camera, status: status) { performed += 1 }
        }
        coordinator.request(.camera, status: nil) { performed += 1 }   // no camera: iOS never asks
        XCTAssertNil(coordinator.pending)
        XCTAssertEqual(performed, 4)
        XCTAssertFalse(coordinator.isExplained(.camera), "going ahead without explaining stores nothing")

        let suppressed = PermissionExplainerCoordinator(defaults: makeDefaults(), suppressed: true)
        suppressed.request(.localNetwork, status: .notDetermined) { performed += 1 }
        XCTAssertNil(suppressed.pending, "harness launches skip the explainer")
        XCTAssertEqual(performed, 5)
    }

    func testMarkExplainedAndReset() {
        let defaults = makeDefaults()
        let coordinator = PermissionExplainerCoordinator(defaults: defaults, suppressed: false)
        coordinator.markExplained(.localNetwork)   // OSC on at launch, or a listener seen
        coordinator.markExplained(.microphone)     // no key: ignored
        XCTAssertTrue(coordinator.isExplained(.localNetwork))
        XCTAssertFalse(coordinator.isExplained(.microphone))
        XCTAssertNil(defaults.object(forKey: PermissionExplainerPolicy.cameraExplainedKey))
        PermissionExplainerCoordinator.reset(defaults)
        XCTAssertFalse(coordinator.isExplained(.localNetwork))
    }
}

final class PermissionExplainerCatalogTests: XCTestCase {
    typealias C = PermissionCatalog

    func testExplainerTextsComeFromTheCatalog() {
        XCTAssertEqual(C.explainerFallback(.camera), "If you don't allow it, the Camera visual shows the spectrum only.")
        XCTAssertEqual(C.explainerFallback(.localNetwork), "If you don't allow it, OSC control stays unavailable and everything else works.")
        XCTAssertNil(C.explainerFallback(.microphone), "FR-005's explainer is unchanged")
        XCTAssertEqual(C.entry(.camera).name, "Camera")
        XCTAssertEqual(C.entry(.localNetwork).name, "Local Network")
    }

    func testNoticesNameTheFallbackAndOnlyTheCameraDismisses() {
        for state in [PermissionState.denied, .restricted] {
            let camera = C.notice(.camera, state)
            XCTAssertEqual(camera?.fallback, "Showing the spectrum only.")
            XCTAssertEqual(camera?.offersDismiss, true)
            XCTAssertEqual(camera?.offersSettings, true)
            let network = C.notice(.localNetwork, state)
            XCTAssertEqual(network?.fallback, "OSC control is unavailable; everything else works as usual.")
            XCTAssertEqual(network?.offersDismiss, false, "inline in Settings, never elsewhere")
            XCTAssertNil(C.notice(.microphone, state)?.fallback, "contract banner unchanged")
        }
        let paused = C.cameraNotice(for: .interrupted, reason: .otherInterruption)
        XCTAssertEqual(paused?.offersDismiss, false, "CAM-013's notices keep their rules")
        XCTAssertNil(paused?.fallback)
        XCTAssertEqual(C.cameraNotice(for: .denied)?.text, "Camera access is off. To show the camera, allow it in Settings.",
                       "CAM-001's text unchanged (R10)")
    }
}
