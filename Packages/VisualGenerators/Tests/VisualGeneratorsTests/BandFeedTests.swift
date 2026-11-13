// BandFeedTests.swift — VIS-001-T14: from an AUD-016 sine through SpectrumStream → BandReducer →
// the generator's input, the expected band is the one lit (VIS-001-R14, S4), and LiveBandAnalyzer
// publishes it from a real analysis tap through the analysis event bus (ANL-016-R16, S6). Waits use a 30 s ceiling, never a frame
// or time budget.
import Foundation
import XCTest
import AudioCore
import AnalysisFeatures
@testable import VisualBandFeed
@testable import VisualGenerators

/// A NormalizedPCMReader over a fixed stereo buffer (the role the analysis tap plays in the app).
final class ArrayPCMReader: NormalizedPCMReader, @unchecked Sendable {
    private let samples: [Float]
    private var position = 0   // stereo frames
    init(_ samples: [Float]) { self.samples = samples }
    func read(into dst: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int {
        let frames = min(maxFrames, samples.count / 2 - position)
        guard frames > 0 else { return 0 }
        samples.withUnsafeBufferPointer { dst.update(from: $0.baseAddress! + 2 * position, count: 2 * frames) }
        position += frames
        return frames
    }
}

enum BandFeedFixture {
    static let frequencies: [Double] = [100, 440, 1_000, 1_500]   // the AUD-016 catalog's sines

    /// One second of a stereo sine at 44.1 kHz from the AUD-016 tone generator.
    static func sine(_ frequency: Double, amplitude: Double = 0.5, seconds: Double = 1) throws -> [Float] {
        let generator = try ToneGenerator(signal: .sine(SineTone(frequency: frequency, amplitude: amplitude)),
                                          format: ToneFormat(sampleRate: 44_100, channels: 2))
        return generator.interleaved(frames: Int(44_100 * seconds))
    }

    static let binWidth = 44_100.0 / 2_048

    static func layout(_ count: SpectrumBarCount) throws -> BandLayout {
        try BandReducer(sampleRate: 44_100).layout(bandCount: BandCount(rawValue: count.rawValue)!, size: .n2048)
    }

    /// The band containing the sine's frequency (the published ANL-002 edges).
    static func expectedBand(_ frequency: Double, count: SpectrumBarCount) throws -> Int {
        try XCTUnwrap(layout(count).band(containingFrequency: frequency))
    }

    /// Whether the band's frequency range comes within one 2,048-point bin (21.5 Hz) of `frequency`.
    static func band(_ b: Int, isWithinOneBinOf frequency: Double, count: SpectrumBarCount) throws -> Bool {
        let l = try layout(count)
        return l.lowerEdge(ofBand: b) <= frequency + binWidth && l.upperEdge(ofBand: b) >= frequency - binWidth
    }
}

final class BandFeedTests: XCTestCase {
    func testEachReferenceSineLightsItsOwnBandAsTheLongestBar() throws {
        let feed = try SpectrumBandFeed(barCount: .b64)
        for count in SpectrumBarCount.allCases {
            feed.setBarCount(count)
            let layout = CircularSpectrumLayout(configuration: CircularSpectrumConfiguration(barCount: count))
            for frequency in BandFeedFixture.frequencies {
                feed.reset()
                XCTAssertTrue(feed.pull(from: ArrayPCMReader(try BandFeedFixture.sine(frequency))))
                let bands = Array(feed.bands)
                XCTAssertEqual(bands.count, count.rawValue)
                let expected = try BandFeedFixture.expectedBand(frequency, count: count)
                let width = try BandFeedFixture.layout(count).widthInBins(ofBand: expected)
                let loudest = bands.indices.max { bands[$0] < bands[$1] }!
                XCTAssertTrue(bands.allSatisfy { $0 >= 0 && $0 <= 1 && $0.isFinite })
                layout.layout(bands, width: 1179, height: 2556)
                let longest = (0..<count.rawValue).max { layout.bar($0).outerRadius < layout.bar($1).outerRadius }!
                XCTAssertEqual(longest, loudest, "the longest bar is the loudest band")
                if width >= 2 {
                    // The band is resolvable: the sine lights exactly it.
                    XCTAssertEqual(loudest, expected, "\(frequency) Hz, \(count.rawValue) bands")
                } else {
                    // Bands narrower than about two bins (low frequencies at 64 and 128 bands) are
                    // below the 2,048-point spectrum's resolution: the loudest band must lie within
                    // one bin (21.5 Hz) of the sine (VIS-001-S4 note).
                    XCTAssertTrue(try BandFeedFixture.band(loudest, isWithinOneBinOf: frequency, count: count),
                                  "\(frequency) Hz, \(count.rawValue) bands: loudest band \(loudest) is more than one bin away")
                }
                print("VIS-001 band feed: \(frequency) Hz, N=\(count.rawValue): containing band \(expected) (\(String(format: "%.2f", width)) bins wide), loudest \(loudest), value \(bands[loudest]), \(width >= 2 ? "exact" : "within one bin")")
            }
        }
    }

