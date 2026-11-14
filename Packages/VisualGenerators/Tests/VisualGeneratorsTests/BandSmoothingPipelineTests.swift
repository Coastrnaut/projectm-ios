// BandSmoothingPipelineTests.swift — ANL-003-T04: a synthetic tone switched on and off through the
// real band path (SpectrumBandFeed: ANL-001 spectra → ANL-002 bands → decibel normalization, the
// live analyzer's settings) and ANL-003's smoother at 60 fps (spec User Story 2 scenario 5,
// ANL-003-S4). The raw band ramps over the analysis window, so the bounds come from its own
// crossings. Frame intervals are injected; nothing reads a clock.
import Foundation
import XCTest
import AnalysisFeatures
import AudioCore
@testable import VisualBandFeed
@testable import VisualGenerators

final class BandSmoothingPipelineTests: XCTestCase {
    private static let sampleRate = 44_100
    private static let framesPerDisplayFrame = 735          // 60 fps at 44.1 kHz
    private static let interval = 1.0 / 60.0
    private static let leadSeconds = 0.5
    private static let toneSeconds = 1.0
    private static let tailSeconds = 1.0

    /// Silence, a 1 kHz sine (amplitude 0.5), silence; stereo interleaved.
    private func fixture() throws -> [Float] {
        let lead = [Float](repeating: 0, count: 2 * Int(Double(Self.sampleRate) * Self.leadSeconds))
        let tone: [Float] = try BandFeedFixture.sine(1_000, amplitude: 0.5, seconds: Self.toneSeconds)
        let tail = [Float](repeating: 0, count: 2 * Int(Double(Self.sampleRate) * Self.tailSeconds))
        return lead + tone + tail
    }

    /// Raw and smoothed values of `band`, one pair per display frame.
    private func run(times: SmoothingTimes, band: Int) throws -> (raw: [Float], smoothed: [Float]) {
        let samples = try fixture()
        let feed = try SpectrumBandFeed(barCount: .b64)
        let smoother = BandSmoother(times: times)
        let chunk = 2 * Self.framesPerDisplayFrame
        var raw: [Float] = []
        var smoothed: [Float] = []
        var start = 0
        while start + chunk <= samples.count {
            let slice = Array(samples[start..<(start + chunk)])
            feed.pull(from: ArrayPCMReader(slice))
            let bands: UnsafeBufferPointer<Float> = feed.bands
            let output = smoother.update(target: bands.baseAddress!, count: bands.count, frameInterval: Self.interval, generation: 1)
            raw.append(bands[band])
            smoothed.append(output[band])
            start += chunk
        }
        return (raw, smoothed)
    }

    func testToneOnAndOffFollowsAttackAndReleaseThroughTheRealBandPath() throws {
        let attack = 0.1
        let release = 0.5
        let band = try BandFeedFixture.expectedBand(1_000, count: .b64)
        let (raw, smoothed) = try run(times: SmoothingTimes(attackSeconds: attack, releaseSeconds: release), band: band)
        let dt = Self.interval
        func time(_ frame: Int) -> Double { Double(frame + 1) * dt }   // end of the frame's interval

        // The tone's steady raw value: the last 300 ms of the on-period.
        let toneEndFrame: Int = Int(((Self.leadSeconds + Self.toneSeconds) / dt).rounded(.down)) - 1
        let steadyStart: Int = toneEndFrame - 18
        let steady: ArraySlice<Float> = raw[steadyStart...toneEndFrame]
        let steadyMin: Float = try XCTUnwrap(steady.min())
        let steadyMax: Float = try XCTUnwrap(steady.max())
        XCTAssertGreaterThan(steadyMin, 0.5, "the tone lights its band")
        XCTAssertLessThan(steadyMax / steadyMin, 1.01, "the raw band is steady while the tone plays")

        // Attack: the last raw zero before the tone, and the first frame from which raw stays ≥ min.
        let lastZero: Int = try XCTUnwrap(raw[0...toneEndFrame].lastIndex(where: { (v: Float) -> Bool in v == 0 }))
        let steadyFrom: Int = try XCTUnwrap((lastZero...toneEndFrame).first { (k: Int) -> Bool in
            raw[k...toneEndFrame].allSatisfy { (v: Float) -> Bool in v >= steadyMin }
        })
        let upGoal: Float = 0.9 * steadyMin
        let upFrame: Int = try XCTUnwrap((lastZero...toneEndFrame).first { (k: Int) -> Bool in smoothed[k] >= upGoal })
        let upTime: Double = time(upFrame) - time(lastZero)
        // y ≤ max·(1 − 0.1^(t/τ)) from the last zero, so reaching 0.9·min takes at least this long:
        let ratio: Double = Double(upGoal) / Double(steadyMax)
        let earliestUp: Double = attack * log(1 - ratio) / log(0.1)
        let latestUp: Double = time(steadyFrom) - time(lastZero) + attack + dt
        XCTAssertGreaterThanOrEqual(upTime, earliestUp - 1e-9)
        XCTAssertLessThanOrEqual(upTime, latestUp + 1e-9)
        XCTAssertGreaterThanOrEqual(upTime, attack - dt, "not faster than the attack (one frame of window ramp)")

        // Release: the last frame the raw band is steady, and the first from which it stays 0.
        let lastSteady: Int = try XCTUnwrap((steadyFrom..<raw.count).last { (k: Int) -> Bool in
            raw[steadyFrom...k].allSatisfy { (v: Float) -> Bool in v >= steadyMin }
        })
        let held: Float = smoothed[lastSteady]
        let silentFrom: Int = try XCTUnwrap((lastSteady..<raw.count).first { (k: Int) -> Bool in
            raw[k...].allSatisfy { (v: Float) -> Bool in v == 0 }
        })
        let downGoal: Float = 0.1 * held
        let downFrame: Int = try XCTUnwrap((lastSteady..<smoothed.count).first { (k: Int) -> Bool in smoothed[k] <= downGoal })
        let downTime: Double = time(downFrame) - time(lastSteady)
        let latestDown: Double = time(silentFrom) - time(lastSteady) + release + dt
        XCTAssertGreaterThanOrEqual(downTime, release - 1e-9, "y ≥ held·0.1^(t/τ): never faster than the release")
        XCTAssertLessThanOrEqual(downTime, latestDown + 1e-9)

        let upMs: Double = upTime * 1_000
        let downMs: Double = downTime * 1_000
        let rampUpMs: Double = (time(steadyFrom) - time(lastZero)) * 1_000
        let rampDownMs: Double = (time(silentFrom) - time(lastSteady)) * 1_000
        print("ANL-003 pipeline: band \(band), steady \(steadyMin)…\(steadyMax); raw ramps up \(rampUpMs) ms, down \(rampDownMs) ms; "
              + "smoothed 90 % up after \(upMs) ms (attack 100), 10 % down after \(downMs) ms (release 500)")
    }

    func testInstantSmoothingLeavesTheRealBandsUnchanged() throws {
        let band = try BandFeedFixture.expectedBand(1_000, count: .b64)
        let (raw, smoothed) = try run(times: .instant, band: band)
        XCTAssertEqual(raw, smoothed, "Instant (the default) keeps today's bars bit for bit")
        XCTAssertTrue(raw.contains { (v: Float) -> Bool in v > 0.5 })
    }
}
