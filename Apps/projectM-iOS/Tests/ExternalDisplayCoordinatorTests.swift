// ExternalDisplayCoordinatorTests.swift — OUT-001-T07 and T09: the external display coordinator
// with real slot views (no display, simulator screen or device needed), the iOS 26 scene
// configuration, the scene-role filter, and the Camera visual (stand-in camera) rendering at an
// external size and scale and back without stopping. Moves are checked inside the call (OUT-001-R6),
// with no wall-clock timing. Simulator results are never device evidence (OUT-001-T15 is).
import CameraLayer
import Metal
import PresentationLifecycle
import Rendering
import UIKit
import XCTest
@testable import projectM_iOS

@MainActor
final class ExternalDisplayCoordinatorTests: XCTestCase {
    private let hd = ExternalDisplayGeometry(width: 1920, height: 1080, scale: 1)

    private func slots() -> (device: VisualSlotView, external: VisualSlotView) {
        let device = VisualSlotView(role: .device)
        device.frame = CGRect(x: 0, y: 0, width: 200, height: 400)
        let external = VisualSlotView(role: .external)
        external.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        return (device, external)
    }

    /// A coordinator with a device slot and a visual on the visualizer screen.
    private func visualizing() -> (ExternalDisplayCoordinator, VisualSlotView, VisualSlotView, UIView) {
        let coordinator = ExternalDisplayCoordinator()
        let (device, external) = slots()
        let visual = UIView()
        coordinator.registerDeviceSlot(device)
        coordinator.show(visual)
        coordinator.visualizerActive(true)
        return (coordinator, device, external, visual)
    }

    // MARK: - Scene configuration (T07; OUT-001-D1)

    func testInfoPlistConfiguresOnlyTheExternalDisplayRole() throws {
        let manifest = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") as? [String: Any])
        XCTAssertEqual(manifest["UIApplicationSupportsMultipleScenes"] as? Bool, false, "multiple windows stay off")
        let configurations = try XCTUnwrap(manifest["UISceneConfigurations"] as? [String: [[String: Any]]])
        XCTAssertEqual(Array(configurations.keys), [UISceneSession.Role.windowExternalDisplayNonInteractive.rawValue],
                       "the application role stays with SwiftUI")
        let entry = try XCTUnwrap(configurations[UISceneSession.Role.windowExternalDisplayNonInteractive.rawValue]?.first)
        let className = try XCTUnwrap(entry["UISceneDelegateClassName"] as? String)
        XCTAssertEqual(className, String(reflecting: ExternalDisplaySceneDelegate.self), "names the delegate in this module")
    }

    func testOnlyTheDeviceScenesEventsReachTheDeviceVisuals() {
        XCTAssertTrue(ExternalDisplayScenes.affectsDeviceVisuals(role: .windowApplication))
        XCTAssertFalse(ExternalDisplayScenes.affectsDeviceVisuals(role: .windowExternalDisplayNonInteractive))
        let note = Notification(name: UIScene.didDisconnectNotification, object: nil)
        XCTAssertTrue(ExternalDisplayScenes.affectsDeviceVisuals(note), "a notification without a scene keeps today's behaviour")
    }

    // MARK: - Routing to slots (T07; OUT-001-R1 to R6)

    func testTheVisualMovesToTheExternalDisplayAndBackInsideTheCall() {
        let (coordinator, device, external, visual) = visualizing()
        XCTAssertTrue(visual.superview === device)
        XCTAssertFalse(coordinator.showsVisualExternally)
        coordinator.externalConnected(id: "a", slot: external, geometry: hd, foreground: true)
        XCTAssertTrue(visual.superview === external, "moved before the call returns")
        XCTAssertEqual(visual.frame, external.bounds, "fills the external display")
        XCTAssertTrue(device.subviews.isEmpty, "no device preview (OUT-001-R3)")
        XCTAssertTrue(coordinator.showsVisualExternally)
        XCTAssertEqual(coordinator.target, .external(id: "a"))
        coordinator.externalDisconnected(id: "a")
        XCTAssertTrue(visual.superview === device, "back on the device")
        XCTAssertTrue(external.subviews.isEmpty)
        XCTAssertFalse(coordinator.showsVisualExternally)
        coordinator.externalConnected(id: "b", slot: external, geometry: hd, foreground: true)
        XCTAssertTrue(visual.superview === external, "reconnect")
        XCTAssertEqual(coordinator.placements, 4, "device, external, device, external")
    }

