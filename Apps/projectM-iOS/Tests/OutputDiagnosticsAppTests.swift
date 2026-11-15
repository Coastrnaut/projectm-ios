// OutputDiagnosticsAppTests.swift — OUT-011-T09 (specs/275-out-011-output-diagnostics; contract C2, C3): the roadmap
// acceptance, "Unplugged display reports disconnected rather than stale data". A real ExternalDisplayCoordinator gets a
// device slot, a stand-in visual and external stand-in displays built like the app's (`ExternalDisplayViewController` in
// an off-screen window, with stand-in screen readings as the DEBUG fake sets them). Connect: the values are shown.
// Disconnect: the snapshot is `.disconnected`, and neither the section's rows nor the probe holds any old value.
// Reconnect at 1280 × 720: the new values, never the old ones. Simulator results are never device evidence
// (OUT-011-T12 is the HDMI check on D1).
import PresentationLifecycle
import UIKit
import XCTest
@testable import projectM_iOS

@MainActor
final class OutputDiagnosticsAppTests: XCTestCase {
    private func scene() throws -> UIWindowScene {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ (s: UIScene) -> UIWindowScene? in s as? UIWindowScene }).first else {
            throw XCTSkip("No window scene in the test host")
        }
        return scene
    }

    /// An off-screen stand-in display of `width` × `height` points at scale 1; `standIn` false reads the window's own screen.
    private func connect(_ coordinator: ExternalDisplayCoordinator, id: String, width: Int, height: Int,
                         standIn: Bool = true) throws -> VisualSlotView {
        let window = UIWindow(windowScene: try scene())
        window.frame = CGRect(x: 100_000, y: 0, width: CGFloat(width), height: CGFloat(height))
        window.windowLevel = .normal - 1
        let controller = ExternalDisplayViewController()
        controller.slot.traitOverrides.displayScale = 1
        if standIn { controller.slot.standInReadings = UITestExternalDisplay.standInReadings(width: width, height: height) }
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        addTeardownBlock { @MainActor in window.isHidden = true }
        let slot = controller.slot
        coordinator.externalConnected(id: id, slot: slot, geometry: slot.geometry, foreground: true)
        slot.layoutIfNeeded()
        return slot
    }

    private func visualizing() -> ExternalDisplayCoordinator {
        let coordinator = ExternalDisplayCoordinator()
        let device = VisualSlotView(role: .device)
        device.frame = CGRect(x: 0, y: 0, width: 390, height: 845)
        coordinator.registerDeviceSlot(device)
        device.layoutIfNeeded()
        coordinator.show(UIView())
        coordinator.visualizerActive(true)
        return coordinator
    }

    private func values(_ d: OutputDiagnostics) -> [String: String] {
        Dictionary(uniqueKeysWithValues: d.rows.map { (row: OutputDiagnosticsRow) -> (String, String) in (row.id, row.value) })
    }

    /// Everything a user or a test could read: the section's rows (as rendered), its copy text and the DEBUG probe.
    private func everything(_ coordinator: ExternalDisplayCoordinator) -> String {
        let d: OutputDiagnostics = OutputDiagnosticsSection.current(coordinator)
        let rows: String = d.rows.map { (r: OutputDiagnosticsRow) -> String in r.title + "=" + r.value }.joined(separator: ";")
        return rows + "|" + d.text + "|" + d.summary
    }

    func testUnpluggedDisplayReportsDisconnectedNotStaleData() throws {
        let coordinator = visualizing()
        XCTAssertEqual(coordinator.outputDiagnostics, .disconnected, "nothing connected")

        _ = try connect(coordinator, id: "a", width: 1920, height: 1080)
        let first: OutputDiagnostics = coordinator.outputDiagnostics
        let v = values(first)
        XCTAssertEqual(v["nativeResolution"], "1920 × 1080 px")
        XCTAssertEqual(v["size"], "1920 × 1080 pt @1x")
        XCTAssertEqual(v["refreshRate"], "60 Hz")
        XCTAssertEqual(v["gamut"], "sRGB")
        XCTAssertEqual(v["edr"], "Not available", "the stand-in reports no headroom: never guessed")
        XCTAssertEqual(v["mirroring"], "Extended")
        XCTAssertEqual(v["drawable"], "1920 × 1080 px", "OUT-003: the visual renders here at native resolution")
        XCTAssertEqual(v["overscan"], "None")
        XCTAssertEqual(v["pixelAspect"], "1.00")
        XCTAssertEqual(v["outputMode"], "Same scene")
        XCTAssertEqual(first.summary, "connected native=1920x1080 pt=1920x1080@1 fps=60 drawable=1920x1080")

        coordinator.externalDisconnected(id: "a")
        XCTAssertEqual(coordinator.outputDiagnostics, .disconnected, "inside the disconnect call")
        let after: String = everything(coordinator)
        XCTAssertEqual(after, "Status=No external display connected|Status: No external display connected|disconnected")
        for stale in ["1920", "1080", "60 Hz", "sRGB", "Extended", "Same scene"] {
            XCTAssertFalse(after.contains(stale), "no old value remains: \(stale)")
        }

        _ = try connect(coordinator, id: "b", width: 1280, height: 720)
        let again = values(coordinator.outputDiagnostics)
        XCTAssertEqual(again["nativeResolution"], "1280 × 720 px", "fresh values after reconnecting")
        XCTAssertEqual(again["size"], "1280 × 720 pt @1x")
        XCTAssertEqual(again["drawable"], "1280 × 720 px")
        XCTAssertFalse(everything(coordinator).contains("1920"), "nothing of the first display")
    }

    func testSettlingConnectionAndVisualElsewhere() throws {
        var fire: (@MainActor () -> Void)?
        let coordinator = ExternalDisplayCoordinator(connectSettle: 0.3) { (_: Double, body: @escaping @MainActor () -> Void) in
            fire = body
        }
        let device = VisualSlotView(role: .device)
        device.frame = CGRect(x: 0, y: 0, width: 390, height: 845)
        coordinator.registerDeviceSlot(device)
        coordinator.show(UIView())
        coordinator.visualizerActive(true)
        _ = try connect(coordinator, id: "a", width: 1920, height: 1080)
        XCTAssertEqual(coordinator.outputDiagnostics, .disconnected, "a settling connection is not connected yet")
        fire?()
        XCTAssertEqual(values(coordinator.outputDiagnostics)["drawable"], "1920 × 1080 px")

        coordinator.visualizerActive(false)   // the visual leaves the display
        let v = values(coordinator.outputDiagnostics)
        XCTAssertEqual(v["nativeResolution"], "1920 × 1080 px", "still connected")
        XCTAssertEqual(v["drawable"], "Not available", "no drawable from earlier")
    }

    func testRealSlotReadsItsOwnScreen() throws {
        let coordinator = visualizing()
        let slot = try connect(coordinator, id: "a", width: 1920, height: 1080, standIn: false)
        let screen: UIScreen = try XCTUnwrap(slot.window?.windowScene?.screen)
        let v = values(coordinator.outputDiagnostics)
        let native: CGRect = screen.nativeBounds
        XCTAssertEqual(v["nativeResolution"], "\(Int(native.width)) × \(Int(native.height)) px", "the scene's screen")
        XCTAssertEqual(v["refreshRate"], "\(screen.maximumFramesPerSecond) Hz")
        coordinator.externalDisconnected(id: "a")
        XCTAssertEqual(coordinator.outputDiagnostics, .disconnected)
    }
}
