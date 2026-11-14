// AppCoordinator+Background.swift — the background playback policy in the app (AUD-015; contract
// specs/097-aud-015-background-playback-policy/contracts/background-policy.md, ADR-0036).
//
// The capture layer enforces the policy (CaptureManager + BackgroundPolicy). The app supplies the
// configuration — the `audio` background mode read from its own Info.plist (absent: ADR-0001
// ruling 17 allows only `screen-capture`) and no "keep playing" setting (AUD-015-R3) — and shows the
// return notice (AUD-015-R7).
import CaptureKit
import Foundation

extension AppCoordinator {
    /// The policy configuration for an Info.plist: the audio mode as declared, keep playing off.
    nonisolated static func backgroundConfiguration(infoDictionary: [String: Any]?) -> BackgroundPolicy.Configuration {
        let modes: [String] = infoDictionary?["UIBackgroundModes"] as? [String] ?? []
        let declares: Bool = BackgroundPolicy.declaresAudioMode(in: modes)
        return BackgroundPolicy.Configuration(declaresAudioBackgroundMode: declares, keepPlayingInBackground: false)
    }

    /// The return notice's text, or nil: hidden while the scene is not active and while the source
    /// shows a stop or pause reason, whose banner already explains the state (AUD-015-R7).
    var visibleBackgroundNotice: String? {
        Self.visibleBackgroundNotice(reason: manager.backgroundNotice, sceneActive: appIsActive,
                                     stopReasonShown: manager.stopReason != nil)
    }

    nonisolated static func visibleBackgroundNotice(reason: BackgroundPolicy.Reason?, sceneActive: Bool,
                                                    stopReasonShown: Bool) -> String? {
        guard sceneActive, !stopReasonShown else { return nil }
        return reason?.notice
    }

    /// How long the return notice stays (AUD-015-R7).
    static let backgroundNoticeDuration: Duration = .seconds(8)

    func dismissBackgroundNotice() {
        manager.dismissBackgroundNotice()
    }
}
