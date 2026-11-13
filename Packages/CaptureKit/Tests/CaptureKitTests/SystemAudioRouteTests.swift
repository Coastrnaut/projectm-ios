// SystemAudioRouteTests.swift — the iOS half of AUD-007's route model (AUD-007-T04; AUD-007-R1,
// R3, R9, R12; S1, S4): the SDK's port and reason constants, the notification observer on a private
// center, and agreement with AUD-014's pause on a lost output. iOS (simulator) only: the audio
// session does not exist on macOS or Linux. The simulator's real route never changes; the routes
// here are injected.
#if os(iOS) && canImport(AVFAudio) && canImport(CryptoKit) && canImport(UniformTypeIdentifiers)
@testable import AudioCore
import AVFAudio
import Foundation
import XCTest
@testable import CaptureKit

@MainActor
private final class SettableRouteProvider: AudioRouteProviding {
    var currentRoute: AudioRoute
    init(_ route: AudioRoute) { currentRoute = route }
}

@MainActor
final class SystemAudioRouteTests: XCTestCase {
    private let speaker = RoutePort(kind: .builtInSpeaker, name: "Speaker")
    private let wired = RoutePort(kind: .wiredHeadphones, name: "Headphones")

    func testTheSDKPortConstantsMapAsTheContractSays() {
        let outputs: [(AVAudioSession.Port, RoutePortKind)] = [
            (.builtInSpeaker, .builtInSpeaker), (.builtInReceiver, .builtInReceiver), (.headphones, .wiredHeadphones),
            (.bluetoothA2DP, .bluetoothA2DP), (.bluetoothLE, .bluetoothLE), (.bluetoothHFP, .bluetoothHFP),
            (.airPlay, .airPlay), (.HDMI, .hdmi), (.usbAudio, .usbAudio), (.carAudio, .carAudio), (.lineOut, .lineOut),
            (.thunderbolt, .other), (.virtual, .other), (.displayPort, .other),
        ]
        for (port, kind) in outputs {
            XCTAssertEqual(RoutePortKind(portType: port.rawValue, direction: .output), kind, port.rawValue)
        }
        let inputs: [(AVAudioSession.Port, RoutePortKind)] = [
            (.builtInMic, .builtInMic), (.headsetMic, .headsetMic), (.lineIn, .lineIn),
            (.bluetoothHFP, .bluetoothHFP), (.usbAudio, .usbAudio), (.carAudio, .carAudio),
        ]
        for (port, kind) in inputs {
            XCTAssertEqual(RoutePortKind(portType: port.rawValue, direction: .input), kind, port.rawValue)
        }
    }

    func testTheSDKReasonsHaveTheModelsRawValues() {
        let pairs: [(AVAudioSession.RouteChangeReason, AudioRouteChangeReason)] = [
            (.unknown, .unknown), (.newDeviceAvailable, .newDeviceAvailable), (.oldDeviceUnavailable, .oldDeviceUnavailable),
            (.categoryChange, .categoryChange), (.override, .override), (.wakeFromSleep, .wakeFromSleep),
            (.noSuitableRouteForCategory, .noSuitableRouteForCategory), (.routeConfigurationChange, .routeConfigurationChange),
        ]
        for (sdk, model) in pairs { XCTAssertEqual(AudioRouteChangeReason(rawReason: sdk.rawValue), model, "\(sdk.rawValue)") }
    }

    /// AUD-007-R9: AUD-014's signal and the explanation use one rule.
    func testAUD014PausesExactlyForTheReasonsTheSharedRuleNames() {
        for reason in AudioRouteChangeReason.allCases {
            let note = Notification(name: AVAudioSession.routeChangeNotification, object: nil,
                                    userInfo: [AVAudioSessionRouteChangeReasonKey: reason.rawValue])
            let signal = AudioSessionSignal.parse(note)
            XCTAssertEqual(signal == .outputRouteLost, reason.pausesInAppPlayback, "\(reason)")
        }
    }

    func testThePostedNotificationReachesTheMonitorWithItsReason() {
        let center = NotificationCenter()
        let session = AVAudioSession.sharedInstance()
        let provider = SettableRouteProvider(AudioRoute(inputs: [], outputs: [speaker]))
        let monitor = AudioRouteMonitor(provider: provider)
        let observer = AudioRouteObserver(center: center, session: session, monitor: monitor)
        defer { observer.invalidate() }

        provider.currentRoute = AudioRoute(inputs: [], outputs: [wired])
        center.post(name: AVAudioSession.routeChangeNotification, object: session,
                    userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue])
        XCTAssertEqual(monitor.lastChange?.reason, .newDeviceAvailable)
        XCTAssertEqual(monitor.lastChange?.summary(.output), .switched(to: wired))

        center.post(name: AVAudioSession.routeChangeNotification, object: NSObject(), userInfo: nil)
        XCTAssertEqual(monitor.lastChange?.sequence, 1, "another object's notification is ignored")
        observer.invalidate()
        center.post(name: AVAudioSession.routeChangeNotification, object: session, userInfo: nil)
        XCTAssertEqual(monitor.lastChange?.sequence, 1, "nothing after invalidate")
    }

    /// AUD-007-S4 / AUD-014-R14: one unplug both pauses playback and reads "— paused".
    func testAnUnplugPausesInAppPlaybackAndTheExplanationSaysPaused() async throws {
        let root = try AudioFixtures.makeTemporaryDirectory("aud007-route")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try AudioFixtures.writeCounter(to: root.appendingPathComponent("a.caf"), frames: 44_100)
        let item = PlaybackItem(id: "a", title: "a", durationSeconds: 1, track: .file(url))

        let center = NotificationCenter()
        let session = AVAudioSession.sharedInstance()
        let provider = SettableRouteProvider(AudioRoute(inputs: [], outputs: [wired]))
        let monitor = AudioRouteMonitor(provider: provider)
        let observer = AudioRouteObserver(center: center, session: session, monitor: monitor)
        defer { observer.invalidate() }
        let backend = AVInAppPlaybackBackend(offlineSampleRate: 44_100, notificationCenter: center)
        let source = InAppPlaybackSource(backend: backend)
        let manager = CaptureManager(sources: [source], runsAnalysisTimer: false)
        let transport = PlaybackTransport(manager: manager, source: source)
        transport.prepare(order: ListPlayOrder([item]), current: item)
        await manager.select(.inAppPlayback)
        XCTAssertTrue(manager.state.isRunning)
        let context = AudioRouteContext.make(mode: manager.activeMode, state: manager.state, isPausedByUser: manager.isPausedByUser)

        provider.currentRoute = AudioRoute(inputs: [], outputs: [speaker])
        center.post(name: AVAudioSession.routeChangeNotification, object: session,
                    userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        for _ in 0..<50 { await Task.yield() }
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(manager.state, .paused, "AUD-014-R14 unchanged")
        XCTAssertEqual(manager.stopReason, .audioRouteChanged)
        let change = try XCTUnwrap(monitor.lastChange)
        XCTAssertEqual(change.summary(.output), .lost(wired))
        XCTAssertEqual(context, .playback(heldByUser: false))
        XCTAssertTrue(change.pausesPlayback(in: try XCTUnwrap(context)))
        await manager.stop()
    }
}
#endif
