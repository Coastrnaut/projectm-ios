// AudioFeatureSourceTests.swift — MOD-002-T02: source IDs round-trip and frame readings
// (MOD-002-R1, R6; contract C1).
import ParameterGraph
import XCTest

final class AudioFeatureSourceTests: XCTestCase {
    func testIDsRoundTrip() {
        let sources: [AudioFeatureSource] = [.band(0), .band(127), .bandMean, .onset, .beatConfidence]
        let ids: [String] = sources.map(\.id)
        XCTAssertEqual(ids, ["audio.band.0", "audio.band.127", "audio.bandMean", "audio.onset", "audio.beatConfidence"])
        for source in sources {
            XCTAssertEqual(AudioFeatureSource(id: source.id), source)
        }
    }

    func testMalformedIDsAreRejected() {
        for id in ["audio.band.01", "audio.band.-1", "audio.band.128", "audio.band.", "audio.band.+1", "audio.level", "", "audio.band.1x"] {
            XCTAssertNil(AudioFeatureSource(id: id), id)
        }
    }

    func testValuesReadFromAFrame() {
        let bands: [Float] = [0.2, 0.4, 0.6]
        bands.withUnsafeBufferPointer { buffer in
            let frame = AudioFeatureFrame(bands: buffer, onset: 0.7, beatConfidence: 0.9)
            XCTAssertEqual(AudioFeatureSource.band(1).value(in: frame), Double(Float(0.4)))
            XCTAssertEqual(AudioFeatureSource.band(3).value(in: frame), 0, "a band beyond the frame reads 0")
            XCTAssertEqual(AudioFeatureSource.bandMean.value(in: frame), (Double(Float(0.2)) + Double(Float(0.4)) + Double(Float(0.6))) / 3, accuracy: 1e-12)
            XCTAssertEqual(AudioFeatureSource.onset.value(in: frame), Double(Float(0.7)))
            XCTAssertEqual(AudioFeatureSource.beatConfidence.value(in: frame), 0.9)
        }
        let silent = AudioFeatureFrame.silent
        for source in [AudioFeatureSource.band(0), .bandMean, .onset, .beatConfidence] {
            XCTAssertEqual(source.value(in: silent), 0, source.id)
        }
    }

    /// ANL-007-T09: the kick envelope source (ANL-007-R11).
    func testKickSourceRoundTripsAndReadsTheEnvelope() {
        XCTAssertEqual(AudioFeatureSource.kick.id, "audio.kick")
        XCTAssertEqual(AudioFeatureSource(id: "audio.kick"), .kick)
        XCTAssertNil(AudioFeatureSource(id: "audio.Kick"))
        let bands: [Float] = [0.2]
        bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
            XCTAssertEqual(AudioFeatureSource.kick.value(in: AudioFeatureFrame(bands: buffer, kick: 0.625)), 0.625)
            XCTAssertEqual(AudioFeatureSource.kick.value(in: AudioFeatureFrame(bands: buffer, kick: .nan)), 0)
            XCTAssertEqual(AudioFeatureSource.kick.value(in: AudioFeatureFrame(bands: buffer)), 0, "no kick feed reads 0")
        }
        XCTAssertEqual(AudioFeatureSource.kick.value(in: .silent), 0)
    }

    func testNonFiniteReadingsAreZero() {
        let bands: [Float] = [.nan, .infinity]
        bands.withUnsafeBufferPointer { buffer in
            let frame = AudioFeatureFrame(bands: buffer, onset: .nan, beatConfidence: .infinity)
            XCTAssertEqual(AudioFeatureSource.band(0).value(in: frame), 0)
            XCTAssertEqual(AudioFeatureSource.band(1).value(in: frame), 0)
            XCTAssertEqual(AudioFeatureSource.bandMean.value(in: frame), 0)
            XCTAssertEqual(AudioFeatureSource.onset.value(in: frame), 0)
            XCTAssertEqual(AudioFeatureSource.beatConfidence.value(in: frame), 0)
        }
    }
}
