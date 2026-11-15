// ExternalOutputResolutionAppTests.swift — OUT-003-T06 (OUT-003-S2) and T09: the roadmap acceptance,
// "Configured scale changes output pixels but not scene coordinates". A real Text visual (compositor:
// circular spectrum and text layers) is placed on an external `VisualSlotView` of 640 × 360 points at
// display scale 3 (a 1920 × 1080 pixel screen). Changing the resolution to 720p changes its drawable
// and a captured frame to 1280 × 720, while every scene-space quantity is equal: the view's bounds,
// centre and transform, the OUT-004 placement, the text spec, the text box normalised to the picture
// and the compositor's layer stack. The same host keeps compositing (no restart). Also: the device
// budget clamp, a recording hold, the return to the device and persistence. Simulator results are
// never device evidence (OUT-003-T10 is).
import Compositor
import FrameCapture
import Metal
import PresentationLifecycle
import TextLayer
import UIKit
import XCTest
@testable import projectM_iOS

@MainActor
final class ExternalOutputResolutionAppTests: XCTestCase {
    private func waitUntil(_ description: String, timeout: TimeInterval = 10, _ condition: @escaping @MainActor () -> Bool) {
        let done = expectation(description: description)
        var fulfilled = false
        let timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { (_: Timer) in
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

    /// An external slot of `size` points at display `scale`, as the root of an off-screen window on the
    /// test host's scene (so a visual's frame loop runs), connected to `coordinator` as display "a".
    private func externalSlot(_ coordinator: ExternalDisplayCoordinator, size: CGSize, scale: CGFloat) throws -> (VisualSlotView, UIWindow) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("No window scene in the test host")
        }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 100_000, y: 0, width: size.width, height: size.height)
        window.windowLevel = .normal - 1
        let controller = ExternalDisplayViewController()
        controller.slot.traitOverrides.displayScale = scale
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        let slot = controller.slot
        coordinator.externalConnected(id: "a", slot: slot, geometry: slot.geometry, foreground: true)
        slot.layoutIfNeeded()
        return (slot, window)
    }

    private func visualizing(_ visual: UIView) -> ExternalDisplayCoordinator {
        let coordinator = ExternalDisplayCoordinator()
        let device = VisualSlotView(role: .device)
        device.frame = CGRect(x: 0, y: 0, width: 390, height: 845)
        coordinator.registerDeviceSlot(device)
        device.layoutIfNeeded()
        coordinator.show(visual)
        coordinator.visualizerActive(true)
        return coordinator
    }

    private func capture(_ source: any FrameCaptureSource) throws -> CapturedPixels {
        var result: CapturedPixels??
        source.captureFrame { (pixels: CapturedPixels?) in result = .some(pixels) }
        waitUntil("captured") { result != nil }
        return try XCTUnwrap(result ?? nil)
    }

    /// The text layer's canvas normalised to its picture: centre x, centre y, height.
    private func normalisedTextBox(_ rendering: TextRendering) -> [Double] {
        let pw = Double(rendering.pictureWidth), ph = Double(rendering.pictureHeight)
        return [(Double(rendering.x) + Double(rendering.width) / 2) / pw,
                (Double(rendering.y) + Double(rendering.height) / 2) / ph,
                Double(rendering.height) / ph]
    }

    /// Everything that lives in scene space (points or normalised), for equality before and after.
    private struct SceneSpace: Equatable {
        let bounds: CGRect
        let center: CGPoint
        let transform: CGAffineTransform
        let placement: ExternalOutputPlacement
        let spec: TextOverlaySpec
        let stack: LayerStack?
    }

    private func sceneSpace(_ host: TextVisualHost, _ slot: VisualSlotView) -> SceneSpace {
        SceneSpace(bounds: host.view.bounds, center: host.view.center, transform: host.view.transform,
                   placement: slot.placement, spec: host.text.spec, stack: host.compositor.appliedStack)
    }

    // MARK: - T06: the acceptance (OUT-003-S2)

    func testTheResolutionChangesOutputPixelsButNotSceneCoordinates() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try TextVisualHost.make(device: device, reader: nil, barCount: .b32)
        host.text.spec = TextOverlaySpec(message: "OUT-003")
        let coordinator = visualizing(host.view)
        let (slot, window) = try externalSlot(coordinator, size: CGSize(width: 640, height: 360), scale: 3)
        defer { host.pause(); coordinator.externalDisconnected(id: "a"); window.isHidden = true }
        XCTAssertTrue(host.view.superview === slot, "the visual is on the external slot")
        host.view.layoutIfNeeded()
        host.resume()

        // Native: the screen's 1920 × 1080 pixels.
        XCTAssertEqual(host.view.metalLayer.drawableSize, CGSize(width: 1920, height: 1080))
        XCTAssertEqual(coordinator.externalResolutionSummary, "mode=native scale=3.00 drawable=1920x1080 clamped=no")
        waitUntil("native text rendered") { host.text.lastRendering?.pictureWidth == 1920 }
        let nativeFrame = try capture(host)
        XCTAssertEqual([nativeFrame.width, nativeFrame.height], [1920, 1080])
        let nativeBox = normalisedTextBox(try XCTUnwrap(host.text.lastRendering))
        let before = sceneSpace(host, slot)
        let framesBefore = host.framesComposited

        // 720p, live: only the pixels change.
        coordinator.resolution = ExternalOutputResolution(mode: .hd720)
        host.view.layoutIfNeeded()
        XCTAssertEqual(host.view.metalLayer.drawableSize, CGSize(width: 1280, height: 720), "the drawable follows inside the call's layout")
        XCTAssertEqual(host.view.traitCollection.displayScale, 2, accuracy: 1e-9)
        XCTAssertEqual(slot.traitCollection.displayScale, 3, "the slot still reports the screen's scale")
        XCTAssertEqual(coordinator.externalResolutionSummary, "mode=720p scale=2.00 drawable=1280x720 clamped=no")
        waitUntil("720p text rendered") { host.text.lastRendering?.pictureWidth == 1280 }
        let lowFrame = try capture(host)
        XCTAssertEqual([lowFrame.width, lowFrame.height], [1280, 720], "a snapshot has the new pixel size")
        let lowBox = normalisedTextBox(try XCTUnwrap(host.text.lastRendering))

        XCTAssertEqual(sceneSpace(host, slot), before, "bounds, centre, transform, placement, text spec and layer stack are unchanged")
        for (a, b) in zip(nativeBox, lowBox) {
            XCTAssertEqual(a, b, accuracy: 0.006, "the text box in normalised picture coordinates is unchanged")
        }
        XCTAssertTrue(host.isRunning, "the visual was not restarted")
        XCTAssertGreaterThan(host.framesComposited, framesBefore, "the same host kept compositing")
        XCTAssertTrue(host.view.superview === slot)

        // Back to Native: the override is gone.
        coordinator.resolution = .native
        host.view.layoutIfNeeded()
        XCTAssertFalse(host.view.traitOverrides.contains(UITraitDisplayScale.self))
        XCTAssertEqual(host.view.metalLayer.drawableSize, CGSize(width: 1920, height: 1080))
    }

    // MARK: - T06: budget, hold, device return (plain view; the drawable rule is bounds × trait scale)

    func testTheDeviceBudgetClampsANative4KScreen() throws {
        let visual = UIView()
        let coordinator = visualizing(visual)
        coordinator.pixelBudget = ExternalPixelBudget(maxSide: 2560, maxPixels: 2560 * 1440)   // REC-014 compact
        let (slot, window) = try externalSlot(coordinator, size: CGSize(width: 1920, height: 1080), scale: 2)
        defer { window.isHidden = true }
        XCTAssertEqual(slot.resolvedOutput?.pixelWidth, 2560)
        XCTAssertEqual(slot.resolvedOutput?.pixelHeight, 1440)
        XCTAssertEqual(visual.traitCollection.displayScale * visual.bounds.width, 2560, accuracy: 0.5)
        XCTAssertEqual(visual.bounds.size, CGSize(width: 1920, height: 1080), "points unchanged")
        XCTAssertEqual(coordinator.externalResolutionSummary, "mode=native scale=1.33 drawable=2560x1440 clamped=yes")
    }

    func testARecordingHoldDefersTheChangeAndTheDeviceSlotRemovesTheOverride() throws {
        let visual = UIView()
        let coordinator = visualizing(visual)
        let (slot, window) = try externalSlot(coordinator, size: CGSize(width: 1920, height: 1080), scale: 1)
        defer { window.isHidden = true }
        XCTAssertFalse(visual.traitOverrides.contains(UITraitDisplayScale.self), "native: no override")

        coordinator.holdsPlacement = true
        coordinator.resolution = ExternalOutputResolution(mode: .custom, percent: 50)
        XCTAssertFalse(visual.traitOverrides.contains(UITraitDisplayScale.self), "deferred while a recording holds the placement")
        coordinator.holdsPlacement = false
        XCTAssertEqual(visual.traitCollection.displayScale, 0.5, accuracy: 1e-9, "applied when the hold ends")
        XCTAssertEqual(slot.resolvedOutput?.pixelWidth, 960)

        coordinator.externalDisconnected(id: "a")
        XCTAssertFalse(visual.traitOverrides.contains(UITraitDisplayScale.self), "back on the device: the device's own scale")
        XCTAssertNil(coordinator.externalResolutionSummary)
    }

    // MARK: - T09: persistence

    func testTheChoicePersistsAndReachesTheCoordinator() throws {
        let suite = "out003-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = ExternalDisplayCoordinator()
        let first = ExternalOutputSetting(defaults: defaults, external: coordinator)
        XCTAssertEqual(first.resolution, .native)
        XCTAssertNil(defaults.object(forKey: ExternalOutputSetting.resolutionKey), "nothing stored until changed")
        first.resolutionMode = .custom
        first.resolutionPercent = 33
        XCTAssertEqual(first.resolutionPercent, 50, "clamped to 50…100")
        XCTAssertEqual(coordinator.resolution, ExternalOutputResolution(mode: .custom, percent: 50))

        let other = ExternalDisplayCoordinator()
        let second = ExternalOutputSetting(defaults: defaults, external: other)
        XCTAssertEqual(second.resolution, ExternalOutputResolution(mode: .custom, percent: 50))
        XCTAssertEqual(other.resolution, second.resolution, "the stored choice is applied at launch")
        XCTAssertEqual(other.pixelBudget, ExternalOutputSetting.devicePixelBudget)

        defaults.set("8k", forKey: ExternalOutputSetting.resolutionKey)
        XCTAssertEqual(ExternalOutputSetting(defaults: defaults, external: ExternalDisplayCoordinator()).resolutionMode, .native,
                       "an unknown value reads the default")
    }
}
