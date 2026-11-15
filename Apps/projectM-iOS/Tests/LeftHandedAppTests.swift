// LeftHandedAppTests.swift — ACC-010-T08, T09 (specs/248-acc-010-left-handed-layout; R1, R4, R6, R7; S3, S4).
// T09: the "Left-handed controls" preference and the side it gives (with and without ACC-009's one-handed layout).
// T08: the output is never mirrored (UIX-013's isolation pattern): an external display window built like the app's
// (`ExternalDisplayViewController`) shows an asymmetric stand-in visual (left half blue, right half red) while the real
// `PerformancePadLayer` is drawn right-handed, then left-handed, in a device window. The external snapshot is
// byte-identical in both, its left half stays blue, and the device picture does change (the pad moved).
// The geometry is tested in ShowControl (HandedPlacementTests); the running app by LeftHandedUITests.
// Simulator results are never device evidence (ACC-010-T13 is the device check).
import LibraryBackup
import PresentationLifecycle
import ShowControl
import SwiftUI
import UIKit
import XCTest
@testable import projectM_iOS

@MainActor
final class LeftHandedAppTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "LeftHandedAppTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: - T09: preference (R1, R6, R7)

    func testOffByDefaultAndStoredOnChange() {
        let defaults: UserDefaults = freshDefaults()
        let setting = OneHandedSetting(defaults: defaults, isPhone: true)
        XCTAssertFalse(setting.leftHanded)
        XCTAssertEqual(setting.controlsSide, .right)
        XCTAssertNil(defaults.object(forKey: OneHandedSetting.leftHandedKey), "nothing stored until changed")
        setting.leftHanded = true
        XCTAssertEqual(defaults.object(forKey: OneHandedSetting.leftHandedKey) as? Bool, true)
        XCTAssertEqual(setting.controlsSide, .left)
        XCTAssertTrue(OneHandedSetting(defaults: defaults, isPhone: true).leftHanded, "kept across launches")
        setting.leftHanded = false
        XCTAssertNil(defaults.object(forKey: OneHandedSetting.leftHandedKey), "off removes the key")
    }

    /// R6: while one-handed is active its hand decides; on iPad (one-handed ignored) the switch decides.
    func testOneHandedHandDecidesWhileActive() {
        let phone = OneHandedSetting(defaults: freshDefaults(), isPhone: true)
        phone.leftHanded = true
        phone.hand = .right
        XCTAssertEqual(phone.controlsSide, .right)
        phone.hand = .left
        phone.leftHanded = false
        XCTAssertEqual(phone.controlsSide, .left)
        phone.hand = nil
        XCTAssertEqual(phone.controlsSide, .right)

        let pad = OneHandedSetting(defaults: freshDefaults(), isPhone: false)
        pad.hand = .right
        pad.leftHanded = true
        XCTAssertEqual(pad.controlsSide, .left, "iPad ignores the one-handed hand (ACC-009-R6)")
    }

    /// R7, S4: backed up with the library settings (and so erased with Settings by FILE-011).
    func testKeyIsBackedUp() {
        XCTAssertEqual(OneHandedSetting.leftHandedKey, "settings.controls.leftHanded")
        XCTAssertTrue(LibrarySettingsPolicy.includedKeys.contains(OneHandedSetting.leftHandedKey))
    }

    // MARK: - T08: the output is never mirrored (R4, S3)

    private func scene() throws -> UIWindowScene {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ (s: UIScene) -> UIWindowScene? in s as? UIWindowScene }).first else {
            throw XCTSkip("No window scene in the test host")
        }
        return scene
    }

    /// What the window shows, as RGBA bytes at scale 1.
    private func snapshot(_ window: UIWindow) -> [UInt8] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { (_: UIGraphicsImageRendererContext) in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let cg = image.cgImage else { return [] }
        let width: Int = cg.width, height: Int = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        bytes.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) -> Void in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }

    private func rgb(_ bytes: [UInt8], width: Int, x: Int, y: Int) -> [UInt8] {
        let i = (y * width + x) * 4
        return Array(bytes[i..<(i + 3)])
    }

    /// Lets SwiftUI apply the pad's measured geometry (a few run-loop turns; no timing is asserted).
    private func settle(_ window: UIWindow) {
        for _ in 0..<5 {
            window.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    /// A stand-in visual whose left half is blue and right half red, so any mirror would show.
    private final class HalvesView: UIView {
        private let left = UIView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
            left.backgroundColor = UIColor(red: 0, green: 0, blue: 1, alpha: 1)
            addSubview(left)
        }

        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            left.frame = CGRect(x: 0, y: 0, width: bounds.width / 2, height: bounds.height)
        }
    }

    func testExternalOutputIsIdenticalOnBothSides() throws {
        let scene = try scene()
        let external = ExternalDisplayCoordinator()
        let show = ShowCoordinator(store: nil, registry: nil)
        let tempo = TempoCoordinator(announce: { (_: String) -> Void in })

        // The device window: its slot below, the real pad above (as in VisualizerView).
        let deviceWindow = UIWindow(windowScene: scene)
        deviceWindow.frame = CGRect(x: 0, y: 0, width: 400, height: 220)   // landscape-shaped: side columns
        let deviceRoot = UIViewController()
        deviceWindow.rootViewController = deviceRoot
        let deviceSlot = VisualSlotView(role: .device)
        deviceSlot.frame = deviceRoot.view.bounds
        deviceRoot.view.addSubview(deviceSlot)
        deviceWindow.isHidden = false
        // The external window, built like ExternalDisplaySceneDelegate's.
        let externalWindow = UIWindow(windowScene: scene)
        externalWindow.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        let controller = ExternalDisplayViewController()
        externalWindow.rootViewController = controller
        controller.slot.traitOverrides.displayScale = 1
        externalWindow.isHidden = false
        controller.view.layoutIfNeeded()
        defer { deviceWindow.isHidden = true; externalWindow.isHidden = true }

        let visual = HalvesView(frame: .zero)
        external.registerDeviceSlot(deviceSlot)
        external.show(visual)
        external.visualizerActive(true)
        external.externalConnected(id: "tv", slot: controller.slot, geometry: controller.slot.geometry, foreground: true)
        XCTAssertTrue(visual.superview === controller.slot, "the visual is on the external display")
        controller.slot.layoutIfNeeded()
        visual.layoutIfNeeded()

        var externalShots: [[UInt8]] = []
        var deviceShots: [[UInt8]] = []
        for side in [ControlsSide.right, .left] {
            let pad = PerformancePadLayer(show: show, tempo: tempo, external: external, side: side) { (_: EdgeInsets) -> Void in }
            let host = UIHostingController(rootView: pad)
            host.view.backgroundColor = .clear
            deviceRoot.addChild(host)
            host.view.frame = deviceRoot.view.bounds
            deviceRoot.view.addSubview(host.view)
            host.didMove(toParent: deviceRoot)
            settle(deviceWindow)
            deviceShots.append(snapshot(deviceWindow))
            externalShots.append(snapshot(externalWindow))
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
        }

        XCTAssertFalse(externalShots[0].isEmpty)
        XCTAssertTrue(externalShots[0] == externalShots[1], "S3: the external picture is byte-identical right- and left-handed")
        XCTAssertEqual(rgb(externalShots[1], width: 320, x: 40, y: 90), [0, 0, 255], "left half still blue: not mirrored")
        XCTAssertEqual(rgb(externalShots[1], width: 320, x: 280, y: 90), [255, 0, 0], "right half still red")
        XCTAssertFalse(deviceShots[0] == deviceShots[1], "the pad itself moved on the device")
        XCTAssertTrue(CGAffineTransformIsIdentity(visual.transform), "the visual is not transformed")
        XCTAssertTrue(CATransform3DIsIdentity(visual.layer.transform))
        XCTAssertEqual(controller.slot.subviews, [visual], "the external slot holds the visual and nothing else (OUT-001-R1)")
        let externalViews: [UIView] = descendants(externalWindow)
        XCTAssertFalse(externalViews.contains { (v: UIView) -> Bool in String(describing: type(of: v)).contains("Hosting") },
                       "no SwiftUI hosting view (no pad) on the external display")
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap { (child: UIView) -> [UIView] in descendants(child) }
    }
}
