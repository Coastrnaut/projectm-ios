// MotionModulationAppTests.swift — CAM-011-T08 (CAM-011-R2, R5, R8, R9, R12, S3): in the app, a binding from
// `audio.motion.pitch` drives the glow intensity from an injected motion source through `NativeSpectrumHost`'s frame
// evaluation; the sensor runs only while the binding exists and the app is active, at 30 Hz under a 30 fps power
// budget; Calibrate brings the binding to its middle. Deterministic: samples and frame times are injected (the
// simulator has no motion sensors). Needs a Metal device (the simulator renders with the host GPU); skips without one.
import Foundation
import Metal
import ParameterGraph
import VisualEffects
import VisualGenerators
import VisualParameters
import XCTest
@testable import projectM_iOS

/// A sampler the test drives by hand.
@MainActor
private final class ManualMotionSampler: MotionSampling {
    let isAvailable: Bool
    private(set) var handler: (@MainActor (MotionSample) -> Void)?
    private(set) var starts: [Double] = []
    private(set) var stops = 0

    init(available: Bool = true) { isAvailable = available }

    func start(rateHz: Double, handler: @escaping @MainActor (MotionSample) -> Void) {
        starts.append(rateHz)
        self.handler = handler
    }

    func stop() {
        stops += 1
        handler = nil
    }

    func send(pitch: Double, at time: UInt64) {
        handler?(MotionSample(pitch: pitch, roll: 0, yaw: 0, timeNanoseconds: time))
    }
}

@MainActor
final class MotionModulationAppTests: XCTestCase {
    private static let frame: UInt64 = 16_666_667
    private static let origin: UInt64 = 1_000_000_000

    private func defaults() -> UserDefaults {
        let name = "MotionModulationAppTests"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func frame(_ host: NativeSpectrumHost, at index: Int) {
        let bands: [Float] = [0.1, 0.1]
        bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
            host.applyModulation(bands: buffer, timeNanoseconds: Self.origin + UInt64(index) * Self.frame)
        }
    }

    func testPitchBindingDrivesTheGlowAndTheSensorFollowsDemand() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32,
                                               glow: BloomParameters(enabled: true, intensity: 0.2))
        let sampler = ManualMotionSampler()
        let motion = MotionModulationCoordinator(defaults: defaults(), sampler: sampler, frameCap: { () -> Int in 60 })
        motion.connect(host)
        XCTAssertFalse(motion.isSampling, "nothing reads motion: the sensor stays off")
        XCTAssertTrue(sampler.starts.isEmpty)

        let source = AudioFeatureSource.motion(.pitch)
        try host.bind(AudioFeatureBinding(source: source, target: VisualParameterIDs.bloomIntensity, outputStart: 0, outputEnd: 1))
        XCTAssertTrue(host.usesMotion)
        XCTAssertTrue(motion.isSampling)
        XCTAssertEqual(sampler.starts, [60], "60 Hz under the standard budget")
        XCTAssertEqual(source.inspectorName, "Tilt forward")
        XCTAssertEqual(AudioFeatureSource.motion(.shake).inspectorName, "Shake")

        let quarter: Double = MotionRange.medium.radians / 2   // tilted forward a quarter range: 0.75
        sampler.send(pitch: quarter, at: Self.origin)
        frame(host, at: 0)
        XCTAssertEqual(Double(host.effectiveGlow.intensity), 0.75, accuracy: 1e-4)
        XCTAssertEqual(host.glow.intensity, 0.2, "the manual intensity is unchanged")

        motion.calibrate()   // the current tilt becomes the middle
        sampler.send(pitch: quarter, at: Self.origin + Self.frame)
        frame(host, at: 1)
        XCTAssertEqual(Double(host.effectiveGlow.intensity), 0.5, accuracy: 1e-3)

        motion.setAppActive(false)   // background: the sensor stops
        XCTAssertFalse(motion.isSampling)
        XCTAssertEqual(sampler.stops, 1)
        motion.setAppActive(true)
        XCTAssertTrue(motion.isSampling)

        host.unbind(VisualParameterIDs.bloomIntensity)   // nothing reads motion again: the sensor stops
        XCTAssertFalse(host.usesMotion)
        XCTAssertFalse(motion.isSampling)
        XCTAssertEqual(sampler.stops, 2)
    }

    func testReadoutRateRangeAndUnavailableDevice() {
        let sampler = ManualMotionSampler()
        let store = defaults()
        let motion = MotionModulationCoordinator(defaults: store, sampler: sampler, frameCap: { () -> Int in 30 })
        XCTAssertEqual(motion.range, .medium)
        XCTAssertNil(store.string(forKey: MotionModulationCoordinator.rangeKey), "nothing stored until changed")
        motion.setReadoutOpen(true)   // Settings › Motion on screen
        XCTAssertEqual(sampler.starts, [30], "30 Hz under a 30 fps power budget")
        sampler.send(pitch: 0.3, at: Self.origin)
        XCTAssertGreaterThan(motion.readout.pitch, 0.5)
        sampler.send(pitch: -0.3, at: Self.origin + 50_000_000)
        XCTAssertGreaterThan(motion.readout.pitch, 0.5, "the readout refreshes at most every 100 ms")
        motion.calibrate()
        XCTAssertEqual(motion.readout.pitch, 0.5)
        motion.range = .wide
        XCTAssertEqual(store.string(forKey: MotionModulationCoordinator.rangeKey), "wide")
        XCTAssertEqual(motion.tracker.range, .wide)
        motion.setReadoutOpen(false)
        XCTAssertFalse(motion.isSampling)
        XCTAssertEqual(MotionModulationCoordinator(defaults: store, sampler: ManualMotionSampler()).range, .wide)

        let none = ManualMotionSampler(available: false)
        let unavailable = MotionModulationCoordinator(defaults: defaults(), sampler: none)
        unavailable.setReadoutOpen(true)
        XCTAssertFalse(unavailable.isAvailable)
        XCTAssertFalse(unavailable.isSampling)
        XCTAssertTrue(none.starts.isEmpty)
        XCTAssertEqual(unavailable.currentValues, .neutral, "no sensors: attitude 0.5, shake 0")
    }
}
