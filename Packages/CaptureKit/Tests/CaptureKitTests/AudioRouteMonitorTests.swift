// AudioRouteMonitorTests.swift — the route monitor with an injected provider (AUD-007-T03;
// AUD-007-R2, R3; S2). Foundation only (host and Linux); no audio session, no clock.
import XCTest
@testable import CaptureKit

@MainActor
private final class FakeRouteProvider: AudioRouteProviding {
    var currentRoute: AudioRoute
    init(_ route: AudioRoute) { currentRoute = route }
}

@MainActor
final class AudioRouteMonitorTests: XCTestCase {
    private let speaker = RoutePort(kind: .builtInSpeaker, name: "Speaker")
    private let wired = RoutePort(kind: .wiredHeadphones, name: "Headphones")
    private let airPods = RoutePort(kind: .bluetoothA2DP, name: "AirPods Pro")

    private func outputs(_ ports: RoutePort...) -> AudioRoute { AudioRoute(inputs: [], outputs: ports) }

    func testRefreshReadsTheRouteWithoutAChange() {
        let provider = FakeRouteProvider(outputs(speaker))
        let monitor = AudioRouteMonitor(provider: provider)
        var changes = 0
        monitor.onChange = { _ in changes += 1 }
        XCTAssertEqual(monitor.route, outputs(speaker), "read at creation")
        provider.currentRoute = outputs(wired)
        monitor.refresh()
        XCTAssertEqual(monitor.route, outputs(wired))
        XCTAssertNil(monitor.lastChange)
        XCTAssertEqual(changes, 0)
    }

    func testEachChangeIsRecordedOnceWithItsBeforeAndAfter() {
        let provider = FakeRouteProvider(outputs(speaker))
        let monitor = AudioRouteMonitor(provider: provider)
        var seen: [AudioRouteChange] = []
        monitor.onChange = { seen.append($0) }

        let script: [(AudioRoute, AudioRouteChangeReason, RouteChangeSummary?)] = [
            (outputs(wired), .newDeviceAvailable, .switched(to: wired)),
            (outputs(speaker), .oldDeviceUnavailable, .lost(wired)),
            (outputs(airPods), .newDeviceAvailable, .switched(to: airPods)),
            (outputs(speaker), .oldDeviceUnavailable, .lost(airPods)),
            (outputs(speaker), .categoryChange, nil),
        ]
        var previous = outputs(speaker)
        for (index, step) in script.enumerated() {
            provider.currentRoute = step.0
            let change = monitor.routeDidChange(reason: step.1)
            XCTAssertEqual(change.sequence, index + 1)
            XCTAssertEqual(change.previous, previous)
            XCTAssertEqual(change.current, step.0)
            XCTAssertEqual(change.summary(.output), step.2, "step \(index)")
            XCTAssertEqual(monitor.route, step.0)
            XCTAssertEqual(monitor.lastChange, change)
            previous = step.0
        }
        XCTAssertEqual(seen.count, script.count, "onChange once per change")
    }
}
