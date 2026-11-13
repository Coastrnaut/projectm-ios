// RouteCoordinatorTests.swift — the route indicator's explanations and announcements in the app
// (AUD-007-T11; AUD-007-R3, R7, R8, R10; spec edge cases "rapid changes" and "background"). A fake
// provider and a recorded announcer; no session observer, no clock (the 4 s expiry is not asserted).
import CaptureKit
import CaptureUI
import XCTest
@testable import projectM_iOS

@MainActor
private final class FakeRoutes: AudioRouteProviding {
    var currentRoute: AudioRoute
    init(_ route: AudioRoute) { currentRoute = route }
}

@MainActor
final class RouteCoordinatorTests: XCTestCase {
    private let speaker = RoutePort(kind: .builtInSpeaker, name: "Speaker")
    private let wired = RoutePort(kind: .wiredHeadphones, name: "Headphones")

    private func make(context: AudioRouteContext? = .playback(heldByUser: false), active: Bool = true)
        -> (RouteCoordinator, FakeRoutes, () -> [String]) {
        let provider = FakeRoutes(AudioRoute(inputs: [], outputs: [speaker]))
        var spoken: [String] = []
        let routes = RouteCoordinator(provider: provider, observesSession: false) { spoken.append($0) }
        routes.context = { context }
        routes.isActive = { active }
        return (routes, provider, { spoken })
    }

    private func set(_ provider: FakeRoutes, _ port: RoutePort) {
        provider.currentRoute = AudioRoute(inputs: [], outputs: [port])
    }

    func testPlugInExplainsAndAnnounces() {
        let (routes, provider, spoken) = make()
        set(provider, wired)
        routes.monitor.routeDidChange(reason: .newDeviceAvailable)
        XCTAssertEqual(routes.route.outputs, [wired])
        XCTAssertEqual(routes.explanation, "Now playing through Headphones")
        XCTAssertEqual(spoken(), ["Now playing through Headphones"])
    }

    func testUnplugWhilePlayingShowsPausedAndLeavesTheAnnouncementToAUD014() {
        let (routes, provider, spoken) = make()
        set(provider, wired)
        routes.refresh()
        set(provider, speaker)
        routes.monitor.routeDidChange(reason: .oldDeviceUnavailable)
        XCTAssertEqual(routes.explanation, "Headphones disconnected — paused")
        XCTAssertEqual(spoken(), [], "AUD-014-R18 announces the pause")
    }

    func testNoContextCategoryChangeBackgroundAndRefreshExplainNothing() {
        for (context, active, reason) in [(nil, true, AudioRouteChangeReason.newDeviceAvailable),
                                          (.playback(heldByUser: false), true, .categoryChange),
                                          (.playback(heldByUser: false), false, .newDeviceAvailable)] as [(AudioRouteContext?, Bool, AudioRouteChangeReason)] {
            let (routes, provider, spoken) = make(context: context, active: active)
            set(provider, wired)
            routes.monitor.routeDidChange(reason: reason)
            XCTAssertEqual(routes.route.outputs, [wired], "the route is still tracked")
            XCTAssertNil(routes.explanation, "\(String(describing: context)) \(active) \(reason)")
            XCTAssertEqual(spoken(), [])
        }
        let (routes, provider, spoken) = make()
        set(provider, wired)
        routes.refresh()
        XCTAssertEqual(routes.route.outputs, [wired])
        XCTAssertNil(routes.explanation, "a source start is not a change")
        XCTAssertEqual(spoken(), [])
    }

    func testTheNewestChangeReplacesTheExplanation() {
        let (routes, provider, spoken) = make()
        set(provider, wired)
        routes.monitor.routeDidChange(reason: .newDeviceAvailable)
        set(provider, RoutePort(kind: .airPlay, name: "Living Room"))
        routes.monitor.routeDidChange(reason: .override)
        XCTAssertEqual(routes.explanation, "Now playing through Living Room")
        XCTAssertEqual(spoken(), ["Now playing through Headphones", "Now playing through Living Room"])
    }

    func testMicrophoneModeExplainsTheInput() {
        let builtIn = RoutePort(kind: .builtInMic, name: "iPhone Microphone")
        let headset = RoutePort(kind: .headsetMic, name: "Headset Microphone")
        let provider = FakeRoutes(AudioRoute(inputs: [builtIn], outputs: []))
        var spoken: [String] = []
        let routes = RouteCoordinator(provider: provider, observesSession: false) { spoken.append($0) }
        routes.context = { .microphone }
        provider.currentRoute = AudioRoute(inputs: [headset], outputs: [])
        routes.monitor.routeDidChange(reason: .newDeviceAvailable)
        XCTAssertEqual(routes.explanation, "Now listening through Headset Microphone")
        XCTAssertEqual(UIStrings.routeIndicator(routes.route, context: .microphone), "Input: Headset Microphone")
        XCTAssertEqual(spoken, ["Now listening through Headset Microphone"])
    }
}
