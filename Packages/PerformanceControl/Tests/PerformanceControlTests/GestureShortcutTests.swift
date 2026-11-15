// GestureShortcutTests.swift — UIX-006-T03 (specs/290-uix-006-touch-gesture-mapping; S1, S2; contract G1, G2).
// Pure: the precedence table for every overlapping pair, None handing over, the master switch and VoiceOver,
// the classifier's thresholds, the catalogue and the stored form.
import XCTest
@testable import PerformanceControl

final class GestureShortcutTests: XCTestCase {
    private typealias G = PerformanceGesture

    /// Every gesture mapped to a distinct action, switch on.
    private func allMapped() -> GestureShortcutConfiguration {
        var configuration = GestureShortcutConfiguration(isEnabled: true)
        let actions: [GestureAction] = [.toggleHUD, .nextCue, .previousCue, .nextPreset, .previousPreset, .tapTempo]
        for (gesture, action) in zip(G.allCases, actions) { configuration.set(action, for: gesture) }
        return configuration
    }

    private func winner(_ set: Set<G>, _ configuration: GestureShortcutConfiguration, voiceOver: Bool = false) -> G? {
        GestureShortcutResolver.resolve(set, configuration: configuration, voiceOverRunning: voiceOver)?.gesture
    }

    func testDocumentedPrecedenceOrder() {
        XCTAssertEqual(G.allCases, [.threeFingerTap, .twoFingerSwipeLeft, .twoFingerSwipeRight, .twoFingerSwipeUp,
                                    .twoFingerSwipeDown, .twoFingerTap])
        XCTAssertEqual(G.allCases.map(\.rank), Array(0..<6))
    }

    /// S1: every overlapping pair resolves to the higher-ranked gesture, both mapped; with the winner set to None the
    /// other wins; with both None nothing does.
    func testEveryPairResolvesDeterministically() {
        for a in G.allCases {
            for b in G.allCases where a.rank < b.rank {
                var configuration = allMapped()
                XCTAssertEqual(winner([a, b], configuration), a, "\(a) beats \(b)")
                XCTAssertEqual(winner([b, a], configuration), a, "order of the set does not matter")
                XCTAssertEqual(GestureShortcutResolver.resolve([a, b], configuration: configuration, voiceOverRunning: false)?.action,
                               configuration.action(for: a))
                configuration.set(.none, for: a)
                XCTAssertEqual(winner([a, b], configuration), b, "\(a) None: \(b) wins")
                configuration.set(.none, for: b)
                XCTAssertNil(winner([a, b], configuration), "both None: nothing")
            }
        }
    }

    func testThreeFingerTapBeatsTwoFingerTapAndFallsBack() {
        var configuration = GestureShortcutConfiguration(isEnabled: true)
        configuration.set(.tapTempo, for: .twoFingerTap)
        configuration.set(.toggleHUD, for: .threeFingerTap)
        let touch = GestureClassifier.recognise(GestureTouchSummary(maxTouches: 3, maxDisplacement: 4, duration: 0.2))
        XCTAssertEqual(touch, [.threeFingerTap, .twoFingerTap])
        XCTAssertEqual(GestureShortcutResolver.resolve(touch, configuration: configuration, voiceOverRunning: false)?.action, .toggleHUD)
        configuration.set(.none, for: .threeFingerTap)
        XCTAssertEqual(GestureShortcutResolver.resolve(touch, configuration: configuration, voiceOverRunning: false)?.action, .tapTempo)
    }

    /// S2: master off or VoiceOver running: nothing fires, and the app attaches no recogniser.
    func testMasterOffAndVoiceOverFireNothing() {
        var configuration = allMapped()
        let everything = Set(G.allCases)
        XCTAssertNotNil(winner(everything, configuration))
        XCTAssertNil(winner(everything, configuration, voiceOver: true))
        XCTAssertFalse(GestureShortcutResolver.isActive(configuration, voiceOverRunning: true))
        configuration.isEnabled = false
        XCTAssertNil(winner(everything, configuration))
        XCTAssertFalse(GestureShortcutResolver.isActive(configuration, voiceOverRunning: false))
        XCTAssertFalse(GestureShortcutConfiguration().isEnabled, "off by default")
        var allNone = GestureShortcutConfiguration(isEnabled: true)
        for gesture in G.allCases { allNone.set(.none, for: gesture) }
        XCTAssertNil(winner(everything, allNone))
        XCTAssertFalse(GestureShortcutResolver.isActive(allNone, voiceOverRunning: false))
    }

