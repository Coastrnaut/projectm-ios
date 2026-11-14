// HotPlugSettleTests.swift — OUT-002-T02: the settle and hold rules (spec
// specs/161-out-002-display-hotplug, data-model.md). Pure Swift; host and Linux.
import XCTest
@testable import PresentationLifecycle

final class HotPlugSettleTests: XCTestCase {
    private let hd = ExternalDisplayGeometry(width: 1920, height: 1080, scale: 1)
    private let small = ExternalDisplayGeometry(width: 1280, height: 720, scale: 1)

    func testAConnectSettlesWithItsToken() {
        var settle = HotPlugSettle(interval: HotPlugSettle.defaultInterval)
        XCTAssertFalse(settle.isImmediate)
        let token = settle.connect(id: "a", geometry: hd, foreground: true)
        XCTAssertTrue(settle.isPending("a"))
        XCTAssertEqual(settle.settle(token: token), PendingConnection(id: "a", geometry: hd, foreground: true, token: token))
        XCTAssertFalse(settle.isPending("a"))
        XCTAssertNil(settle.settle(token: token), "a timer fires once")
    }

    func testADisconnectBeforeSettleCancelsAndTheTimerIsStale() {
        var settle = HotPlugSettle(interval: 0.3)
        let token = settle.connect(id: "a", geometry: hd, foreground: true)
        XCTAssertTrue(settle.cancel(id: "a"))
        XCTAssertEqual(settle.cancelled, 1)
        XCTAssertNil(settle.settle(token: token), "the stale timer settles nothing")
        XCTAssertFalse(settle.cancel(id: "a"), "a settled or unknown display is not cancelled")
        XCTAssertEqual(settle.cancelled, 1)
    }

    func testARepeatConnectReplacesTheEntryAndItsToken() {
        var settle = HotPlugSettle(interval: 0.3)
        let first = settle.connect(id: "a", geometry: hd, foreground: true)
        let second = settle.connect(id: "a", geometry: small, foreground: false)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(settle.pending.count, 1)
        XCTAssertNil(settle.settle(token: first))
        XCTAssertEqual(settle.settle(token: second)?.geometry, small)
    }

    func testUpdatesChangeOnlyAPendingEntry() {
        var settle = HotPlugSettle(interval: 0.3)
        let token = settle.connect(id: "a", geometry: ExternalDisplayGeometry(width: 0, height: 0, scale: 1), foreground: false)
        XCTAssertTrue(settle.update(id: "a", geometry: hd))
        XCTAssertTrue(settle.update(id: "a", foreground: true))
        XCTAssertFalse(settle.update(id: "b", geometry: hd))
        XCTAssertFalse(settle.update(id: "b", foreground: true))
        let settled = settle.settle(token: token)
        XCTAssertEqual(settled?.geometry, hd)
        XCTAssertEqual(settled?.foreground, true)
    }

    func testZeroIntervalIsImmediate() {
        XCTAssertTrue(HotPlugSettle().isImmediate)
        XCTAssertTrue(HotPlugSettle(interval: 0).isImmediate)
    }

    // MARK: - Placement hold (OUT-002-R4)

    private func routing(visualizing: Bool, displays: [String]) -> ExternalDisplayRouting {
        var routing = ExternalDisplayRouting()
        for id in displays { routing.apply(.connected(id: id, geometry: hd, foreground: true)) }
        routing.apply(.visualizing(visualizing))
        return routing
    }

    func testTheHeldTargetWinsWhileItExists() {
        let r = routing(visualizing: true, displays: ["a"])
        XCTAssertEqual(r.target, .external(id: "a"))
        XCTAssertEqual(r.effectiveTarget(held: nil), .external(id: "a"), "no hold: OUT-001 routing")
        XCTAssertEqual(r.effectiveTarget(held: .device), .device, "a recording on the device keeps it there")
        XCTAssertEqual(r.effectiveTarget(held: .external(id: "a")), .external(id: "a"))
    }

    func testAHeldDisplayThatIsGoneFallsBackToRouting() {
        let r = routing(visualizing: true, displays: ["b"])
        XCTAssertEqual(r.effectiveTarget(held: .external(id: "a")), .external(id: "b"))
        XCTAssertEqual(routing(visualizing: true, displays: []).effectiveTarget(held: .external(id: "a")), .device)
    }

    func testAHeldBackgroundDisplayKeepsTheVisual() {
        var r = routing(visualizing: true, displays: ["a"])
        r.apply(.foreground(id: "a", false))
        XCTAssertEqual(r.target, .device)
        XCTAssertEqual(r.effectiveTarget(held: .external(id: "a")), .external(id: "a"), "moving would change the recording's size")
    }

    func testWithoutAVisualizationTheTargetIsTheDevice() {
        let r = routing(visualizing: false, displays: ["a"])
        XCTAssertEqual(r.effectiveTarget(held: .external(id: "a")), .device)
    }
}
