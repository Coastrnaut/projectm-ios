// OutputBlackoutCoordinatorTests.swift — OUT-010-T07, T10, T11: the output blackout with real slot
// views (no display, simulator screen or device needed). "Within one frame" is checked as: the slot
// holding the visual is opaque black, with no animation, before `setBlackout(true)` returns, so the
// current Core Animation transaction carries it to the next composited frame (research OUT-010-D1).
// The fade is driven with fake frame times; nothing reads the wall clock. Simulator results are never
// device evidence (OUT-010-T15 is).
import PresentationLifecycle
import UIKit
import XCTest
@testable import projectM_iOS

@MainActor
final class OutputBlackoutCoordinatorTests: XCTestCase {
    private let hd = ExternalDisplayGeometry(width: 1920, height: 1080, scale: 1)
    private let dt = 1.0 / 60

    private func slot(_ role: VisualSlotView.Role, width: CGFloat, height: CGFloat) -> VisualSlotView {
        let slot = VisualSlotView(role: role)
        slot.frame = CGRect(x: 0, y: 0, width: width, height: height)
        slot.layoutIfNeeded()
        return slot
    }

    /// A coordinator on the visualizer with a device slot and a visual; the display link is off.
    private func visualizing() -> (ExternalDisplayCoordinator, VisualSlotView, VisualSlotView, UIView) {
        let coordinator = ExternalDisplayCoordinator()
        coordinator.usesDisplayLink = false
        let device = slot(.device, width: 200, height: 400)
        let external = slot(.external, width: 1920, height: 1080)
        let visual = UIView()
        coordinator.registerDeviceSlot(device)
        coordinator.show(visual)
        coordinator.visualizerActive(true)
        return (coordinator, device, external, visual)
    }

    private func advance(_ coordinator: ExternalDisplayCoordinator, seconds: Double) {
        for _ in 0..<Int((seconds / dt).rounded()) { coordinator.advanceFrame(frameTime: dt) }
    }

    // MARK: - One frame (T07; OUT-010-R2, R3, R4)

    func testBlackOutCoversTheDeviceOutputInsideTheCall() {
        let (coordinator, device, _, visual) = visualizing()
        let placements = coordinator.placements
        XCTAssertFalse(device.isOutputBlack, "live")
        XCTAssertEqual(device.coverOpacity, 0)
        coordinator.setBlackout(true)
        XCTAssertTrue(device.isOutputBlack, "opaque, filling, not animating, before the call returns")
        XCTAssertTrue(coordinator.isOutputBlack)
        XCTAssertTrue(visual.superview === device, "the visual stays in its slot and keeps running")
        XCTAssertEqual(coordinator.placements, placements, "no move")
        XCTAssertEqual(coordinator.blackoutPhase, .blackedOut)
        XCTAssertTrue(coordinator.isBlackoutRequested)
    }

    func testBlackOutCoversTheExternalOutputInsideTheCall() {
        let (coordinator, device, external, visual) = visualizing()
        coordinator.externalConnected(id: "a", slot: external, geometry: hd, foreground: true)
        XCTAssertTrue(visual.superview === external)
        XCTAssertFalse(external.isOutputBlack)
        coordinator.toggleBlackout()
        XCTAssertTrue(external.isOutputBlack, "the external display is black at the next frame")
        XCTAssertTrue(coordinator.isOutputBlack)
        XCTAssertTrue(visual.superview === external, "no device preview (spec Clarifications)")
        XCTAssertTrue(device.subviews.isEmpty)
        XCTAssertTrue(coordinator.showsVisualExternally)
    }

    func testANewCoordinatorStartsLiveAndNamesItsStates() {
        let coordinator = ExternalDisplayCoordinator()
        XCTAssertEqual(coordinator.blackoutPhase, .live, "nothing is stored (OUT-010-R11)")
        XCTAssertFalse(coordinator.isBlackoutRequested)
        XCTAssertEqual(OutputBlackout.Phase.live.accessibilityValue, "Live")
        XCTAssertEqual(OutputBlackout.Phase.blackedOut.accessibilityValue, "Blacked out")
        XCTAssertEqual(OutputBlackout.Phase.restoreWaiting.accessibilityValue, "Restore waiting")
        XCTAssertEqual(OutputBlackout.Phase.fadingIn.accessibilityValue, "Fading in")
    }

