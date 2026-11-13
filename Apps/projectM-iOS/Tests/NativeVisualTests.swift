// NativeVisualTests.swift — VIS-001-T19, T28: when the circular spectrum replaces projectM, and the
// native visual's lifecycle (VIS-001-R12, R15, R16). The host tests need a Metal device (the
// simulator renders with the host GPU); they skip without one, never fail for that reason.
import Metal
import PresentationLifecycle
import XCTest
@testable import projectM_iOS

@MainActor
final class NativeVisualTests: XCTestCase {
    func testTheNativeVisualIsShownOnlyWhenChosenAvailableAndVisualizing() {
        for choice in [VisualChoice.projectM, .circularSpectrum] {
            for available in [false, true] {
                for visualizing in [false, true] {
                    XCTAssertEqual(AppCoordinator.nativeVisualShown(choice: choice, hostAvailable: available, onVisualizer: visualizing),
                                   choice == .circularSpectrum && available && visualizing, "\(choice) \(available) \(visualizing)")
                }
            }
        }
    }

    private func makeHost() throws -> CircularSpectrumHost {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        return try CircularSpectrumHost.make(device: device, reader: nil, barCount: .b32)
    }

    func testHostFollowsPresentationAndPause() throws {
        let host = try makeHost()
        let registry = PresentationResourceRegistry()
        host.presentationResources.forEach(registry.register)
        XCTAssertEqual(registry.registeredCount, 1)
        host.resume()
        XCTAssertTrue(host.isRunning, "resumed: frame loop and analysis on")
        registry.setCanPresent(false)
        XCTAssertFalse(host.isRunning, "suspended before the call returns (PERF-011)")
        XCTAssertTrue(host.isSuspended)
        registry.setCanPresent(true)
        XCTAssertTrue(host.isRunning, "resumes: it was not paused")
        host.pause()
        host.pause()
        XCTAssertFalse(host.isRunning, "paused (idempotent)")
        registry.setCanPresent(false)
        registry.setCanPresent(true)
        XCTAssertFalse(host.isRunning, "a pause survives a presentation round trip")
        host.resume()
        host.resume()
        XCTAssertTrue(host.isRunning)
        host.pause()
    }

    func testHostIsOneAccessibleElement() throws {
        let host = try makeHost()
        XCTAssertTrue(host.view.isAccessibilityElement)
        XCTAssertEqual(host.view.accessibilityLabel, "Circular Spectrum visualization")
        XCTAssertEqual(host.view.accessibilityIdentifier, "circularSpectrum")
    }
}
