// OUT-001-T02: the external display routing rules (OUT-001-S3; data-model.md "Rules"). Pure Swift,
// so these run on the macOS host and on Linux.
import PresentationLifecycle
import XCTest

final class ExternalDisplayRoutingTests: XCTestCase {
    private let hd = ExternalDisplayGeometry(width: 1920, height: 1080, scale: 1)
    private let tv = ExternalDisplayGeometry(width: 720, height: 480, scale: 1)

    private func visualizing() -> ExternalDisplayRouting {
        var routing = ExternalDisplayRouting()
        routing.apply(.visualizing(true))
        return routing
    }

    func testNoDisplayMeansDevice() {
        XCTAssertEqual(ExternalDisplayRouting().target, .device)
        XCTAssertEqual(visualizing().target, .device)
    }

    func testConnectingAUsableForegroundDisplayMovesTheVisualization() {
        var routing = visualizing()
        XCTAssertTrue(routing.apply(.connected(id: "a", geometry: hd, foreground: true)))
        XCTAssertEqual(routing.target, .external(id: "a"))
        XCTAssertEqual(routing.active?.geometry.pixelWidth, 1920)
        XCTAssertEqual(routing.active?.geometry.pixelHeight, 1080)
    }

    func testNotVisualizingKeepsTheDeviceAndTheExternalWindowBlack() {
        var routing = ExternalDisplayRouting()
        XCTAssertFalse(routing.apply(.connected(id: "a", geometry: hd, foreground: true)), "nothing to move yet")
        XCTAssertEqual(routing.target, .device)
        XCTAssertTrue(routing.apply(.visualizing(true)))
        XCTAssertEqual(routing.target, .external(id: "a"))
        XCTAssertTrue(routing.apply(.visualizing(false)), "stopping the visualizer returns to the device")
        XCTAssertEqual(routing.target, .device)
    }

    func testZeroOrNonFiniteSizeWaitsForAUsableSize() {
        var routing = visualizing()
        routing.apply(.connected(id: "a", geometry: ExternalDisplayGeometry(width: 0, height: 0, scale: 1), foreground: true))
        XCTAssertEqual(routing.target, .device)
        routing.apply(.resized(id: "a", geometry: ExternalDisplayGeometry(width: .nan, height: 1080, scale: 1)))
        XCTAssertEqual(routing.target, .device)
        routing.apply(.resized(id: "a", geometry: ExternalDisplayGeometry(width: 1920, height: 1080, scale: 0)))
        XCTAssertEqual(routing.target, .device)
        XCTAssertTrue(routing.apply(.resized(id: "a", geometry: hd)))
        XCTAssertEqual(routing.target, .external(id: "a"))
        XCTAssertFalse(ExternalDisplayGeometry(width: .infinity, height: 1, scale: 1).isUsable)
        XCTAssertEqual(ExternalDisplayGeometry(width: 0, height: 0, scale: 1).pixelWidth, 0)
    }

    func testBackgroundReturnsToTheDeviceAndForegroundBringsItBack() {
        var routing = visualizing()
        routing.apply(.connected(id: "a", geometry: hd, foreground: true))
        XCTAssertTrue(routing.apply(.foreground(id: "a", false)))
        XCTAssertEqual(routing.target, .device)
        XCTAssertTrue(routing.apply(.foreground(id: "a", true)))
        XCTAssertEqual(routing.target, .external(id: "a"))
    }

    func testASecondDisplayWaitsUntilTheFirstLeaves() {
        var routing = visualizing()
        routing.apply(.connected(id: "a", geometry: hd, foreground: true))
        XCTAssertFalse(routing.apply(.connected(id: "b", geometry: tv, foreground: true)), "the first keeps it")
        XCTAssertEqual(routing.target, .external(id: "a"))
        XCTAssertTrue(routing.apply(.disconnected(id: "a")))
        XCTAssertEqual(routing.target, .external(id: "b"), "the next eligible display takes over")
        XCTAssertTrue(routing.apply(.disconnected(id: "b")))
        XCTAssertEqual(routing.target, .device)
    }

    func testDisconnectAndReconnect() {
        var routing = visualizing()
        routing.apply(.connected(id: "a", geometry: hd, foreground: true))
        XCTAssertTrue(routing.apply(.disconnected(id: "a")))
        XCTAssertEqual(routing.target, .device)
        XCTAssertTrue(routing.displays.isEmpty)
        XCTAssertTrue(routing.apply(.connected(id: "a2", geometry: tv, foreground: true)))
        XCTAssertEqual(routing.target, .external(id: "a2"))
    }

    func testResizeOfTheActiveDisplayAsksForLayoutButKeepsTheTarget() {
        var routing = visualizing()
        routing.apply(.connected(id: "a", geometry: hd, foreground: true))
        XCTAssertTrue(routing.apply(.resized(id: "a", geometry: tv)), "the drawable must follow the new size")
        XCTAssertEqual(routing.target, .external(id: "a"))
        XCTAssertFalse(routing.apply(.resized(id: "a", geometry: tv)), "the same size changes nothing")
    }

    func testRepeatedConnectActsAsAnUpdate() {
        var routing = visualizing()
        routing.apply(.connected(id: "a", geometry: hd, foreground: false))
        XCTAssertEqual(routing.target, .device)
        XCTAssertTrue(routing.apply(.connected(id: "a", geometry: tv, foreground: true)))
        XCTAssertEqual(routing.displays.count, 1)
        XCTAssertEqual(routing.active?.geometry, tv)
    }

    func testUnknownIdsAreIgnored() {
        var routing = visualizing()
        let before = routing
        XCTAssertFalse(routing.apply(.resized(id: "x", geometry: hd)))
        XCTAssertFalse(routing.apply(.foreground(id: "x", true)))
        XCTAssertFalse(routing.apply(.disconnected(id: "x")))
        XCTAssertEqual(routing, before)
    }
}
