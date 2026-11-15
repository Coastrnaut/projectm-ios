// ExternalOutputModeAppTests.swift — OUT-006-T06, T07 (specs/261-out-006-output-mirroring; contract C2-C4).
// T06: the acceptance "Toggle changes output routing without duplicating audio capture". A real AppCoordinator
// (its own defaults suite and ExternalDisplayCoordinator) gets a device slot, a stand-in visual and an
// external stand-in display built like the app's (`ExternalDisplayViewController` in an off-screen window); a
// real MED-010 logo layer sits on a real compositor. Toggling the mode must change what is routed to the
// external output (the logo layer's effective opacity; the external slot holds only the visual) while the one
// audio pipeline stays the same objects with no new session. T07: the preference. Simulator results are
// never device evidence (OUT-006-T10 is the device check).
import AudioCore
import Compositor
import ImageLayer
import Metal
import PresentationLifecycle
import UIKit
import XCTest
@testable import projectM_iOS

/// A layer that draws nothing (the stack under the logo).
private final class EmptyLayer: LayerSource {
    let layerName = "empty"
    let fallback = LayerFallback.transparent
    func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {}
    func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                audio: LayerAudioContext) throws(LayerSourceError) { throw .notReady }
}

/// What must not change when the mode changes: the one capture and its analysis pipeline.
@MainActor
private struct PipelineWitness: Equatable {
    var manager: ObjectIdentifier
    var normalizedOutput: ObjectIdentifier
    var analysisTap: ObjectIdentifier?
    var state: String
    var transitions: Int
    var sourceStarts: Int

    init(_ coordinator: AppCoordinator) {
        manager = ObjectIdentifier(coordinator.manager)
        normalizedOutput = ObjectIdentifier(coordinator.manager.normalizedOutput as AnyObject)
        analysisTap = coordinator.manager.analysisTap.map { (tap: any NormalizedPCMReader) -> ObjectIdentifier in
            ObjectIdentifier(tap as AnyObject)
        }
        state = String(describing: coordinator.manager.state)
        transitions = coordinator.manager.transitions.count
        sourceStarts = coordinator.sourceStarts
    }
}

