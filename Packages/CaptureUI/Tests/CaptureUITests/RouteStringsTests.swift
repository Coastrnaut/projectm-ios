// RouteStringsTests.swift — the route indicator's texts (AUD-007-T09; AUD-007-R4-R11; S2, S3;
// specs/026-aud-007-audio-output-route-indicator/contracts/ui-strings.md). Pure strings run on the
// host and Linux; the view smoke render is inside the SwiftUI guard.
import AudioCore
import CaptureKit
import Foundation
import XCTest
@testable import CaptureUI

final class RouteStringsTests: XCTestCase {
    private let speaker = RoutePort(kind: .builtInSpeaker, name: "Speaker")
    private let wired = RoutePort(kind: .wiredHeadphones, name: "Headphones")
    private let airPods = RoutePort(kind: .bluetoothA2DP, name: "AirPods Pro")
    private let playing = AudioRouteContext.playback(heldByUser: false)
    private let held = AudioRouteContext.playback(heldByUser: true)

    private func outputs(_ ports: RoutePort...) -> AudioRoute { AudioRoute(inputs: [], outputs: ports) }
    private func change(_ reason: AudioRouteChangeReason, _ from: AudioRoute, _ to: AudioRoute) -> AudioRouteChange {
        AudioRouteChange(sequence: 1, reason: reason, previous: from, current: to)
    }

    // MARK: Indicator

    func testIndicatorTextAndVoiceOverLabel() {
        XCTAssertEqual(UIStrings.routeIndicator(outputs(speaker), context: playing), "Output: Speaker")
        XCTAssertEqual(UIStrings.routeAccessibilityLabel(outputs(speaker), context: playing), "Audio output: Speaker")
        XCTAssertEqual(UIStrings.routeIndicator(outputs(airPods), context: held), "Output: AirPods Pro")
        XCTAssertEqual(UIStrings.routeIndicator(outputs(RoutePort(kind: .hdmi, name: "TV"), speaker), context: playing), "Output: TV, Speaker")
        XCTAssertEqual(UIStrings.routeIndicator(outputs(), context: playing), "Output: None")
        XCTAssertEqual(UIStrings.routeAccessibilityLabel(outputs(), context: playing), "Audio output: None")
        let mic = AudioRoute(inputs: [RoutePort(kind: .builtInMic, name: "iPhone Microphone")], outputs: [])
        XCTAssertEqual(UIStrings.routeIndicator(mic, context: .microphone), "Input: iPhone Microphone")
        XCTAssertEqual(UIStrings.routeAccessibilityLabel(mic, context: .microphone), "Audio input: iPhone Microphone")
        XCTAssertEqual(UIStrings.routeIndicator(.empty, context: .microphone), "Input: None")
    }

    func testEmptyNamesUseTheGenericNameAndNothingIsInvented() {
        XCTAssertEqual(UIStrings.routeIndicator(outputs(RoutePort(kind: .bluetoothLE, name: "")), context: playing), "Output: Bluetooth device")
        XCTAssertEqual(UIStrings.routeIndicator(outputs(RoutePort(kind: .airPlay, name: "  ")), context: playing), "Output: AirPlay device")
        XCTAssertEqual(UIStrings.routePortName(RoutePort(kind: .other, name: "")), "Audio device")
        XCTAssertEqual(UIStrings.routePortName(RoutePort(kind: .wiredHeadphones, name: "Kitchen")), "Kitchen", "iOS's name verbatim")
    }

    func testSymbolsFollowTheFirstPort() {
        XCTAssertEqual(UIStrings.routeSymbol(outputs(speaker), context: playing), "speaker.wave.2")
        XCTAssertEqual(UIStrings.routeSymbol(outputs(wired), context: playing), "headphones")
        XCTAssertEqual(UIStrings.routeSymbol(outputs(airPods), context: playing), "wave.3.right")
        XCTAssertEqual(UIStrings.routeSymbol(outputs(), context: playing), "speaker.slash")
        XCTAssertEqual(UIStrings.routeSymbol(.empty, context: .microphone), "mic.slash")
    }

    // MARK: Explanations and announcements (contracts/ui-strings.md, AUD-007-R7, R8, R10)

