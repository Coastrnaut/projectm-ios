// AudioSessionSignalTests.swift — what the audio session tells the playback backend (AUD-014-T04;
// AUD-014-R20; research AUD-014-D1, D10). The notifications are posted to a private
// NotificationCenter with the documented keys and values; nothing here touches the real session.
#if os(iOS) && canImport(AVFAudio)
import AVFAudio
import XCTest
@testable import CaptureKit

@MainActor
final class AudioSessionSignalTests: XCTestCase {
    private func interruption(_ type: AVAudioSession.InterruptionType?, options: UInt? = nil, reason: UInt? = nil) -> Notification {
        var info: [AnyHashable: Any] = [:]
        if let type { info[AVAudioSessionInterruptionTypeKey] = type.rawValue }
        if let options { info[AVAudioSessionInterruptionOptionKey] = options }
        if let reason { info[AVAudioSessionInterruptionReasonKey] = reason }
        return Notification(name: AVAudioSession.interruptionNotification, object: nil, userInfo: info)
    }

    private func route(_ reason: AVAudioSession.RouteChangeReason) -> Notification {
        Notification(name: AVAudioSession.routeChangeNotification, object: nil,
                     userInfo: [AVAudioSessionRouteChangeReasonKey: reason.rawValue])
    }

    func testInterruptionNotificationsAreParsed() {
        XCTAssertEqual(AudioSessionSignal.parse(interruption(.began)), .interruptionBegan(outputDisconnected: false))
        XCTAssertEqual(AudioSessionSignal.parse(interruption(.began, reason: 0)), .interruptionBegan(outputDisconnected: false))
        XCTAssertEqual(AudioSessionSignal.parse(interruption(.began, reason: 2)), .interruptionBegan(outputDisconnected: false),
                       "built-in microphone muted: an ordinary interruption for playback")
        XCTAssertEqual(AudioSessionSignal.parse(interruption(.began, reason: 4)), .interruptionBegan(outputDisconnected: true),
                       "AVAudioSessionInterruptionReasonRouteDisconnected")
        XCTAssertEqual(AVAudioSession.InterruptionReason.routeDisconnected.rawValue, 4)
        XCTAssertEqual(AudioSessionSignal.parse(interruption(.ended, options: AVAudioSession.InterruptionOptions.shouldResume.rawValue)),
                       .interruptionEnded(shouldResume: true))
        XCTAssertEqual(AudioSessionSignal.parse(interruption(.ended, options: 0)), .interruptionEnded(shouldResume: false))
        XCTAssertEqual(AudioSessionSignal.parse(interruption(.ended)), .interruptionEnded(shouldResume: false),
                       "no option key means no resume indication")
        XCTAssertNil(AudioSessionSignal.parse(interruption(nil)), "no type: ignored")
        XCTAssertNil(AudioSessionSignal.parse(Notification(name: AVAudioSession.interruptionNotification, object: nil,
                                                           userInfo: [AVAudioSessionInterruptionTypeKey: UInt(99)])))
    }

    func testRouteAndResetNotificationsAreParsed() {
        XCTAssertEqual(AudioSessionSignal.parse(route(.oldDeviceUnavailable)), .outputRouteLost)
        for reason in [AVAudioSession.RouteChangeReason.newDeviceAvailable, .categoryChange, .override, .routeConfigurationChange, .unknown] {
            XCTAssertNil(AudioSessionSignal.parse(route(reason)), "\(reason.rawValue)")
        }
        XCTAssertEqual(AudioSessionSignal.parse(Notification(name: AVAudioSession.mediaServicesWereResetNotification)), .mediaServicesReset)
        XCTAssertNil(AudioSessionSignal.parse(Notification(name: Notification.Name("somethingElse"))))
    }

    func testObserverDeliversEachNotificationOnceAndNothingAfterInvalidate() {
        let center = NotificationCenter()
        let session = NSObject()
        var received: [AudioSessionSignal] = []
        let observer = AudioSessionObserver(center: center, session: session) { received.append($0) }

        center.post(name: AVAudioSession.interruptionNotification, object: session,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        center.post(name: AVAudioSession.interruptionNotification, object: session,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                               AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue])
        center.post(name: AVAudioSession.routeChangeNotification, object: session,
                    userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: session)
        XCTAssertEqual(received, [.interruptionBegan(outputDisconnected: false), .interruptionEnded(shouldResume: true),
                                  .outputRouteLost, .mediaServicesReset])

        // Another object's notifications are not this session's.
        center.post(name: AVAudioSession.interruptionNotification, object: NSObject(),
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        XCTAssertEqual(received.count, 4)

        observer.invalidate()
        observer.invalidate()                         // idempotent
        center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: session)
        XCTAssertEqual(received.count, 4, "nothing after invalidate")
    }
}
#endif
