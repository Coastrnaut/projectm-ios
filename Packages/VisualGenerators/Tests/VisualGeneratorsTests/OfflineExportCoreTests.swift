// OfflineExportCoreTests.swift — REC-013-T04: the export's clock, audio source, fixture, sidecar and analysis driver
// (specs/240-rec-013-deterministic-offline-export; research REC-013-D1, D2, D4, D6). Plain Swift; runs on Linux.
import AnalysisFeatures
import Foundation
import VisualBandFeed
import VisualGenerators
import XCTest

final class OfflineExportCoreTests: XCTestCase {
    func testClockPutsFrameNAtNOverFps() {
        let c30 = OfflineFrameClock(fps: 30)
        XCTAssertEqual(c30.timeNanoseconds(frame: 0), 0)
        XCTAssertEqual(c30.timeNanoseconds(frame: 1), 33_333_333)
        XCTAssertEqual(c30.timeNanoseconds(frame: 30), 1_000_000_000)
        XCTAssertEqual(c30.samplePosition(frame: 1), 1_470)
        XCTAssertEqual(c30.samplePosition(frame: 60), 88_200)
        XCTAssertEqual(c30.frameCount(samples: 88_200), 60)       // 2 s × 30
        XCTAssertEqual(c30.frameCount(samples: 0), 0)
        let c60 = OfflineFrameClock(fps: 60)
        XCTAssertEqual(c60.samplePosition(frame: 1), 735)
        XCTAssertEqual(c60.frameCount(samples: 44_100), 60)
        XCTAssertEqual(c60.frameCount(samples: 44_100 + 300), 60)   // rounds to the nearest frame
        XCTAssertEqual(c60.frameCount(samples: 44_100 + 400), 61)
    }

    func testSourceReadsOnlyUpToTheExposedEnd() {
        let source = OfflinePCMSource(interleaved: (0..<20).map { (i: Int) -> Float in Float(i) })   // 10 frames
        var buffer = [Float](repeating: -1, count: 40)
        XCTAssertEqual(buffer.withUnsafeMutableBufferPointer { source.read(into: $0.baseAddress!, maxFrames: 20) }, 0)
        source.expose(upTo: 3)
        XCTAssertEqual(buffer.withUnsafeMutableBufferPointer { source.read(into: $0.baseAddress!, maxFrames: 20) }, 3)
        XCTAssertEqual(Array(buffer[0..<6]), [0, 1, 2, 3, 4, 5])
        source.expose(upTo: 2)   // never backwards
        source.expose(upTo: 50)  // clamped to the buffer
        XCTAssertEqual(buffer.withUnsafeMutableBufferPointer { source.read(into: $0.baseAddress!, maxFrames: 4) }, 4)
        XCTAssertEqual(buffer[0], 6)
        XCTAssertEqual(buffer.withUnsafeMutableBufferPointer { source.read(into: $0.baseAddress!, maxFrames: 20) }, 3)
        XCTAssertEqual(source.position, 10)
    }

    func testFixtureIsRepeatableAndSeedDependent() {
        let a = OfflineFixtureAudio.samples(seed: 1, seconds: 1)
        XCTAssertEqual(a.count, 88_200)
        XCTAssertEqual(a, OfflineFixtureAudio.samples(seed: 1, seconds: 1))
        XCTAssertNotEqual(a, OfflineFixtureAudio.samples(seed: 2, seconds: 1))
        XCTAssertTrue(a.allSatisfy { (x: Float) -> Bool in x.isFinite && abs(x) <= 1.5 })
        XCTAssertGreaterThan(a.map { (x: Float) -> Float in abs(x) }.max() ?? 0, 0.3)
    }

    func testManifestRoundTripAndComparison() throws {
        let glow = OfflineExportManifest.Glow(enabled: true, intensity: 0.5, radius: 0.2, threshold: 0.7)
        let m = OfflineExportManifest(visual: "circular", options: "64 bars", glow: glow, reduceFlashing: true, safetyProfile: "standard",
                                      width: 160, height: 90, fps: 30, seed: 7, audioSource: "fixture", audioSHA256: "ab",
                                      audioFrames: 88_200, gpu: "GPU", osVersion: "27.2", appVersion: "1.1",
                                      frameChecksums: ["00", "11"])
        XCTAssertEqual(m.frameCount, 2)
        let data = try m.encoded()
        XCTAssertEqual(try OfflineExportManifest.decode(data), m)
        XCTAssertEqual(try m.encoded(), data)   // sorted keys: byte-stable
        var other = m
        other.gpu = "Other"
        XCTAssertTrue(m.sameFrames(as: other))
        other.frameChecksums = ["00", "12"]
        XCTAssertFalse(m.sameFrames(as: other))
        XCTAssertEqual(OfflineExportManifest.hex([0x00, 0xAB, 0x0F]), "00ab0f")
    }

    /// Two drivers on the same audio see identical frames; other audio gives other bands (D2).
    func testDriverIsDeterministicPerFrame() throws {
        let audio = OfflineFixtureAudio.samples(seed: 3, seconds: 1)
        let clock = OfflineFrameClock(fps: 30)
        let a = try OfflineAnalysisDriver(interleaved: audio, barCount: .b64)
        let b = try OfflineAnalysisDriver(interleaved: audio, barCount: .b64)
        let c = try OfflineAnalysisDriver(interleaved: OfflineFixtureAudio.samples(seed: 4, seconds: 1).map { (x: Float) -> Float in x * 0.3 },
                                          barCount: .b64)
        var differs = false
        var events = 0
        for n in 0..<clock.frameCount(samples: a.source.frameCount) {
            let s = clock.samplePosition(frame: n)
            let fa = a.advance(toSample: s)
            let fb = b.advance(toSample: s)
            let fc = c.advance(toSample: s)
            XCTAssertEqual(fa.bands, fb.bands, "frame \(n)")
            XCTAssertEqual(fa.mono, fb.mono, "frame \(n)")
            XCTAssertEqual(fa.stereo, fb.stereo, "frame \(n)")
            XCTAssertEqual(fa.kickEnvelope, fb.kickEnvelope, "frame \(n)")
            XCTAssertEqual(fa.events.map(\.kind), fb.events.map(\.kind), "frame \(n)")
            XCTAssertEqual(a.source.position, s)
            events += fa.events.count
            if fa.bands != fc.bands { differs = true }
        }
        XCTAssertTrue(differs)
        XCTAssertGreaterThan(events, 0)
        XCTAssertEqual(a.droppedEvents, 0)
        XCTAssertGreaterThan(a.advance(toSample: 44_100).bands.max() ?? 0, 0)
    }
}
