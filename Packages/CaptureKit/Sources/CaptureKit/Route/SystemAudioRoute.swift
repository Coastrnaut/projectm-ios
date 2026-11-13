// SystemAudioRoute.swift — the audio session's route for AUD-007 (AUD-007-T08; research
// AUD-007-D1, D4). iOS only: `AVAudioSession` does not exist on macOS or Linux.
//
// `SystemAudioRouteProvider` reads `AVAudioSession.sharedInstance().currentRoute`;
// `AudioRouteObserver` observes `AVAudioSession.routeChangeNotification` on a given center and
// object (production: the default center and the shared session; tests: a private center, as
// AUD-014's `AudioSessionObserver`) and hands each change to an `AudioRouteMonitor` on the main
// actor. Port names are passed through verbatim and never logged.
#if os(iOS) && canImport(AVFAudio)
import AVFAudio
import Foundation

extension AudioRoute {
    /// The values of a session route description.
    public init(_ description: AVAudioSessionRouteDescription) {
        self.init(inputs: description.inputs.map { RoutePort(kind: RoutePortKind(portType: $0.portType.rawValue, direction: .input), name: $0.portName) },
                  outputs: description.outputs.map { RoutePort(kind: RoutePortKind(portType: $0.portType.rawValue, direction: .output), name: $0.portName) })
    }
}

/// Reads the shared audio session's current route.
@MainActor
public final class SystemAudioRouteProvider: AudioRouteProviding {
    public init() {}

    public var currentRoute: AudioRoute {
        AudioRoute(AVAudioSession.sharedInstance().currentRoute)
    }
}

/// Turns the session's route-change notifications into monitor changes.
@MainActor
public final class AudioRouteObserver {
    private let center: NotificationCenter
    private var token: (any NSObjectProtocol)?

    /// - Parameter session: the notifications' object (production: `AVAudioSession.sharedInstance()`).
    public init(center: NotificationCenter = .default, session: AnyObject = AVAudioSession.sharedInstance(),
                monitor: AudioRouteMonitor) {
        self.center = center
        token = center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak monitor] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            MainActor.assumeIsolated {
                _ = monitor?.routeDidChange(reason: AudioRouteChangeReason(rawReason: raw))
            }
        }
    }

    /// Stops observing. Idempotent.
    public func invalidate() {
        if let token { center.removeObserver(token) }
        token = nil
    }
}
#endif
