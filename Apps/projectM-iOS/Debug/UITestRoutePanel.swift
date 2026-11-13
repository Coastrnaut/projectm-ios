// UITestRoutePanel.swift — a fake audio route and buttons that change it, for RouteIndicatorUITests
// (AUD-007-T13, AUD-007-R15). DEBUG builds only, and only with the launch argument
// `-uitestFakeRoutes`; Release builds contain none of this.
//
// The simulator's route never changes, so the route indicator reads this settable fake instead of
// the session. Each button sets the fake's next route, then posts the real route-change
// notification with the reason iOS would give. Every observer of that notification reacts as on a
// device: the indicator's observer reads the fake route, and AUD-014's In-App Playback backend
// pauses on "old device unavailable". It is never device evidence (AUD-007-T16 is).
#if DEBUG
import AVFAudio
import CaptureKit
import SwiftUI

@MainActor
final class UITestRouteProvider: AudioRouteProviding {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-uitestFakeRoutes") }
    static let shared = UITestRouteProvider()

    static let speaker = RoutePort(kind: .builtInSpeaker, name: "Speaker")
    static let wired = RoutePort(kind: .wiredHeadphones, name: "Headphones")
    static let bluetooth = RoutePort(kind: .bluetoothA2DP, name: "Bluetooth Headphones")
    static let microphone = RoutePort(kind: .builtInMic, name: "iPhone Microphone")

    var currentRoute = AudioRoute(inputs: [microphone], outputs: [speaker])

    /// Sets the route, then posts the session's route-change notification with `reason`.
    func change(to output: RoutePort, reason: AVAudioSession.RouteChangeReason) {
        currentRoute = AudioRoute(inputs: [Self.microphone], outputs: [output])
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(),
                                        userInfo: [AVAudioSessionRouteChangeReasonKey: reason.rawValue])
    }
}

struct UITestRoutePanel: View {
    var body: some View {
        let fake = UITestRouteProvider.shared
        HStack(spacing: 2) {
            button("route:wiredIn") { fake.change(to: UITestRouteProvider.wired, reason: .newDeviceAvailable) }
            button("route:wiredOut") { fake.change(to: UITestRouteProvider.speaker, reason: .oldDeviceUnavailable) }
            button("route:bluetoothIn") { fake.change(to: UITestRouteProvider.bluetooth, reason: .newDeviceAvailable) }
            button("route:bluetoothOut") { fake.change(to: UITestRouteProvider.speaker, reason: .oldDeviceUnavailable) }
        }
        .font(.system(size: 9))
        .buttonStyle(.bordered)
        .padding(4)
        .background(.black.opacity(0.6))
    }

    private func button(_ id: String, action: @escaping () -> Void) -> some View {
        Button(id, action: action).accessibilityIdentifier(id)
    }
}
#endif