    func testEveryExplanationRow() {
        let plugIn = change(.newDeviceAvailable, outputs(speaker), outputs(wired))
        XCTAssertEqual(UIStrings.routeExplanation(plugIn, context: playing), "Now playing through Headphones")
        XCTAssertEqual(UIStrings.routeAnnouncement(plugIn, context: playing), "Now playing through Headphones")
        XCTAssertEqual(UIStrings.routeExplanation(plugIn, context: held), "Audio output is now Headphones")

        let unplug = change(.oldDeviceUnavailable, outputs(wired), outputs(speaker))
        XCTAssertEqual(UIStrings.routeExplanation(unplug, context: playing), "Headphones disconnected — paused")
        XCTAssertNil(UIStrings.routeAnnouncement(unplug, context: playing), "AUD-014-R18 announces the pause")
        XCTAssertEqual(UIStrings.routeExplanation(unplug, context: held), "Headphones disconnected")
        XCTAssertEqual(UIStrings.routeAnnouncement(unplug, context: held), "Headphones disconnected")

        let bluetoothOut = change(.oldDeviceUnavailable, outputs(airPods), outputs(speaker))
        XCTAssertEqual(UIStrings.routeExplanation(bluetoothOut, context: playing), "AirPods Pro disconnected — paused")

        let none = change(.noSuitableRouteForCategory, outputs(speaker), outputs())
        XCTAssertEqual(UIStrings.routeExplanation(none, context: playing), "No audio output available")

        let builtIn = RoutePort(kind: .builtInMic, name: "iPhone Microphone")
        let headset = RoutePort(kind: .headsetMic, name: "Headset Microphone")
        let micIn = change(.newDeviceAvailable, AudioRoute(inputs: [builtIn], outputs: []), AudioRoute(inputs: [headset], outputs: []))
        XCTAssertEqual(UIStrings.routeExplanation(micIn, context: .microphone), "Now listening through Headset Microphone")
        let micOut = change(.oldDeviceUnavailable, AudioRoute(inputs: [headset], outputs: []), AudioRoute(inputs: [builtIn], outputs: []))
        XCTAssertEqual(UIStrings.routeExplanation(micOut, context: .microphone), "Headset Microphone disconnected")
        XCTAssertEqual(UIStrings.routeAnnouncement(micOut, context: .microphone), "Headset Microphone disconnected")
        let micNone = change(.oldDeviceUnavailable, AudioRoute(inputs: [builtIn], outputs: []), .empty)
        XCTAssertEqual(UIStrings.routeExplanation(micNone, context: .microphone), "iPhone Microphone disconnected")
        let micGone = change(.noSuitableRouteForCategory, AudioRoute(inputs: [builtIn], outputs: []), .empty)
        XCTAssertEqual(UIStrings.routeExplanation(micGone, context: .microphone), "No audio input available")

        let category = change(.categoryChange, outputs(), outputs(speaker))
        XCTAssertNil(UIStrings.routeExplanation(category, context: playing))
        XCTAssertNil(UIStrings.routeAnnouncement(category, context: playing))
    }

    // MARK: Wording rule (AUD-007-R11, S3)

    func testNoRouteWordingNamesASourceModeACaptureOrAnApp() {
        let marker = "\u{2063}NAME\u{2063}"
        var texts: [String] = []
        let kinds = RoutePortKind.allCases
        for kind in kinds { texts.append(UIStrings.routePortName(RoutePort(kind: kind, name: ""))) }
        let named = RoutePort(kind: .wiredHeadphones, name: marker)
        let other = RoutePort(kind: .builtInSpeaker, name: marker)
        let mic = RoutePort(kind: .headsetMic, name: marker)
        let micOther = RoutePort(kind: .builtInMic, name: marker)
        let contexts: [AudioRouteContext] = [.playback(heldByUser: false), .playback(heldByUser: true), .microphone]
        for context in contexts {
            let (a, b) = context == .microphone ? (micOther, mic) : (other, named)
            let route = { (ports: [RoutePort]) in context == .microphone ? AudioRoute(inputs: ports, outputs: []) : AudioRoute(inputs: [], outputs: ports) }
            texts.append(UIStrings.routeIndicator(route([b]), context: context))
            texts.append(UIStrings.routeAccessibilityLabel(route([b]), context: context))
            texts.append(UIStrings.routeIndicator(route([]), context: context))
            for reason in AudioRouteChangeReason.allCases {
                for (from, to) in [([a], [b]), ([b], [a]), ([b], [])] {
                    let c = AudioRouteChange(sequence: 1, reason: reason, previous: route(from), current: route(to))
                    if let text = UIStrings.routeExplanation(c, context: context) { texts.append(text) }
                    if let text = UIStrings.routeAnnouncement(c, context: context) { texts.append(text) }
                }
            }
        }
        XCTAssertGreaterThan(texts.count, 50)
        let forbidden = AudioSourceMode.allCases.map(UIStrings.label) + ["captur", "Spotify", "Apple Music", "YouTube"]
        for text in texts {
            let own = text.replacingOccurrences(of: marker, with: "")
            for word in forbidden {
                XCTAssertFalse(own.localizedCaseInsensitiveContains(word), "\"\(own)\" contains \"\(word)\"")
            }
        }
        // Outputs are never described as where audio comes from.
        for context in [playing, held] {
            for reason in AudioRouteChangeReason.allCases {
                let c = change(reason, outputs(speaker), outputs(named))
                for text in [UIStrings.routeExplanation(c, context: context), UIStrings.routeAnnouncement(c, context: context)].compactMap({ $0 }) {
                    for word in ["from", "receiving", "listening"] {
                        XCTAssertFalse(text.replacingOccurrences(of: marker, with: "").localizedCaseInsensitiveContains(word), text)
                    }
                }
            }
        }
    }
}

#if canImport(SwiftUI)
import SwiftUI

@MainActor
final class AudioRouteIndicatorRenderTests: XCTestCase {
    func testTheIndicatorRendersForOutputsInputsAndNone() {
        let routes: [(AudioRoute, AudioRouteContext)] = [
            (AudioRoute(inputs: [], outputs: [RoutePort(kind: .bluetoothA2DP, name: "AirPods Pro")]), .playback(heldByUser: false)),
            (AudioRoute(inputs: [RoutePort(kind: .builtInMic, name: "iPhone Microphone")], outputs: []), .microphone),
            (.empty, .playback(heldByUser: true)),
        ]
        for (route, context) in routes {
            let renderer = ImageRenderer(content: AudioRouteIndicator(route: route, context: context).frame(width: 390))
            renderer.scale = 1
            XCTAssertNotNil(renderer.cgImage, "\(context)")
        }
    }
}
#endif
