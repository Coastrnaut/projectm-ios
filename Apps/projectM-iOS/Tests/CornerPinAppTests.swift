// CornerPinAppTests.swift — OUT-007-T06, T09 (specs/264-out-007-corner-pin; contract C2-C4). The external
// stand-in display is built like the app's (`ExternalDisplayViewController` in an off-screen 1920 × 1080 window).
// T06: projecting the slot's corners through the applied `sublayerTransform` (about the layer's anchor, as Core
// Animation does) lands them on the quad in slot coordinates; the device slot and the visual's own geometry and
// drawable size (what a recording encodes) are untouched; the recording hold does not defer it; the calibration
// card shows only while the editor is open and stays under the blackout cover. T09: the preference. Simulator
// results are never device evidence (OUT-007-T12 is the projector check).
import PresentationLifecycle
import UIKit
import XCTest
@testable import projectM_iOS

@MainActor
final class CornerPinAppTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let name = "out007-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return defaults
    }

    private func externalWindow() throws -> VisualSlotView {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { (s: UIScene) -> UIWindowScene? in s as? UIWindowScene }.first)
        let controller = ExternalDisplayViewController()
        controller.slot.traitOverrides.displayScale = 1
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 100_000, y: 0, width: 1920, height: 1080)
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        addTeardownBlock { @MainActor in window.isHidden = true }
        return controller.slot
    }

    private func pin() throws -> CornerPin {
        try XCTUnwrap(CornerPin(topLeft: CornerPinPoint(x: 0.08, y: 0.04), topRight: CornerPinPoint(x: 0.95, y: 0),
                                bottomRight: CornerPinPoint(x: 1, y: 0.97), bottomLeft: CornerPinPoint(x: 0.02, y: 0.9)))
    }

    private static func values(_ t: CATransform3D) -> [Double] {
        [t.m11, t.m12, t.m13, t.m14, t.m21, t.m22, t.m23, t.m24, t.m31, t.m32, t.m33, t.m34, t.m41, t.m42, t.m43, t.m44]
            .map { (v: CGFloat) -> Double in Double(v) }
    }

    /// Where Core Animation draws the slot-local point (`x`, `y`) of a sublayer: through `sublayerTransform`
    /// about the layer's anchor.
    private static func projected(_ slot: VisualSlotView, x: Double, y: Double) -> CornerPinPoint {
        let b: CGRect = slot.layer.bounds
        let ax = Double(b.minX + slot.layer.anchorPoint.x * b.width), ay = Double(b.minY + slot.layer.anchorPoint.y * b.height)
        return Homography.project(values(slot.layer.sublayerTransform), x: x, y: y, anchorX: ax, anchorY: ay)
    }

    /// The visual's own geometry and drawable size: what the device shows and a recording encodes.
    private struct VisualWitness: Equatable {
        var bounds: CGRect
        var center: CGPoint
        var transform: CGAffineTransform
        var layerTransform: [Double]
        var drawable: ResolvedExternalOutput?
    }

    private func witness(_ visual: UIView, _ slot: VisualSlotView) -> VisualWitness {
        VisualWitness(bounds: visual.bounds, center: visual.center, transform: visual.transform,
                      layerTransform: Self.values(visual.layer.transform), drawable: slot.resolvedOutput)
    }

    /// T06 (OUT-007-R2, R6, R7, S1, S4): the acceptance on the external stand-in.
    func testTheExternalOutputCornersLandOnTheQuadAndTheDeviceIsUnwarped() throws {
        let external = ExternalDisplayCoordinator()
        let device = VisualSlotView(role: .device)
        device.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let visual = UIView()
        external.registerDeviceSlot(device)
        external.show(visual)
        external.visualizerActive(true)
        let slot = try externalWindow()
        external.externalConnected(id: "stand-in", slot: slot, geometry: slot.geometry, foreground: true)
        XCTAssertTrue(visual.superview === slot)
        XCTAssertTrue(CATransform3DIsIdentity(slot.layer.sublayerTransform), "identity by default")
        XCTAssertEqual(external.cornerPinSummary, "pin=identity card=hidden corners=0,0;1,0;1,1;0,1")
        let before: VisualWitness = witness(visual, slot)

        let quad: CornerPin = try pin()
        external.cornerPin = quad
        let size: CGSize = slot.bounds.size
        XCTAssertEqual(size, CGSize(width: 1920, height: 1080))
        let unit: [(Double, Double)] = [(0, 0), (1, 0), (1, 1), (0, 1)]
        for (i, corner) in unit.enumerated() {
            let r: CornerPinPoint = Self.projected(slot, x: corner.0 * Double(size.width), y: corner.1 * Double(size.height))
            XCTAssertEqual(r.x, quad.corners[i].x * Double(size.width), accuracy: 1e-6, "corner \(i) x, inside the call")
            XCTAssertEqual(r.y, quad.corners[i].y * Double(size.height), accuracy: 1e-6, "corner \(i) y")
        }
        XCTAssertEqual(witness(visual, slot), before, "the visual's geometry and drawable are untouched (recording content)")
        XCTAssertTrue(CATransform3DIsIdentity(device.layer.sublayerTransform), "the device is never warped")
        XCTAssertTrue(external.cornerPinSummary.hasPrefix("pin=custom card=hidden"))

        // OUT-007-R7: live while a recording holds the placement.
        external.holdsPlacement = true
        external.cornerPin = .identity
        XCTAssertTrue(CATransform3DIsIdentity(slot.layer.sublayerTransform), "not deferred by the hold")
        external.cornerPin = quad
        external.holdsPlacement = false

        // Back on the device: the visual is unwarped there.
        external.externalDisconnected(id: "stand-in")
        XCTAssertTrue(visual.superview === device)
        XCTAssertTrue(CATransform3DIsIdentity(device.layer.sublayerTransform))
        XCTAssertTrue(CATransform3DIsIdentity(visual.layer.transform))
        XCTAssertEqual(external.cornerPinSummary, "none")

        // A slot that connects later takes the pin at once.
        let later = VisualSlotView(role: .external)
        later.frame = CGRect(x: 0, y: 0, width: 1280, height: 720)
        external.externalConnected(id: "later", slot: later, geometry: later.geometry, foreground: true)
        let r: CornerPinPoint = Self.projected(later, x: 1280, y: 720)
        XCTAssertEqual(r.x, 1280, accuracy: 1e-6)
        XCTAssertEqual(r.y, 0.97 * 720, accuracy: 1e-6)
    }

    /// T06 (OUT-007-R5, R8): the card shows only while calibrating, on every external slot, under the cover.
    func testTheCalibrationCardShowsWhileTheEditorIsOpenAndTheBlackoutStillWins() throws {
        let external = ExternalDisplayCoordinator()
        external.usesDisplayLink = false
        let device = VisualSlotView(role: .device)
        device.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let visual = UIView()
        external.registerDeviceSlot(device)
        external.show(visual)
        external.visualizerActive(true)
        let slot = try externalWindow()
        external.externalConnected(id: "stand-in", slot: slot, geometry: slot.geometry, foreground: true)
        XCTAssertEqual(external.calibrationAspect, 1920.0 / 1080.0, accuracy: 1e-9)

        external.beginCalibration()
        XCTAssertTrue(slot.isCalibrationCardShown)
        XCTAssertFalse(device.isCalibrationCardShown, "never on the device")
        XCTAssertEqual(slot.subviews.count, 1, "the card is a layer: the slot still holds only the visual")
        XCTAssertTrue(external.cornerPinSummary.hasPrefix("pin=identity card=shown"))
        external.setBlackout(true)
        XCTAssertTrue(external.isOutputBlack, "the cover stays above the card")
        external.setBlackout(false)

        external.endCalibration()
        XCTAssertFalse(slot.isCalibrationCardShown)
        external.externalDisconnected(id: "stand-in")
        XCTAssertEqual(external.calibrationAspect, 1920.0 / 1080.0, accuracy: 1e-9, "the last known shape")
        XCTAssertEqual(ExternalDisplayCoordinator().calibrationAspect, 16.0 / 9.0, "else 16:9")
    }

    /// T09 (OUT-007-R9, S5): the pin persists; identity removes it; bad stored values read identity.
    func testTheCornerPinPersistsAndReadsSafely() throws {
        let defaults = try defaults()
        let external = ExternalDisplayCoordinator()
        let setting = ExternalOutputSetting(defaults: defaults, external: external)
        XCTAssertEqual(setting.cornerPin, .identity)
        XCTAssertNil(defaults.object(forKey: ExternalOutputSetting.cornerPinKey), "nothing stored until changed")
        let quad: CornerPin = try pin()
        setting.cornerPin = quad
        XCTAssertEqual(defaults.string(forKey: ExternalOutputSetting.cornerPinKey), quad.stored)
        XCTAssertEqual(external.cornerPin, quad, "applied live")
        let relaunched = ExternalDisplayCoordinator()
        XCTAssertEqual(ExternalOutputSetting(defaults: defaults, external: relaunched).cornerPin, quad, "persisted")
        XCTAssertEqual(relaunched.cornerPin, quad, "applied at launch")
        setting.cornerPin = .identity
        XCTAssertNil(defaults.object(forKey: ExternalOutputSetting.cornerPinKey), "identity is stored as absent")
        for bad in ["0,0;1,0;0,1;1,1", "garbage"] {
            defaults.set(bad, forKey: ExternalOutputSetting.cornerPinKey)
            XCTAssertEqual(ExternalOutputSetting(defaults: defaults, external: ExternalDisplayCoordinator()).cornerPin, .identity, bad)
        }
        XCTAssertTrue(ExternalOutputSetting.keys.contains("settings.externalDisplay.cornerPin"), "device-local, excluded from backup")
        XCTAssertEqual(ExternalOutputSetting.spokenValue(.topLeft, CornerPinPoint(x: 0.035, y: -0.1)), "3.5 % across, minus 10 % down")
    }
}
