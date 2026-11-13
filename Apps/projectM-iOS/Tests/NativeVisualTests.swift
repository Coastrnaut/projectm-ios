// NativeVisualTests.swift — VIS-001-T19, T28, VIS-002-T11: when a native spectrum replaces projectM,
// and the native visual's lifecycle (VIS-001-R12, R15, R16; VIS-002-R12, R13). The host tests need a Metal device (the
// simulator renders with the host GPU); they skip without one, never fail for that reason.
import Metal
import PresentationLifecycle
import VisualEffects
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class NativeVisualTests: XCTestCase {
    func testTheNativeVisualIsShownOnlyWhenChosenAvailableAndVisualizing() {
        for choice in VisualChoice.allCases {
            for available in [false, true] {
                for visualizing in [false, true] {
                    XCTAssertEqual(AppCoordinator.nativeVisualShown(choice: choice, hostAvailable: available, onVisualizer: visualizing),
                                   choice.isNative && available && visualizing, "\(choice) \(available) \(visualizing)")
                }
            }
        }
    }

    private func makeHost() throws -> NativeSpectrumHost {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        return try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32)
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

    /// FX-001-T17 (FX-001-R11 to R13): the host applies glow settings, and a glow that cannot be
    /// built leaves the circular spectrum running without it.
    func testHostAppliesGlowAndSurvivesAGlowFailure() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32)
        XCTAssertFalse(host.glowUnavailable)
        XCTAssertFalse(host.glowActive)
        XCTAssertEqual(host.view.accessibilityValue, "Glow off")
        host.glow = BloomParameters(enabled: true, intensity: 0.8, radius: 0.04, threshold: 0.5)
        XCTAssertTrue(host.glowActive, "the chain runs the bloom from the next frame")
        XCTAssertEqual(host.view.accessibilityValue, "Glow on")
        host.glow = BloomParameters(enabled: true, intensity: 0)
        XCTAssertFalse(host.glowActive, "intensity 0 draws directly (pass-through)")
        host.glow = BloomParameters(enabled: false, intensity: 1)
        XCTAssertFalse(host.glowActive)
        XCTAssertEqual(host.view.accessibilityValue, "Glow off")

        let failed = try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32,
                                                   glow: BloomParameters(enabled: true), forceGlowFailure: true)
        XCTAssertTrue(failed.glowUnavailable, "the visual exists without its glow (FX-001-R13)")
        XCTAssertFalse(failed.glowActive)
        XCTAssertEqual(failed.view.accessibilityValue, "Glow unavailable")
        failed.glow = BloomParameters(enabled: false)
        XCTAssertEqual(failed.view.accessibilityValue, "Glow off")
    }

    /// VIS-002-T11: the linear spectrum names itself and its orientation; the host switches styles
    /// in place (VIS-002-R12, R13; research VIS-002-D5).
    func testLinearHostNamesItselfAndSwitchesStyles() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, style: .linear(.vertical, spacing: 0.2), barCount: .b32)
        XCTAssertEqual(host.view.accessibilityLabel, "Linear Spectrum visualization")
        XCTAssertEqual(host.view.accessibilityIdentifier, "linearSpectrum")
        XCTAssertEqual(host.view.accessibilityValue, "Vertical, Glow off")
        try host.apply(style: .linear(.horizontal, spacing: 0.5))
        XCTAssertEqual(host.view.accessibilityValue, "Horizontal, Glow off")
        host.glow = BloomParameters(enabled: true, intensity: 0.8)
        XCTAssertEqual(host.view.accessibilityValue, "Horizontal, Glow on")
        XCTAssertTrue(host.glowActive, "the glow applies to the linear spectrum too (VIS-002-R10)")
        host.resume()
        XCTAssertTrue(host.isRunning)
        try host.apply(style: .circular)
        XCTAssertEqual(host.view.accessibilityIdentifier, "circularSpectrum")
        XCTAssertEqual(host.view.accessibilityValue, "Glow on")
        XCTAssertTrue(host.isRunning, "switching kinds keeps the loop running")
        host.barCount = .b128
        try host.apply(style: .linear(.vertical, spacing: 0))
        XCTAssertEqual(host.barCount, .b128, "the bar count carries over")
        host.pause()
        XCTAssertEqual(AppCoordinator.nativeVisualUnavailableMessage(for: .linearSpectrum),
                       "Linear Spectrum isn't available on this device. Showing projectM.")
        XCTAssertEqual(AppCoordinator.nativeVisualUnavailableMessage(for: .circularSpectrum),
                       "Circular Spectrum isn't available on this device. Showing projectM.")
    }
}
