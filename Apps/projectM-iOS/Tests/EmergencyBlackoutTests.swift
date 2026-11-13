// EmergencyBlackoutTests.swift — SHOW-014-T07: the emergency button's action blacks out at once, and
// restore resumes the previous scene: the same visual view in the same slot, never re-placed, the
// visual running throughout with its settings unchanged (SHOW-014-R7, S2). A real native visual
// (NativeSpectrumHost) under the real coordinator; skipped without a Metal device. The fade is driven
// with fake frame times; nothing reads the wall clock. Simulator results are never device evidence.
import Metal
import PresentationLifecycle
import UIKit
import VisualEffects
import XCTest
@testable import projectM_iOS

@MainActor
final class EmergencyBlackoutTests: XCTestCase {
    private let dt = 1.0 / 60

    private func slot(_ role: VisualSlotView.Role, width: CGFloat, height: CGFloat) -> VisualSlotView {
        let slot = VisualSlotView(role: role)
        slot.frame = CGRect(x: 0, y: 0, width: width, height: height)
        slot.layoutIfNeeded()
        return slot
    }

    private func runningHost() throws -> NativeSpectrumHost {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32,
                                               glow: BloomParameters(enabled: true, intensity: 0.6, radius: 0.03, threshold: 0.4))
        host.resume()
        return host
    }

    private func advance(_ coordinator: ExternalDisplayCoordinator, seconds: Double) {
        for _ in 0..<Int((seconds / dt).rounded()) { coordinator.advanceFrame(frameTime: dt) }
    }

    /// One emergency blackout and a restore; checks the scene is the same at every step.
    private func cycle(_ coordinator: ExternalDisplayCoordinator, host: NativeSpectrumHost, holder: VisualSlotView,
                       file: StaticString = #filePath, line: UInt = #line) {
        let placements = coordinator.placements
        let glow = host.glow
        XCTAssertTrue(coordinator.blackoutPhase.offersEmergencyBlackout, "the button is shown", file: file, line: line)

        EmergencyBlackoutButton.trigger(coordinator)
        XCTAssertTrue(holder.isOutputBlack, "black before the action returns (OUT-010-R2)", file: file, line: line)
        XCTAssertFalse(coordinator.blackoutPhase.offersEmergencyBlackout, "the button hides: a second tap cannot restore", file: file, line: line)
        XCTAssertTrue(coordinator.blackoutPhase.offersRestore, file: file, line: line)
        XCTAssertTrue(host.isRunning, "the visual keeps drawing while black", file: file, line: line)

        EmergencyBlackoutButton.trigger(coordinator)   // a repeated emergency tap (or B) changes nothing
        XCTAssertEqual(coordinator.blackoutPhase, .blackedOut, file: file, line: line)

        coordinator.setBlackout(false)                  // the badge's Restore
        advance(coordinator, seconds: 1.1)
        XCTAssertEqual(coordinator.blackoutPhase, .live, file: file, line: line)
        XCTAssertFalse(holder.isOutputBlack, file: file, line: line)
        XCTAssertEqual(holder.coverOpacity, 0, "fully restored", file: file, line: line)
        XCTAssertTrue(host.view.superview === holder, "the same view in the same slot", file: file, line: line)
        XCTAssertEqual(coordinator.placements, placements, "never re-placed: the previous scene, not a new one", file: file, line: line)
        XCTAssertTrue(host.isRunning, "still running after restore", file: file, line: line)
        XCTAssertEqual(host.glow, glow, "its settings are unchanged", file: file, line: line)
    }

    func testTheEmergencyBlackoutOnTheDeviceRestoresTheSameRunningVisual() throws {
        let host = try runningHost()
        let coordinator = ExternalDisplayCoordinator()
        coordinator.usesDisplayLink = false
        let device = slot(.device, width: 200, height: 400)
        coordinator.registerDeviceSlot(device)
        coordinator.show(host.view)
        coordinator.visualizerActive(true)
        XCTAssertTrue(host.view.superview === device)
        cycle(coordinator, host: host, holder: device)
        host.pause()
    }

    func testTheEmergencyBlackoutOnAnExternalDisplayRestoresTheSameRunningVisual() throws {
        let host = try runningHost()
        let coordinator = ExternalDisplayCoordinator()
        coordinator.usesDisplayLink = false
        let device = slot(.device, width: 200, height: 400)
        let external = slot(.external, width: 1920, height: 1080)
        coordinator.registerDeviceSlot(device)
        coordinator.show(host.view)
        coordinator.visualizerActive(true)
        coordinator.externalConnected(id: "a", slot: external, geometry: ExternalDisplayGeometry(width: 1920, height: 1080, scale: 1),
                                      foreground: true)
        XCTAssertTrue(host.view.superview === external)
        cycle(coordinator, host: host, holder: external)
        XCTAssertTrue(device.subviews.isEmpty, "never moved to the device (no preview)")
        host.pause()
    }
}