    func testSilenceGivesZeroBands() throws {
        let feed = try SpectrumBandFeed(barCount: .b32)
        XCTAssertTrue(feed.pull(from: ArrayPCMReader([Float](repeating: 0, count: 2 * 44_100))))
        XCTAssertEqual(Array(feed.bands), [Float](repeating: 0, count: 32))
    }

    func testNothingNewMeansNoFrame() throws {
        let feed = try SpectrumBandFeed(barCount: .b16)
        XCTAssertFalse(feed.pull(from: ArrayPCMReader([])))
        XCTAssertFalse(feed.pull(from: ArrayPCMReader([Float](repeating: 0.1, count: 2 * 100))), "less than one window")
    }
}

final class LiveBandAnalyzerTests: XCTestCase {
    /// Polls `buffer` until a frame arrives or 30 s pass.
    private func waitForFrame(_ buffer: LiveBandOutput, count: Int) -> [Float]? {
        var out = [Float](repeating: 0, count: 128)
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if let info = out.withUnsafeMutableBufferPointer({ buffer.readLatest(into: $0.baseAddress!, capacity: 128) }) {
                return Array(out[0..<info.count])
            }
            Thread.sleep(forTimeInterval: 0.005)
        }
        return nil
    }

    func testPublishesTheSineBandFromAnAnalysisTap() throws {
        let ring = NormalizedPCMRing(analysisTapCapacityFrames: NormalizedPCMRing.analysisTapDefaultCapacityFrames)
        let tap = try XCTUnwrap(ring.analysisTap)
        let analyzer = try LiveBandAnalyzer(barCount: .b32)
        analyzer.start(reader: tap)
        analyzer.start(reader: tap)   // idempotent
        let sine = try BandFeedFixture.sine(1_000, seconds: 0.25)
        sine.withUnsafeBufferPointer { ring.write($0.baseAddress!, frames: $0.count / 2) }
        let frame = try XCTUnwrap(waitForFrame(analyzer.output, count: 32), "no band frame within 30 s")
        XCTAssertEqual(frame.count, 32)
        let loudest = frame.indices.max { frame[$0] < frame[$1] }!
        XCTAssertEqual(loudest, try BandFeedFixture.expectedBand(1_000, count: .b32), "1 kHz bands at 32 are several bins wide")
        analyzer.stop()
        analyzer.stop()               // idempotent
        XCTAssertFalse(analyzer.isRunning)
        // After stop, new audio produces no frame (the timer is cancelled before stop returns).
        var drain = [Float](repeating: 0, count: 128)
        while drain.withUnsafeMutableBufferPointer({ analyzer.output.readLatest(into: $0.baseAddress!, capacity: 128) }) != nil {}
        sine.withUnsafeBufferPointer { ring.write($0.baseAddress!, frames: $0.count / 2) }
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertNil(drain.withUnsafeMutableBufferPointer { analyzer.output.readLatest(into: $0.baseAddress!, capacity: 128) })
    }

    func testBarCountChangeTakesEffect() throws {
        let ring = NormalizedPCMRing(analysisTapCapacityFrames: NormalizedPCMRing.analysisTapDefaultCapacityFrames)
        let analyzer = try LiveBandAnalyzer(barCount: .b16)
        analyzer.setBarCount(.b128)
        analyzer.start(reader: try XCTUnwrap(ring.analysisTap))
        let sine = try BandFeedFixture.sine(440, seconds: 0.25)
        sine.withUnsafeBufferPointer { ring.write($0.baseAddress!, frames: $0.count / 2) }
        let frame = try XCTUnwrap(waitForFrame(analyzer.output, count: 128))
        XCTAssertEqual(frame.count, 128)
        analyzer.stop()
    }
}