    func testClassifierThresholds() {
        func recognise(_ n: Int, _ dx: Double, _ dy: Double, _ t: TimeInterval) -> Set<G> {
            GestureClassifier.recognise(GestureTouchSummary(maxTouches: n, dx: dx, dy: dy, maxDisplacement: (dx * dx + dy * dy).squareRoot(), duration: t))
        }
        XCTAssertEqual(recognise(1, 0, 0, 0.1), [], "one finger stays with the controls tap")
        XCTAssertEqual(recognise(4, 0, 0, 0.1), [], "four fingers: system")
        XCTAssertEqual(recognise(2, 5, 5, 0.2), [.twoFingerTap])
        XCTAssertEqual(recognise(2, 0, 0, 0.6), [], "held too long for a tap")
        XCTAssertEqual(recognise(2, -80, 10, 0.3), [.twoFingerSwipeLeft])
        XCTAssertEqual(recognise(2, 80, -10, 0.3), [.twoFingerSwipeRight])
        XCTAssertEqual(recognise(2, 5, -70, 0.3), [.twoFingerSwipeUp])
        XCTAssertEqual(recognise(2, 5, 70, 0.3), [.twoFingerSwipeDown])
        XCTAssertEqual(recognise(2, 35, 0, 0.3), [], "the dead band between tap slop and swipe distance")
        XCTAssertEqual(recognise(2, 80, 0, 1.2), [], "too slow for a swipe")
        XCTAssertEqual(recognise(3, 80, 0, 0.3), [], "three-finger swipes belong to the system")
    }

    func testSwipeBeatsTapWhenBothAreReported() {
        let configuration = allMapped()
        XCTAssertEqual(winner([.twoFingerTap, .twoFingerSwipeUp], configuration), .twoFingerSwipeUp)
    }

    func testCatalogueIsSafe() {
        let names: [String] = GestureAction.allCases.map(\.rawValue)
        for forbidden in ["blackout", "restore", "delete", "save", "erase", "record"] {
            XCTAssertFalse(names.contains { (name: String) -> Bool in name.lowercased().contains(forbidden) }, forbidden)
        }
        XCTAssertEqual(GestureAction.allCases.count, 7)
    }

    func testStoredFormRoundTripsAndIgnoresUnknownNames() {
        var configuration = GestureShortcutConfiguration(isEnabled: true)
        configuration.set(.nextPreset, for: .twoFingerTap)
        XCTAssertEqual(GestureShortcutConfiguration(json: configuration.json), configuration.normalised)
        XCTAssertEqual(GestureShortcutConfiguration(json: nil), GestureShortcutConfiguration())
        XCTAssertEqual(GestureShortcutConfiguration(json: "{oops"), GestureShortcutConfiguration())
        let odd = GestureShortcutConfiguration(json: #"{"enabled":true,"mapping":{"fourFingerPinch":"nextCue","twoFingerTap":"blackout","threeFingerTap":"tapTempo"}}"#)
        XCTAssertTrue(odd.isEnabled)
        XCTAssertEqual(odd.action(for: .twoFingerTap), .none, "unknown action: the default")
        XCTAssertEqual(odd.action(for: .threeFingerTap), .tapTempo)
        XCTAssertEqual(odd.action(for: .twoFingerSwipeLeft), .nextCue, "missing: the default")
    }
}

private extension GestureShortcutConfiguration {
    /// Every gesture written out explicitly (what a decoded configuration holds).
    var normalised: GestureShortcutConfiguration {
        var copy = GestureShortcutConfiguration(isEnabled: isEnabled)
        for gesture in PerformanceGesture.allCases { copy.set(action(for: gesture), for: gesture) }
        return copy
    }
}