    func testAVisualChangeWhileExternalGoesToTheExternalDisplay() {
        let (coordinator, device, external, visual) = visualizing()
        coordinator.externalConnected(id: "a", slot: external, geometry: hd, foreground: true)
        let next = UIView()
        coordinator.show(next)
        XCTAssertTrue(next.superview === external)
        XCTAssertNil(visual.superview, "the previous visual leaves the window and stops drawing")
        XCTAssertEqual(external.subviews.count, 1, "the external window holds only the current visual")
        XCTAssertTrue(device.subviews.isEmpty)
    }

    func testANewDeviceSlotDoesNotPullTheVisualBackWhileExternal() {
        let (coordinator, _, external, visual) = visualizing()
        coordinator.externalConnected(id: "a", slot: external, geometry: hd, foreground: true)
        let replacement = VisualSlotView(role: .device)   // SwiftUI re-created the device host
        coordinator.registerDeviceSlot(replacement)
        XCTAssertTrue(visual.superview === external)
        XCTAssertTrue(replacement.subviews.isEmpty)
    }

    func testTheExternalDisplayStaysBlackWithoutAVisualization() {
        let coordinator = ExternalDisplayCoordinator()
        let (_, external) = slots()
        coordinator.externalConnected(id: "a", slot: external, geometry: hd, foreground: true)
        XCTAssertFalse(coordinator.showsVisualExternally, "notice or chooser: nothing is projected")
        XCTAssertTrue(external.subviews.isEmpty)
        let visual = UIView()
        coordinator.show(visual)
        XCTAssertTrue(external.subviews.isEmpty, "not on the visualizer screen")
        coordinator.visualizerActive(true)
        XCTAssertTrue(visual.superview === external)
        coordinator.visualizerActive(false)
        XCTAssertTrue(external.subviews.isEmpty, "stop returns the external display to black")
        XCTAssertFalse(coordinator.showsVisualExternally)
    }

    func testZeroSizeAndBackgroundKeepTheVisualOnTheDevice() {
        let (coordinator, device, external, visual) = visualizing()
        coordinator.externalConnected(id: "a", slot: external, geometry: ExternalDisplayGeometry(width: 0, height: 0, scale: 1),
                                      foreground: true)
        XCTAssertTrue(visual.superview === device, "no size yet")
        coordinator.externalResized(id: "a", geometry: hd)
        XCTAssertTrue(visual.superview === external)
        coordinator.externalForeground(id: "a", false)
        XCTAssertTrue(visual.superview === device, "background")
        coordinator.externalForeground(id: "a", true)
        XCTAssertTrue(visual.superview === external, "foreground again")
    }

