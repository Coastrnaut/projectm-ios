// OutputFramePacingAppTests.swift — OUT-013-T09 (OUT-013-S4) and T11 (specs/281-out-013-frame-pacing): the roadmap
// acceptance, "Slow external output does not stall primary display render loop", in the app. A real Text visual
// (compositor) sits on an external `VisualSlotView` (the OUT-003 stand-in pattern: an off-screen window on the test
// host's scene). The slow output is injected: the visual's frame completions are held (DEBUG `holdCompletions`), so
// its GPU never "finishes". A device-side probe (a display link on the main thread, standing in for the HUD and frame
// meter updates) must keep ticking while the external output is stuck, and the output's frames in flight and held
// completions must stay at the bound. The hard assertions are counts; the probe's gap bound is a loose smoke check.
// Simulator results are never device evidence (OUT-013-T12 is).
import ANGLERendering
import FrameTiming
import Metal
import QuartzCore
import UIKit
import XCTest
@testable import projectM_iOS

/// A main-thread display link that records its ticks: the device's own loop.
@MainActor
private final class DeviceLoopProbe: NSObject {
    private(set) var ticks = 0
    private(set) var maxGap: CFTimeInterval = 0
    private var last: CFTimeInterval?
    private var link: CADisplayLink?

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        if let last { maxGap = max(maxGap, link.timestamp - last) }
        last = link.timestamp
        ticks += 1
    }
}

@MainActor
final class OutputFramePacingAppTests: XCTestCase {
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

    /// An external slot as the root of an off-screen window on the test host's scene, connected as display "a".
    private func externalSlot(_ coordinator: ExternalDisplayCoordinator) throws -> (VisualSlotView, UIWindow) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("No window scene in the test host")
        }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 100_000, y: 0, width: 640, height: 360)
        window.windowLevel = .normal - 1
        let controller = ExternalDisplayViewController()
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

    // MARK: - T09: the acceptance (OUT-013-S4)

    func testASlowExternalOutputDoesNotStallTheDeviceLoop() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try TextVisualHost.make(device: device, reader: nil, barCount: .b32)
        let coordinator = visualizing(host.view)
        let (slot, window) = try externalSlot(coordinator)
        let probe = DeviceLoopProbe()
        defer { probe.stop(); host.pause(); coordinator.externalDisconnected(id: "a"); window.isHidden = true }
        XCTAssertTrue(host.view.superview === slot, "the visual is on the external slot")
        host.view.layoutIfNeeded()
        host.outputPacing.holdCompletions = true   // the external output never finishes a frame
        host.resume()
        probe.start()

        waitUntil("the stuck output drops ticks while the device loop runs") {
            host.outputPacing.counts.droppedInFlight >= 20 && probe.ticks >= 30
        }
        let stuck: OutputPacingCounts = host.outputPacing.counts
        XCTAssertEqual(stuck.begun, 2, "two frames went out, then nothing was queued")
        XCTAssertEqual(stuck.inFlight, 2)
        XCTAssertEqual(stuck.maxInFlight, 2)
        XCTAssertEqual(host.outputPacing.heldCount, 2, "held completions never exceed the bound")
        XCTAssertLessThan(probe.maxGap, 0.25, "the device loop kept ticking (smoke bound)")

        // Still stuck later: the counts that matter do not grow; only the drop count does.
        let probeTicks: Int = probe.ticks
        waitUntil("more device ticks") { probe.ticks >= probeTicks + 20 }
        let later: OutputPacingCounts = host.outputPacing.counts
        XCTAssertEqual(later.begun, 2)
        XCTAssertEqual(later.inFlight, 2)
        XCTAssertEqual(host.outputPacing.heldCount, 2)
        XCTAssertGreaterThan(later.droppedInFlight, stuck.droppedInFlight, "drops are counted")

        // The output recovers: frames flow again.
        host.outputPacing.holdCompletions = false
        host.outputPacing.releaseHeldCompletions()
        waitUntil("frames resume") { host.outputPacing.counts.begun >= 6 }
        XCTAssertLessThanOrEqual(host.outputPacing.counts.maxInFlight, 2)
    }

    // MARK: - T11: the link follows the view's screen (US2)

    func testTheFrameLinkFollowsTheScreenOfItsWindow() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try TextVisualHost.make(device: device, reader: nil, barCount: .b32)
        host.resume()   // not in a window yet: the main screen's link
        let link: ScreenDisplayLink = try XCTUnwrap(host.frameLink)
        XCTAssertNil(link.screenIdentity)
        let range: CAFrameRateRange = link.preferredFrameRateRange
        link.isPaused = true

        let coordinator = visualizing(host.view)
        let (slot, window) = try externalSlot(coordinator)
        defer { host.pause(); coordinator.externalDisconnected(id: "a"); window.isHidden = true }
        XCTAssertTrue(host.view.superview === slot)
        let scene: UIWindowScene = try XCTUnwrap(window.windowScene)
        XCTAssertTrue(host.frameLink === link, "one link object for the visual's life")
        XCTAssertEqual(link.screenIdentity, ObjectIdentifier(scene.screen), "rebuilt on the slot window's screen")
        XCTAssertEqual(link.builds, 2)
        XCTAssertEqual(link.preferredFrameRateRange, range, "FR-049's range is kept")
        XCTAssertTrue(link.isPaused, "the pause state is kept")
        XCTAssertFalse(link.follow(host.view), "the same screen again: nothing is rebuilt")
        XCTAssertEqual(link.builds, 2)
        link.isPaused = false
    }
}
