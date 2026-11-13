// AudioRouteTests.swift — the route model of AUD-007 (AUD-007-T02; AUD-007-R1, R7-R9; S1, S2;
// specs/026-aud-007-audio-output-route-indicator/contracts/route-model.md). Foundation only, so it
// runs on the macOS host and on Linux; the SDK constants are checked in SystemAudioRouteTests.
import AudioCore
import XCTest
@testable import CaptureKit

final class AudioRouteTests: XCTestCase {
    private let speaker = RoutePort(kind: .builtInSpeaker, name: "Speaker")
    private let wired = RoutePort(kind: .wiredHeadphones, name: "Headphones")
    private let airPods = RoutePort(kind: .bluetoothA2DP, name: "AirPods Pro")
    private let appleTV = RoutePort(kind: .airPlay, name: "Living Room")

    private func outputs(_ ports: RoutePort...) -> AudioRoute { AudioRoute(inputs: [], outputs: ports) }

    private func change(_ reason: AudioRouteChangeReason, _ from: AudioRoute, _ to: AudioRoute) -> AudioRouteChange {
        AudioRouteChange(sequence: 1, reason: reason, previous: from, current: to)
    }

    // MARK: Port types (contracts/route-model.md)

    func testEveryListedPortTypeMapsToItsKind() {
        let outputTable: [String: RoutePortKind] = [
            "Speaker": .builtInSpeaker, "Receiver": .builtInReceiver, "Headphones": .wiredHeadphones,
            "BluetoothA2DPOutput": .bluetoothA2DP, "BluetoothLE": .bluetoothLE, "BluetoothHFP": .bluetoothHFP,
            "AirPlay": .airPlay, "HDMIOutput": .hdmi, "USBAudio": .usbAudio, "CarAudio": .carAudio, "LineOut": .lineOut,
        ]
        for (raw, kind) in outputTable {
            XCTAssertEqual(RoutePortKind(portType: raw, direction: .output), kind, raw)
        }
        let inputTable: [String: RoutePortKind] = [
            "MicrophoneBuiltIn": .builtInMic, "MicrophoneWired": .headsetMic, "LineIn": .lineIn,
            "BluetoothHFP": .bluetoothHFP, "USBAudio": .usbAudio, "CarAudio": .carAudio,
        ]
        for (raw, kind) in inputTable {
            XCTAssertEqual(RoutePortKind(portType: raw, direction: .input), kind, raw)
        }
    }

    func testUnknownPortTypesMapToOther() {
        for raw in ["Thunderbolt", "Virtual", "DisplayPort", "", "SomethingNew"] {
            XCTAssertEqual(RoutePortKind(portType: raw, direction: .output), .other, raw)
            XCTAssertEqual(RoutePortKind(portType: raw, direction: .input), .otherInput, raw)
        }
        // An input-only type reported as an output, and the reverse, is still "other".
        XCTAssertEqual(RoutePortKind(portType: "MicrophoneBuiltIn", direction: .output), .other)
        XCTAssertEqual(RoutePortKind(portType: "Speaker", direction: .input), .otherInput)
    }

    // MARK: Reasons and the shared pause rule (AUD-007-R9)

    func testReasonRawValuesMatchTheSDKAndUnknownValuesAreUnknown() {
        let expected: [UInt: AudioRouteChangeReason] = [0: .unknown, 1: .newDeviceAvailable, 2: .oldDeviceUnavailable,
                                                        3: .categoryChange, 4: .override, 6: .wakeFromSleep,
                                                        7: .noSuitableRouteForCategory, 8: .routeConfigurationChange]
        for (raw, reason) in expected { XCTAssertEqual(AudioRouteChangeReason(rawReason: raw), reason, "\(raw)") }
        XCTAssertEqual(AudioRouteChangeReason(rawReason: 5), .unknown)
        XCTAssertEqual(AudioRouteChangeReason(rawReason: 99), .unknown)
    }

    func testOnlyAnOldDeviceBecomingUnavailablePausesPlayback() {
        for reason in AudioRouteChangeReason.allCases {
            XCTAssertEqual(reason.pausesInAppPlayback, reason == .oldDeviceUnavailable, "\(reason)")
        }
    }

    // MARK: Change summaries (AUD-007-R7, R8)