    func testAHalfOpaqueCoverOverWhiteBlendsEncodedValues() throws {
        // Research OUT-010-D2: the fade's opacity assumes Core Animation blends encoded values.
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { (s: UIScene) -> UIWindowScene? in s as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        window.windowLevel = .normal - 1
        let slot = VisualSlotView(role: .device)
        slot.frame = window.bounds
        let white = UIView()
        white.backgroundColor = .white
        window.addSubview(slot)
        window.isHidden = false
        slot.hold(white)
        slot.layoutIfNeeded()
        slot.coverOpacity = 0.5
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(bounds: slot.bounds, format: format).image { (_: UIGraphicsImageRendererContext) in
            _ = slot.drawHierarchy(in: slot.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        let cg = try XCTUnwrap(image.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: -20, y: -20, width: cg.width, height: cg.height))
        XCTAssertEqual(Double(pixel[0]), 127.5, accuracy: 4, "encoded 0.5, not linear-light 0.73 (186)")
    }

    // MARK: - Restore (T10; OUT-010-R6, R7)

    func testRestoreFadesTheCoverOverFrameTime() {
        for (reduce, seconds) in [(false, 1.0), (true, 4.0)] {
            let (coordinator, device, _, _) = visualizing()
            coordinator.reduceFlashing = reduce
            coordinator.setBlackout(true)
            coordinator.setBlackout(false)
            XCTAssertEqual(coordinator.blackoutPhase, .fadingIn)
            XCTAssertTrue(device.isOutputBlack, "restore alone shows nothing")
            advance(coordinator, seconds: seconds / 2)
            XCTAssertGreaterThan(device.coverOpacity, 0, "half way")
            XCTAssertLessThan(device.coverOpacity, 1)
            XCTAssertFalse(coordinator.isBlackoutRequested, "the control offers Black out during the fade")
            advance(coordinator, seconds: seconds / 2 + 2 * dt)
            XCTAssertEqual(coordinator.blackoutPhase, .live, "reduce flashing \(reduce)")
            XCTAssertEqual(device.coverOpacity, 0)
            XCTAssertFalse(coordinator.blackout.needsFrames)
            coordinator.setBlackout(true)
            XCTAssertTrue(device.isOutputBlack)
        }
    }

    func testTheDisplayLinkRunsOnlyWhileTheBlackoutNeedsFrames() {
        let (coordinator, _, _, _) = visualizing()
        coordinator.usesDisplayLink = true
        coordinator.setBlackout(true)
        XCTAssertFalse(coordinator.drivesBlackoutFrames, "simply black needs no frames")
        coordinator.setBlackout(false)
        XCTAssertTrue(coordinator.drivesBlackoutFrames, "the fade runs on the display link")
        coordinator.setBlackout(true)
        XCTAssertTrue(coordinator.drivesBlackoutFrames, "the restore spacing still counts")
        advance(coordinator, seconds: 1.1)
        XCTAssertFalse(coordinator.drivesBlackoutFrames, "stopped once nothing needs frames")
        XCTAssertEqual(coordinator.blackoutPhase, .blackedOut)
    }

    // MARK: - The blackout follows the output (T11; OUT-010-R8)

    func testTheBlackoutFollowsConnectDisconnectReentryAndVisualChanges() {
        let (coordinator, device, external, visual) = visualizing()
        coordinator.setBlackout(true)

        coordinator.externalConnected(id: "a", slot: external, geometry: hd, foreground: true)
        XCTAssertTrue(visual.superview === external)
        XCTAssertTrue(external.isOutputBlack, "connect: the external display receives the visual already black")

        coordinator.externalForeground(id: "a", false)
        XCTAssertTrue(visual.superview === device)
        XCTAssertTrue(device.isOutputBlack, "external background: back on the device, still black")
        coordinator.externalForeground(id: "a", true)
        XCTAssertTrue(external.isOutputBlack)

        coordinator.externalDisconnected(id: "a")
        XCTAssertTrue(visual.superview === device)
        XCTAssertTrue(device.isOutputBlack, "disconnect never reveals the picture")

        let next = UIView()
        coordinator.show(next)
        XCTAssertTrue(next.superview === device)
        XCTAssertTrue(device.isOutputBlack, "a visual change stays black")

        coordinator.visualizerActive(false)
        coordinator.unregisterDeviceSlot(device)
        let reentered = slot(.device, width: 200, height: 400)
        coordinator.registerDeviceSlot(reentered)
        coordinator.visualizerActive(true)
        XCTAssertTrue(next.superview === reentered)
        XCTAssertTrue(reentered.isOutputBlack, "re-entering the visualizer stays black")

        coordinator.setBlackout(false)
        advance(coordinator, seconds: 1.1)
        XCTAssertEqual(coordinator.blackoutPhase, .live)
        XCTAssertFalse(reentered.isOutputBlack)
        XCTAssertEqual(reentered.coverOpacity, 0, "restored")
    }
}
