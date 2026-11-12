// SyntheticSessionEvents.swift — posts the audio-session notifications iOS posts, for automation
// (AutomationRunner's sc009 lifecycle script) and for the UI tests' session-event panel
// (AUD-014-T21). Compiled only into Debug builds or builds with the PROJECTM_AUTOMATION flag; the
// shipping Release build contains none of it.
//
// The notifications go to the default center with the shared session as their object and the
// documented user-info keys, exactly what the app's observers receive from iOS. They do not
// interrupt anything: the session stays active and no other audio plays. What a real phone call
// does is checked on devices only.
#if DEBUG || PROJECTM_AUTOMATION
import AVFAudio
import Foundation

@MainActor
enum SyntheticSessionEvents {
    /// "Interruption began", or "ended" with or without the resume indication.
    static func postInterruption(_ type: AVAudioSession.InterruptionType, shouldResume: Bool = false) {
        var info: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: type.rawValue]
        if shouldResume { info[AVAudioSessionInterruptionOptionKey] = AVAudioSession.InterruptionOptions.shouldResume.rawValue }
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), userInfo: info)
    }

    /// The output device became unavailable (headphones unplugged).
    static func postOutputRouteLost() {
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(),
                                        userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
    }
}
#endif