@MainActor
final class ExternalOutputModeAppTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let name = "out006-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return defaults
    }

    private func scene() throws -> UIWindowScene {
        try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { (s: UIScene) -> UIWindowScene? in s as? UIWindowScene }.first)
    }

    /// An external stand-in display: an off-screen 1920 × 1080 window holding the app's external root.
    private func externalWindow(_ scene: UIWindowScene) -> (UIWindow, VisualSlotView) {
        let controller = ExternalDisplayViewController()
        controller.slot.traitOverrides.displayScale = 1
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 100_000, y: 0, width: 1920, height: 1080)
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        addTeardownBlock { @MainActor in window.isHidden = true }
        return (window, controller.slot)
    }

    private func logoLayer(_ coordinator: AppCoordinator) throws -> LogoLayerSource {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
        let compositor = try Compositor(device: device)
        var stack = LayerStack()
        try stack.add(LayerDescriptor(kind: .circularSpectrum))
        try compositor.apply(stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in EmptyLayer() }
        addTeardownBlock { @MainActor in _ = compositor }
        return try XCTUnwrap(coordinator.logo.attach(to: compositor))
    }

    /// T06 (OUT-006-R2 to R6, S1, S2, S4): the acceptance.
    func testTheToggleChangesOutputRoutingWithoutDuplicatingAudioCapture() throws {
        let external = ExternalDisplayCoordinator()
        let coordinator = AppCoordinator(defaults: try defaults(), externalDisplay: external)
        let layer = try logoLayer(coordinator)
        let stored: Double = coordinator.logo.placement.opacity
        XCTAssertGreaterThan(stored, 0)

        let device = VisualSlotView(role: .device)
        device.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let visual = UIView()
        external.registerDeviceSlot(device)
        external.show(visual)
        external.visualizerActive(true)
        let before = PipelineWitness(coordinator)

        let (_, slot) = externalWindow(try scene())
        external.externalConnected(id: "stand-in", slot: slot, geometry: slot.geometry, foreground: true)
        XCTAssertTrue(visual.superview === slot, "the visual is on the external display")
        XCTAssertEqual(slot.subviews.map { (v: UIView) -> ObjectIdentifier in ObjectIdentifier(v) }, [ObjectIdentifier(visual)],
                       "the external window holds only the visual (OUT-006-R4)")
        XCTAssertEqual(external.outputModeSummary, "mode=sameScene target=external overlays=shown externalViews=1")
        XCTAssertEqual(layer.placement.opacity, stored, "Same scene: the logo is drawn on the display")

        for _ in 0..<2 {
            coordinator.externalOutput.outputMode = .clean
            XCTAssertEqual(external.outputModeSummary, "mode=clean target=external overlays=hidden externalViews=1")
            XCTAssertEqual(layer.placement.opacity, 0, "Clean output: the logo draws nothing, inside the call")
            XCTAssertTrue(coordinator.logo.outputSuppressed)
            XCTAssertTrue(visual.superview === slot, "a mode change never moves the visual (OUT-006-R5)")
            XCTAssertTrue(device.subviews.isEmpty, "nothing is drawn twice")
            coordinator.externalOutput.outputMode = .sameScene
            XCTAssertEqual(layer.placement.opacity, stored)
            XCTAssertTrue(visual.superview === slot)
        }
        coordinator.externalOutput.outputMode = .clean
        XCTAssertEqual(coordinator.logo.placement.opacity, stored, "the stored placement never changes")

        // OUT-006-R3: back on the device the logo shows, whatever the mode.
        external.externalDisconnected(id: "stand-in")
        XCTAssertTrue(visual.superview === device)
        XCTAssertEqual(layer.placement.opacity, stored)
        XCTAssertEqual(external.outputModeSummary, "mode=clean target=device overlays=shown externalViews=0")
        external.externalConnected(id: "stand-in-2", slot: slot, geometry: slot.geometry, foreground: true)
        XCTAssertEqual(layer.placement.opacity, 0, "a reconnect in Clean output leaves the logo out again")
        let late = try logoLayer(coordinator)
        XCTAssertEqual(late.placement.opacity, 0, "a layer attached meanwhile follows the routing")

        // OUT-006-R6, S2: exactly one capture and one analysis pipeline, untouched.
        XCTAssertEqual(PipelineWitness(coordinator), before, "same capture, normalized output and analysis tap; no new session")
    }

    /// OUT-006-R5: a running recording's placement hold does not defer the mode (one render).
    func testTheModeAppliesLiveWhileARecordingHoldsThePlacement() throws {
        let external = ExternalDisplayCoordinator()
        var routed: [Bool] = []
        external.onSceneOverlaysChange = { (routes: Bool) -> Void in routed.append(routes) }
        let device = VisualSlotView(role: .device)
        device.frame = CGRect(x: 0, y: 0, width: 200, height: 400)
        let slot = VisualSlotView(role: .external)
        slot.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let visual = UIView()
        external.registerDeviceSlot(device)
        external.show(visual)
        external.visualizerActive(true)
        external.outputMode = .clean
        XCTAssertEqual(routed, [], "on the device nothing changes")
        external.externalConnected(id: "a", slot: slot, geometry: ExternalDisplayGeometry(width: 1920, height: 1080, scale: 1),
                                   foreground: true)
        XCTAssertEqual(routed, [false])
        external.holdsPlacement = true
        external.outputMode = .sameScene
        XCTAssertEqual(routed, [false, true], "applied inside the call during the hold")
        XCTAssertTrue(visual.superview === slot)
        external.outputMode = .sameScene
        XCTAssertEqual(routed, [false, true], "reported only on change")
    }

    /// T07 (OUT-006-R1, R7, S3): the choice persists; absent or unknown reads Same scene.
    func testTheOutputModePersistsAndReadsSafely() throws {
        let defaults = try defaults()
        let external = ExternalDisplayCoordinator()
        let setting = ExternalOutputSetting(defaults: defaults, external: external)
        XCTAssertEqual(setting.outputMode, .sameScene)
        XCTAssertNil(defaults.object(forKey: ExternalOutputSetting.outputModeKey), "nothing stored until changed")
        setting.outputMode = .clean
        XCTAssertEqual(defaults.string(forKey: ExternalOutputSetting.outputModeKey), "clean")
        XCTAssertEqual(external.outputMode, .clean, "applied live")
        let relaunched = ExternalDisplayCoordinator()
        XCTAssertEqual(ExternalOutputSetting(defaults: defaults, external: relaunched).outputMode, .clean, "persisted")
        XCTAssertEqual(relaunched.outputMode, .clean, "applied at launch")
        defaults.set("mirror", forKey: ExternalOutputSetting.outputModeKey)
        XCTAssertEqual(ExternalOutputSetting(defaults: defaults, external: ExternalDisplayCoordinator()).outputMode, .sameScene)
        XCTAssertTrue(ExternalOutputSetting.keys.contains("settings.externalDisplay.outputMode"), "device-local, excluded from backup")
        XCTAssertEqual(ExternalOutputSetting.title(.sameScene), "Same scene")
        XCTAssertEqual(ExternalOutputSetting.title(.clean), "Clean output")
    }
}
