// PermissionExplainer.swift — the explainer shown right before iOS's camera and local network prompts
// (UIX-015; specs/108-uix-015-onboarding-permission-explainer, contracts/permission-explainer.md).
//
// * `PermissionExplainerPolicy` decides from the permission's status and a stored "explained" flag:
//   explain only while iOS has never asked and the user has not continued past this explainer before
//   (UIX-015-R1, R2, R6). Granted, denied, restricted and "iOS will not ask" (nil) never explain.
// * The flag is set on Continue (R3) and never by Not now (R4). Local network has no status query, so
//   it is also set when OSC was already on at launch or the listener was seen listening or denied.
// * The microphone has no flag: iOS reports whether it asked, and FR-005's explainer stays as it is (R9).
// * A DEBUG or automation harness launch suppresses the explainer unless it passes
//   `-uitestPermissionExplainers` (R13; the same rule as UIX-001's guided scene).
// * `PermissionExplainerCoordinator` holds the one pending request and the pick to perform on Continue.
import AVFoundation
import CameraLayer
import Foundation
import Observation
import PerformanceControl

enum PermissionExplainerPolicy {
    static let cameraExplainedKey = "permission.explained.camera"
    static let localNetworkExplainedKey = "permission.explained.localNetwork"
    /// Lets a DEBUG harness launch show the explainers by the normal rule.
    static let testArgument = "-uitestPermissionExplainers"

    /// The stored flag's key; nil for permissions without an explainer of this kind.
    static func key(_ permission: AppPermission) -> String? {
        switch permission {
        case .camera: cameraExplainedKey
        case .localNetwork: localNetworkExplainedKey
        case .microphone, .screenCapture: nil
        }
    }

    /// Contract C2.
    static func shouldExplain(status: PermissionState?, explained: Bool, suppressed: Bool) -> Bool {
        !suppressed && !explained && status == .notDetermined
    }

    /// `harness` is false in Release builds without automation.
    static func isSuppressed(arguments: [String], environment: [String: String], harness: Bool) -> Bool {
        guard harness, !arguments.contains(testArgument) else { return false }
        if environment["XCTestConfigurationFilePath"] != nil || environment["PROJECTM_AUTORUN"] != nil { return true }
        return arguments.contains { (argument: String) -> Bool in argument.hasPrefix("-uitest") || argument == "-autostart" }
    }

    static func harnessSuppresses(processInfo: ProcessInfo = .processInfo) -> Bool {
        #if DEBUG || PROJECTM_AUTOMATION
        let harness = true
        #else
        let harness = false
        #endif
        return isSuppressed(arguments: processInfo.arguments, environment: processInfo.environment, harness: harness)
    }
}

/// The status each explainer reads (research UIX-015 D2).
enum PermissionStatusSource {
    /// The stand-in camera's status (DEBUG `-uitestCamera <scenario>`); nil when iOS would not ask.
    static func camera(scenario: CameraScenario) -> PermissionState? {
        switch scenario {
        case .granted: .granted
        case .denied: .denied
        case .restricted: .restricted
        case .notDeterminedGrant, .notDeterminedDeny: .notDetermined
        case .unavailable: nil
        }
    }

    /// The camera's status at `position`: nil when the device has no camera there (iOS never asks,
    /// CAM-002-R10), else iOS's authorization mapped by the catalog.
    static func camera(position: CameraPosition, arguments: [String] = ProcessInfo.processInfo.arguments) -> PermissionState? {
        #if DEBUG
        if let i = arguments.firstIndex(of: "-uitestCamera"), i + 1 < arguments.count,
           let scenario = CameraScenario(rawValue: arguments[i + 1]) {
            return camera(scenario: scenario)
        }
        #endif
        let avPosition: AVCaptureDevice.Position = position == .front ? .front : .back
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: avPosition) != nil else { return nil }
        return PermissionCatalog.state(cameraAuthorization: AVCaptureDevice.authorizationStatus(for: .video))
    }

    /// Local network: iOS has no query; an observed listener answers, otherwise "not asked" (the
    /// explained flag remembers that iOS asked).
    static func localNetwork(state: OSCReceiverState) -> PermissionState {
        PermissionCatalog.state(localNetwork: state) ?? .notDetermined
    }
}

@MainActor
@Observable
final class PermissionExplainerCoordinator {
    /// The explainer on screen (nil when none).
    private(set) var pending: AppPermission?
    @ObservationIgnored private var action: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored let suppressed: Bool

    init(defaults: UserDefaults = .standard, suppressed: Bool = PermissionExplainerPolicy.harnessSuppresses()) {
        self.defaults = defaults
        self.suppressed = suppressed
    }

    /// `-uitestResetNotice`: nothing explained.
    static func reset(_ defaults: UserDefaults) {
        defaults.removeObject(forKey: PermissionExplainerPolicy.cameraExplainedKey)
        defaults.removeObject(forKey: PermissionExplainerPolicy.localNetworkExplainedKey)
    }

    func isExplained(_ permission: AppPermission) -> Bool {
        guard let key = PermissionExplainerPolicy.key(permission) else { return false }
        return defaults.bool(forKey: key)
    }

    func markExplained(_ permission: AppPermission) {
        guard let key = PermissionExplainerPolicy.key(permission), !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
    }

    /// The user picked a feature that needs `permission`: show the explainer when the policy says so,
    /// otherwise perform the pick at once.
    func request(_ permission: AppPermission, status: PermissionState?, perform: @escaping () -> Void) {
        let explain: Bool = PermissionExplainerPolicy.shouldExplain(status: status, explained: isExplained(permission),
                                                                     suppressed: suppressed)
        guard explain else {
            perform()
            return
        }
        action = perform
        pending = permission
    }

    /// Continue: explained from now on; the pick goes ahead and iOS asks next (UIX-015-R3).
    func continuePending() {
        guard let permission = pending else { return }
        markExplained(permission)
        let perform = action
        action = nil
        pending = nil
        perform?()
    }

    /// Not now: the pick is cancelled; nothing is stored, nothing is asked (UIX-015-R4).
    func notNow() {
        action = nil
        pending = nil
    }
}