    func testWiredHeadphonesInAndOut() {
        let plugIn = change(.newDeviceAvailable, outputs(speaker), outputs(wired))
        XCTAssertEqual(plugIn.summary(.output), .switched(to: wired))
        let unplug = change(.oldDeviceUnavailable, outputs(wired), outputs(speaker))
        XCTAssertEqual(unplug.summary(.output), .lost(wired))
        XCTAssertTrue(unplug.pausesPlayback(in: .playback(heldByUser: false)))
        XCTAssertFalse(unplug.pausesPlayback(in: .playback(heldByUser: true)), "the user already holds it")
        XCTAssertFalse(unplug.pausesPlayback(in: .microphone))
        XCTAssertFalse(plugIn.pausesPlayback(in: .playback(heldByUser: false)))
    }

    func testBluetoothInAndOutAndAirPlay() {
        XCTAssertEqual(change(.newDeviceAvailable, outputs(speaker), outputs(airPods)).summary(.output), .switched(to: airPods))
        XCTAssertEqual(change(.oldDeviceUnavailable, outputs(airPods), outputs(speaker)).summary(.output), .lost(airPods))
        // Picking an AirPlay receiver in Control Center arrives as an override or a configuration change.
        XCTAssertEqual(change(.override, outputs(speaker), outputs(appleTV)).summary(.output), .switched(to: appleTV))
        XCTAssertEqual(change(.routeConfigurationChange, outputs(appleTV), outputs(speaker)).summary(.output),
                       .switched(to: speaker), "a port gone for a reason that does not pause is a switch")
    }

    func testNothingToExplain() {
        XCTAssertNil(change(.categoryChange, outputs(), outputs(speaker)).summary(.output), "the app's own session setup")
        XCTAssertNil(change(.categoryChange, outputs(speaker), outputs(wired)).summary(.output))
        XCTAssertNil(change(.routeConfigurationChange, outputs(wired), outputs(wired)).summary(.output), "unchanged")
        XCTAssertNil(change(.newDeviceAvailable, outputs(wired), outputs(wired)).summary(.input), "no inputs either side")
    }

    func testNoPortsLeft() {
        XCTAssertEqual(change(.noSuitableRouteForCategory, outputs(speaker), outputs()).summary(.output), .noneLeft)
        // A lost port wins over "none left": the user unplugged something.
        XCTAssertEqual(change(.oldDeviceUnavailable, outputs(wired), outputs()).summary(.output), .lost(wired))
    }

    func testTheAddedPortIsNamedEvenWhenItIsNotFirst() {
        let hdmi = RoutePort(kind: .hdmi, name: "TV")
        XCTAssertEqual(change(.newDeviceAvailable, outputs(speaker), outputs(speaker, hdmi)).summary(.output), .switched(to: hdmi))
    }

    func testMicrophoneInputChanges() {
        let builtIn = RoutePort(kind: .builtInMic, name: "iPhone Microphone")
        let headset = RoutePort(kind: .headsetMic, name: "Headset Microphone")
        let plugIn = AudioRouteChange(sequence: 1, reason: .newDeviceAvailable,
                                      previous: AudioRoute(inputs: [builtIn], outputs: []),
                                      current: AudioRoute(inputs: [headset], outputs: []))
        XCTAssertEqual(plugIn.summary(.input), .switched(to: headset))
        XCTAssertNil(plugIn.summary(.output), "the record-only session has no outputs")
    }

    // MARK: Context (contracts/route-model.md)

    func testContextFollowsTheActiveModeAndState() {
        let running: [AudioState] = [.waiting, .noAudioReceived, .silent, .active, .paused, .interrupted]
        for state in running {
            XCTAssertEqual(AudioRouteContext.make(mode: .inAppPlayback, state: state, isPausedByUser: false), .playback(heldByUser: false))
            XCTAssertEqual(AudioRouteContext.make(mode: .inAppPlayback, state: state, isPausedByUser: true), .playback(heldByUser: true))
            XCTAssertEqual(AudioRouteContext.make(mode: .microphone, state: state, isPausedByUser: false), .microphone)
            XCTAssertNil(AudioRouteContext.make(mode: .systemAppCapture, state: state, isPausedByUser: false))
            XCTAssertNil(AudioRouteContext.make(mode: nil, state: state, isPausedByUser: false))
        }
        for state in [AudioState.notStarted, .stopped, .endedBySystem] {
            XCTAssertNil(AudioRouteContext.make(mode: .inAppPlayback, state: state, isPausedByUser: false))
            XCTAssertNil(AudioRouteContext.make(mode: .microphone, state: state, isPausedByUser: false))
        }
        XCTAssertEqual(AudioRouteContext.playback(heldByUser: false).direction, .output)
        XCTAssertEqual(AudioRouteContext.microphone.direction, .input)
    }
}