    func testTheSlotReportsItsSizeAndScale() throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ (s: UIScene) -> UIWindowScene? in s as? UIWindowScene }).first else {
            throw XCTSkip("No window scene in the test host")
        }
        let coordinator = ExternalDisplayCoordinator()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 100_000, y: 0, width: 960, height: 540)
        let external = VisualSlotView(role: .external)
        coordinator.externalConnected(id: "a", slot: external, geometry: ExternalDisplayGeometry(width: 0, height: 0, scale: 1),
                                      foreground: true)
        external.frame = window.bounds
        window.addSubview(external)
        window.isHidden = false
        defer { window.isHidden = true }
        external.layoutIfNeeded()
        let screenScale = external.traitCollection.displayScale
        XCTAssertEqual(coordinator.routing.active?.geometry, ExternalDisplayGeometry(width: 960, height: 540, scale: Double(screenScale)),
                       "the size arrives from layout")
        external.traitOverrides.displayScale = screenScale == 2 ? 1 : 2   // the display's scale changes
        external.layoutIfNeeded()
        let scale: CGFloat = screenScale == 2 ? 1 : 2
        XCTAssertEqual(coordinator.routing.active?.geometry, ExternalDisplayGeometry(width: 960, height: 540, scale: Double(scale)),
                       "a scale change alone is reported too")
        XCTAssertEqual(coordinator.routing.active?.geometry.pixelWidth, Int(960 * scale))
    }

    // MARK: - A real visual at an external size (T09; OUT-001-R2, R4, R7, R9)

    func testCameraVisualRendersAtTheExternalSizeAndComesBackWithoutStopping() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ (s: UIScene) -> UIWindowScene? in s as? UIWindowScene }).first else {
            throw XCTSkip("No window scene in the test host")
        }
        var stub: StubCameraFrameProvider?
        let host = try CameraVisualHost.make(device: device, reader: nil, barCount: .b32) { (device: MTLDevice) -> any CameraFrameProvider in
            let made = StubCameraFrameProvider(device: device, scenario: .granted)
            stub = made
            return made
        }
        let camera = try XCTUnwrap(stub)
        let coordinator = ExternalDisplayCoordinator()
        let deviceWindow = UIWindow(windowScene: scene)
        deviceWindow.frame = CGRect(x: 0, y: 0, width: 200, height: 400)
        let deviceSlot = VisualSlotView(role: .device)
        deviceSlot.frame = deviceWindow.bounds
        deviceWindow.addSubview(deviceSlot)
        deviceWindow.isHidden = false
        let externalWindow = UIWindow(windowScene: scene)
        externalWindow.frame = CGRect(x: 100_000, y: 0, width: 1920, height: 1080)   // off screen
        let externalSlot = VisualSlotView(role: .external)
        externalSlot.traitOverrides.displayScale = 1   // a 1080p television
        externalSlot.frame = externalWindow.bounds
        externalWindow.addSubview(externalSlot)
        externalWindow.isHidden = false
        defer {
            host.pause()
            host.view.removeFromSuperview()
            deviceWindow.isHidden = true
            externalWindow.isHidden = true
        }
        coordinator.registerDeviceSlot(deviceSlot)
        coordinator.show(host.view)
        coordinator.visualizerActive(true)
        host.view.layoutIfNeeded()
        host.resume()
        let renderScale = QualityGovernor.current().renderScale
        let deviceScale = deviceSlot.traitCollection.displayScale
        let deviceSize = CGSize(width: (200 * deviceScale * renderScale).rounded(), height: (400 * deviceScale * renderScale).rounded())
        XCTAssertEqual(host.view.metalLayer.drawableSize, deviceSize)
        wait("frames on the device") { host.framesComposited > 2 }

        coordinator.externalConnected(id: "tv", slot: externalSlot, geometry: externalSlot.geometry, foreground: true)
        host.view.layoutIfNeeded()
        XCTAssertEqual(host.view.metalLayer.drawableSize, CGSize(width: (1920 * renderScale).rounded(), height: (1080 * renderScale).rounded()),
                       "drawn for the external display's size and scale, not a copy of the device picture")
        let before = host.framesComposited
        wait("frames on the external display") { host.framesComposited > before + 2 }
        XCTAssertEqual(camera.state, .running, "the move does not stop the camera (OUT-001-R9)")
        XCTAssertTrue(host.isRunning)

        coordinator.externalDisconnected(id: "tv")
        host.view.layoutIfNeeded()
        XCTAssertEqual(host.view.metalLayer.drawableSize, deviceSize, "back at the device size")
        let after = host.framesComposited
        wait("frames on the device again") { host.framesComposited > after + 2 }
        XCTAssertEqual(camera.state, .running)
    }

    private func wait(_ description: String, timeout: TimeInterval = 10, until condition: @escaping @MainActor () -> Bool) {
        let done = expectation(description: description)
        var fulfilled = false
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { (_: Timer) in
            MainActor.assumeIsolated {
                if !fulfilled, condition() {
                    fulfilled = true
                    done.fulfill()
                }
            }
        }
        wait(for: [done], timeout: timeout)
        timer.invalidate()
    }
}
