// AudioSessionSignal.swift — what the audio session and the audio engine tell In-App Playback
// (AUD-014-T12; AUD-014-R20; research AUD-014-D1, D10).
//
// The backend handles these platform-neutral signals, so the macOS host can test it without an
// audio session. On iOS `AudioSessionObserver` turns the session's notifications into signals. It
// takes its NotificationCenter and the notifications' object as parameters: production passes the
// default center and the shared session, tests a private center.
//
// Which notifications (iOS 27.2 SDK headers): `AVAudioSessionInterruptionNotification` with its
// type, option and reason keys; `AVAudioSessionRouteChangeNotification` with its reason key;
// `AVAudioSessionMediaServicesWereResetNotification`. The interruption notification is deprecated
// from iOS 27.0 in favor of two notifications that exist only from iOS 27.0; the app supports
// iOS 26, so it uses the one that exists on every supported version, and only that one, so that
// no interruption is reported twice. `AVAudioSessionInterruptionWasSuspendedKey` and the
// "app was suspended" reason are not used: the SDK documents that they are no longer sent from
// iOS 16.
import Foundation
#if os(iOS) && canImport(AVFAudio)
import AVFAudio
#endif

enum AudioSessionSignal: Sendable, Equatable {
    /// `outputDisconnected`: the interruption's reason is a disconnected route.
    case interruptionBegan(outputDisconnected: Bool)
    case interruptionEnded(shouldResume: Bool)
    /// The output device became unavailable (for example headphones unplugged).
    case outputRouteLost
    /// `AVAudioEngineConfigurationChange`: the engine stopped itself because the hardware changed.
    case engineConfigurationChanged
    /// iOS restarted its media services: every audio object of the app is dead.
    case mediaServicesReset
}

#if os(iOS) && canImport(AVFAudio)
extension AudioSessionSignal {
    /// The signal a session notification carries; nil when it is none of ours.
    static func parse(_ note: Notification) -> AudioSessionSignal? {
        switch note.name {
        case AVAudioSession.interruptionNotification:
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            switch type {
            case .began:
                let reason = (note.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt).flatMap(AVAudioSession.InterruptionReason.init)
                return .interruptionBegan(outputDisconnected: reason == .routeDisconnected)
            case .ended:
                let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
                return .interruptionEnded(shouldResume: options.contains(.shouldResume))
            default:
                return nil
            }
        case AVAudioSession.routeChangeNotification:
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            return reason == .oldDeviceUnavailable ? .outputRouteLost : nil
        case AVAudioSession.mediaServicesWereResetNotification:
            return .mediaServicesReset
        default:
            return nil
        }
    }
}

/// Observes one session's notifications on `center` and hands each to `handler` on the main actor.
@MainActor
final class AudioSessionObserver {
    private let center: NotificationCenter
    private let handler: @MainActor (AudioSessionSignal) -> Void
    private var tokens: [any NSObjectProtocol] = []

    /// - Parameter session: the notifications' object (production: `AVAudioSession.sharedInstance()`).
    init(center: NotificationCenter, session: AnyObject, handler: @escaping @MainActor (AudioSessionSignal) -> Void) {
        self.center = center
        self.handler = handler
        let names = [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereResetNotification]
        for name in names {
            tokens.append(center.addObserver(forName: name, object: session, queue: .main) { [weak self] note in
                guard let signal = AudioSessionSignal.parse(note) else { return }
                MainActor.assumeIsolated { self?.handler(signal) }
            })
        }
    }

    /// Stops observing. Idempotent.
    func invalidate() {
        tokens.forEach { center.removeObserver($0) }
        tokens.removeAll()
    }
}
#endif
