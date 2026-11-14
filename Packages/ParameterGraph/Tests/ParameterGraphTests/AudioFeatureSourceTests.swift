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
    /// ANL-010-T09: the centroid source (ANL-010-R8).
    func testCentroidSourceRoundTripsAndReadsTheNormalizedCentroid() {
        XCTAssertEqual(AudioFeatureSource.centroid.id, "audio.centroid")
        XCTAssertEqual(AudioFeatureSource(id: "audio.centroid"), .centroid)
        XCTAssertNil(AudioFeatureSource(id: "audio.Centroid"))
        let bands: [Float] = [0.2]
        bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
            XCTAssertEqual(AudioFeatureSource.centroid.value(in: AudioFeatureFrame(bands: buffer, centroid: 0.375)), 0.375)
            XCTAssertEqual(AudioFeatureSource.centroid.value(in: AudioFeatureFrame(bands: buffer, centroid: .infinity)), 0)
            XCTAssertEqual(AudioFeatureSource.centroid.value(in: AudioFeatureFrame(bands: buffer, kick: 1)), 0, "no centroid feed reads 0")
        }
        XCTAssertEqual(AudioFeatureSource.centroid.value(in: .silent), 0)
    }

    /// ANL-014-T08: the loudness source (ANL-014-R8).
    func testLoudnessSourceRoundTripsAndReadsTheEnvelope() {
        XCTAssertEqual(AudioFeatureSource.loudness.id, "audio.loudness")
        XCTAssertEqual(AudioFeatureSource(id: "audio.loudness"), .loudness)
        XCTAssertEqual(AudioFeatureSource.loudness.description.isEmpty, false)
        XCTAssertNil(AudioFeatureSource(id: "audio.Loudness"))
        let bands: [Float] = [0.2]
        bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
            XCTAssertEqual(AudioFeatureSource.loudness.value(in: AudioFeatureFrame(bands: buffer, loudness: 0.625)), 0.625)
            XCTAssertEqual(AudioFeatureSource.loudness.value(in: AudioFeatureFrame(bands: buffer, loudness: .nan)), 0)
            XCTAssertEqual(AudioFeatureSource.loudness.value(in: AudioFeatureFrame(bands: buffer, centroid: 1)), 0, "no loudness feed reads 0")
        }
        XCTAssertEqual(AudioFeatureSource.loudness.value(in: .silent), 0)
    }

    /// ANL-012-T08: the flatness source (ANL-012-R7).
    func testFlatnessSourceRoundTripsAndReadsTheValue() {
        XCTAssertEqual(AudioFeatureSource.flatness.id, "audio.flatness")
        XCTAssertEqual(AudioFeatureSource(id: "audio.flatness"), .flatness)
        XCTAssertNil(AudioFeatureSource(id: "audio.Flatness"))
        let bands: [Float] = [0.2]
        bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
            XCTAssertEqual(AudioFeatureSource.flatness.value(in: AudioFeatureFrame(bands: buffer, flatness: 0.5625)), 0.5625)
            XCTAssertEqual(AudioFeatureSource.flatness.value(in: AudioFeatureFrame(bands: buffer, flatness: .nan)), 0)
            XCTAssertEqual(AudioFeatureSource.flatness.value(in: AudioFeatureFrame(bands: buffer, rolloff: 1)), 0, "no feed reads 0")
        }
        XCTAssertEqual(AudioFeatureSource.flatness.value(in: .silent), 0)
    }

    /// ANL-011-T09: the rolloff source (ANL-011-R8).
    func testRolloffSourceRoundTripsAndReadsTheValue() {
        XCTAssertEqual(AudioFeatureSource.rolloff.id, "audio.rolloff")
        XCTAssertEqual(AudioFeatureSource(id: "audio.rolloff"), .rolloff)
        XCTAssertNil(AudioFeatureSource(id: "audio.rollOff"))
        let bands: [Float] = [0.2]
        bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
            XCTAssertEqual(AudioFeatureSource.rolloff.value(in: AudioFeatureFrame(bands: buffer, rolloff: 0.625)), 0.625)
            XCTAssertEqual(AudioFeatureSource.rolloff.value(in: AudioFeatureFrame(bands: buffer, rolloff: .nan)), 0)
            XCTAssertEqual(AudioFeatureSource.rolloff.value(in: AudioFeatureFrame(bands: buffer, centroid: 1)), 0, "no feed reads 0")
        }
        XCTAssertEqual(AudioFeatureSource.rolloff.value(in: .silent), 0)
    }

    /// ANL-009-T07: the high transient source (ANL-009-R8).
    func testHighTransientSourceRoundTripsAndReadsTheValue() {
        XCTAssertEqual(AudioFeatureSource.highTransient.id, "audio.highTransient")
        XCTAssertEqual(AudioFeatureSource(id: "audio.highTransient"), .highTransient)
        XCTAssertNil(AudioFeatureSource(id: "audio.hihat"), "no instrument-named source exists")
        let bands: [Float] = [0.2]
        bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
            XCTAssertEqual(AudioFeatureSource.highTransient.value(in: AudioFeatureFrame(bands: buffer, highTransient: 0.625)), 0.625)
            XCTAssertEqual(AudioFeatureSource.highTransient.value(in: AudioFeatureFrame(bands: buffer, highTransient: .nan)), 0)
            XCTAssertEqual(AudioFeatureSource.highTransient.value(in: AudioFeatureFrame(bands: buffer, midTransient: 1)), 0, "no feed reads 0")
        }
        XCTAssertEqual(AudioFeatureSource.highTransient.value(in: .silent), 0)
    }

    /// ANL-008-T07: the mid transient source (ANL-008-R8).
    func testMidTransientSourceRoundTripsAndReadsTheValue() {
        XCTAssertEqual(AudioFeatureSource.midTransient.id, "audio.midTransient")
        XCTAssertEqual(AudioFeatureSource(id: "audio.midTransient"), .midTransient)
        XCTAssertNil(AudioFeatureSource(id: "audio.snare"), "no instrument-named source exists")
        let bands: [Float] = [0.2]
        bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
            XCTAssertEqual(AudioFeatureSource.midTransient.value(in: AudioFeatureFrame(bands: buffer, midTransient: 0.625)), 0.625)
            XCTAssertEqual(AudioFeatureSource.midTransient.value(in: AudioFeatureFrame(bands: buffer, midTransient: .infinity)), 0)
            XCTAssertEqual(AudioFeatureSource.midTransient.value(in: AudioFeatureFrame(bands: buffer, kick: 1)), 0, "no feed reads 0")
        }
        XCTAssertEqual(AudioFeatureSource.midTransient.value(in: .silent), 0)
    }

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
