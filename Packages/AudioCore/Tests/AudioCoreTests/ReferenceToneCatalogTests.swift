// ReferenceToneCatalogTests.swift — the versioned fixture catalog, its expected analysis values and
// its golden hashes (AUD-016-T07, T09; AUD-016-R9 to R11, R23, S1;
// specs/011-aud-016-reference-tone-suite/contracts/fixture-catalog.md).
import Foundation
import XCTest
@testable import AudioCore

final class ReferenceToneCatalogTests: XCTestCase {
    private func fixture(_ id: String, file: StaticString = #filePath, line: UInt = #line) throws -> ReferenceToneFixture {
        try XCTUnwrap(ReferenceToneCatalog.fixture(id: id), "no fixture \(id)", file: file, line: line)
    }

    // MARK: The catalog (AUD-016-R9, R23)

    func testVersionIDsNamesAndLayouts() throws {
        XCTAssertEqual(ReferenceToneCatalog.version, 1)
        XCTAssertEqual(ReferenceToneCatalog.fixtures.map(\.id), [
            "sine-1k", "sine-100", "sine-1500", "sine-split", "sweep-log", "sweep-linear",
            "pulse-120", "pulse-120-accent", "pulse-132", "silence",
        ])
        XCTAssertEqual(ReferenceToneCatalog.fixtures.map(\.name), [
            "Test tone 1 kHz", "Test tone 100 Hz", "Test tone 1.5 kHz", "Test tone L 1 kHz, R 440 Hz",
            "Test sweep 20 Hz–20 kHz, logarithmic", "Test sweep 20 Hz–20 kHz, linear",
            "Test pulses 120 BPM", "Test pulses 120 BPM, accented", "Test pulses 132 BPM", "Test silence",
        ])
        XCTAssertEqual(Set(ReferenceToneCatalog.fixtures.map(\.id)).count, ReferenceToneCatalog.fixtures.count)
        for fixture in ReferenceToneCatalog.fixtures {
            XCTAssertTrue(fixture.name.hasPrefix("Test "), fixture.id)
            XCTAssertFalse(fixture.summary.isEmpty, fixture.id)
            XCTAssertEqual(fixture.loopSeconds, 10, fixture.id)
            XCTAssertEqual(fixture.layouts, fixture.id == "sine-split" ? [2] : [1, 2], fixture.id)
        }
        XCTAssertEqual(ReferenceToneCatalog.variantRates, [44_100, 48_000])
        XCTAssertEqual(ReferenceToneCatalog.fftSizes, [512, 1_024, 2_048, 4_096, 8_192])
        XCTAssertEqual(ReferenceToneCatalog.playbackFormat, ToneFormat.canonical)
        XCTAssertNil(ReferenceToneCatalog.fixture(id: "nope"))
    }

    func testParameters() throws {
        XCTAssertEqual(try fixture("sine-1k").signal, .sine(SineTone(frequency: 1_000, amplitude: 0.25)))
        XCTAssertEqual(try fixture("sine-100").signal, .sine(SineTone(frequency: 100, amplitude: 0.25)))
        XCTAssertEqual(try fixture("sine-1500").signal, .sine(SineTone(frequency: 1_500, amplitude: 0.25)))
        XCTAssertEqual(try fixture("sine-split").signal, .sine(SineTone(left: 1_000, right: 440, amplitude: 0.25)))
        XCTAssertEqual(try fixture("sweep-log").signal, .sweep(SweepTone(start: 20, end: 20_000, seconds: 10, amplitude: 0.25, curve: .logarithmic)))
        XCTAssertEqual(try fixture("sweep-linear").signal, .sweep(SweepTone(start: 20, end: 20_000, seconds: 10, amplitude: 0.25, curve: .linear)))
        XCTAssertEqual(try fixture("pulse-120").signal, .pulses(PulseTrain(beatsPerMinute: 120, widthSeconds: 0.002, amplitude: 0.5)))
        XCTAssertEqual(try fixture("pulse-120-accent").signal,
                       .pulses(PulseTrain(beatsPerMinute: 120, widthSeconds: 0.002, amplitude: 0.5, accents: [1, 0.5, 0.5, 0.5])))
        XCTAssertEqual(try fixture("pulse-132").signal, .pulses(PulseTrain(beatsPerMinute: 132, widthSeconds: 0.002, amplitude: 0.5)))
        XCTAssertEqual(try fixture("silence").signal, .silence)
    }

    /// Every variant stays at or below −6 dBFS and repeats seamlessly across the loop wrap.
    func testPeaksAndSeamlessLoops() throws {
        for fixture in ReferenceToneCatalog.fixtures {
            for rate in ReferenceToneCatalog.variantRates {
                for channels in fixture.layouts {
                    let generator = try fixture.generator(sampleRate: rate, channels: channels)
                    let loop = try ReferenceToneLoops.firstRun(fixture, rate: rate, channels: channels)
                    let peak = loop.map { abs($0) }.max() ?? 0
                    XCTAssertLessThanOrEqual(peak, 0.5, "\(fixture.id) \(rate)/\(channels)")
                    if fixture.id != "silence" { XCTAssertGreaterThan(peak, 0.2, "\(fixture.id)") }
                    let wrap = generator.interleaved(frames: 4_096, startFrame: Int64(fixture.loopFrames(sampleRate: rate)))
                    XCTAssertEqual(wrap.map(\.bitPattern), loop[0..<(4_096 * channels)].map(\.bitPattern),
                                   "\(fixture.id) \(rate)/\(channels): the next loop starts like the first")
                }
            }
        }
    }

    // MARK: Expected values (AUD-016-R11): the contract's tables

    func testSineBins() throws {
        let nearest: [String: [Int]] = [
            "100@44100": [1, 2, 5, 9, 19], "100@48000": [1, 2, 4, 9, 17],
            "1000@44100": [12, 23, 46, 93, 186], "1000@48000": [11, 21, 43, 85, 171],
            "1500@44100": [17, 35, 70, 139, 279], "1500@48000": [16, 32, 64, 128, 256],
            "440@44100": [5, 10, 20, 41, 82], "440@48000": [5, 9, 19, 38, 75],
        ]
        XCTAssertEqual(try fixture("sine-split").sineFrequencies, [1_000, 440])
        XCTAssertEqual(try fixture("sine-1500").sineFrequencies, [1_500])
        XCTAssertEqual(try fixture("sweep-log").sineFrequencies, [])
        for (key, bins) in nearest {
            let parts = key.split(separator: "@")
            let frequency = Double(parts[0])!, rate = Int(parts[1])!
            XCTAssertEqual(ReferenceToneCatalog.fftSizes.map { ReferenceToneCatalog.nearestBin(frequency: frequency, fftSize: $0, sampleRate: rate) },
                           bins, key)
            for size in ReferenceToneCatalog.fftSizes {
                let centered = ReferenceToneCatalog.isBinCentered(frequency: frequency, fftSize: size, sampleRate: rate)
                XCTAssertEqual(centered, frequency == 1_500 && rate == 48_000, "\(key) N=\(size)")
                XCTAssertEqual(ReferenceToneCatalog.exactBin(frequency: frequency, fftSize: size, sampleRate: rate),
                               frequency * Double(size) / Double(rate))
            }
        }
        XCTAssertEqual(ReferenceToneCatalog.exactBin(frequency: 1_000, fftSize: 1_024, sampleRate: 48_000), 21.333333333333332)
    }

    func testPulseOnsetsTempoAndAccents() throws {
        let p120 = try fixture("pulse-120"), accent = try fixture("pulse-120-accent"), p132 = try fixture("pulse-132")
        XCTAssertEqual(p120.beatsPerMinute, 120)
        XCTAssertEqual(p132.beatsPerMinute, 132)
        XCTAssertNil(try fixture("sine-1k").beatsPerMinute)
        XCTAssertEqual(p120.onsetFrames(sampleRate: 44_100), (0..<20).map { Int64($0 * 22_050) })
        XCTAssertEqual(p120.onsetFrames(sampleRate: 48_000), (0..<20).map { Int64($0 * 24_000) })
        XCTAssertEqual(accent.onsetFrames(sampleRate: 48_000), p120.onsetFrames(sampleRate: 48_000))
        XCTAssertEqual(p120.framesPerBeat(sampleRate: 48_000), 24_000)
        XCTAssertEqual(p132.framesPerBeat(sampleRate: 44_100)!, 20_045.454545454544, accuracy: 1e-9)
        XCTAssertEqual(p132.onsetFrames(sampleRate: 44_100), [
            0, 20_045, 40_091, 60_136, 80_182, 100_227, 120_273, 140_318, 160_364, 180_409, 200_455, 220_500,
            240_545, 260_591, 280_636, 300_682, 320_727, 340_773, 360_818, 380_864, 400_909, 420_955,
        ])
        XCTAssertEqual(p132.onsetFrames(sampleRate: 48_000), [
            0, 21_818, 43_636, 65_455, 87_273, 109_091, 130_909, 152_727, 174_545, 196_364, 218_182, 240_000,
            261_818, 283_636, 305_455, 327_273, 349_091, 370_909, 392_727, 414_545, 436_364, 458_182,
        ])
        XCTAssertEqual(accent.onsetLevels(sampleRate: 48_000), (0..<20).map { $0 % 4 == 0 ? 0.5 : 0.25 })
        XCTAssertEqual(p132.onsetLevels(sampleRate: 48_000), [Double](repeating: 0.5, count: 22))
        XCTAssertEqual(try fixture("silence").onsetFrames(sampleRate: 48_000), [])
    }

    func testSweepFrequencies() throws {
        let log = try fixture("sweep-log"), linear = try fixture("sweep-linear")
        let expected: [(Double, Double, Double)] = [(0, 20, 20), (1.25, 47.427, 2_517.5), (2.5, 112.468, 5_015),
                                                    (5, 632.456, 10_010), (7.5, 3_556.559, 15_005)]
        for (t, logHz, linearHz) in expected {
            XCTAssertEqual(try XCTUnwrap(log.instantaneousFrequency(atSeconds: t)), logHz, accuracy: 0.001, "log at \(t)")
            XCTAssertEqual(try XCTUnwrap(linear.instantaneousFrequency(atSeconds: t)), linearHz, accuracy: 1e-9, "linear at \(t)")
        }
        XCTAssertEqual(ReferenceToneCatalog.sweepCheckSeconds, [0, 1.25, 2.5, 5, 7.5])
        XCTAssertNil(try fixture("silence").instantaneousFrequency(atSeconds: 1))
        XCTAssertEqual(try fixture("sine-1k").instantaneousFrequency(atSeconds: 1), 1_000)
    }

    // MARK: Golden hashes (AUD-016-R10, S1)

    /// Generates every variant twice; both runs are equal and hash to the stored value. The first
    /// run is the shared one also used by `testPeaksAndSeamlessLoops` (generated once per process);
    /// the second is generated here and hashed. Shortened 2026-11-13 under owner rule 7: each variant
    /// was generated three times per suite and hashed with the portable SHA-256 in one 29 s test; now
    /// twice, hashed with CryptoKit where it exists (TestSHA256.swift), split by rate into two tests.
    /// Together they still check all 38 golden values.
    private func checkGoldens(rate: Int) throws -> Set<String> {
        var computed: [String: String] = [:]
        for fixture in ReferenceToneCatalog.fixtures {
            for channels in fixture.layouts {
                let key = ReferenceToneGoldens.key(fixture.id, rate: rate, channels: channels)
                let first = try ReferenceToneLoops.firstRun(fixture, rate: rate, channels: channels)
                let second = try fixture.loop(sampleRate: rate, channels: channels)
                XCTAssertEqual(first.count, fixture.loopFrames(sampleRate: rate) * channels, key)
                XCTAssertTrue(first.withUnsafeBytes { a in second.withUnsafeBytes { b in a.count == b.count && memcmp(a.baseAddress!, b.baseAddress!, a.count) == 0 } },
                              "\(key): two runs differ")
                computed[key] = TestSHA256.hex(samples: second)
            }
        }
        XCTAssertEqual(computed.count, 19, "variants at \(rate) Hz")
        let mismatches = computed.keys.sorted().filter { ReferenceToneGoldens.sha256[$0] != computed[$0] }
        XCTAssertTrue(mismatches.isEmpty,
                      "hashes differ from the goldens:\n" + mismatches.map { "\"\($0)\": \"\(computed[$0]!)\"," }.joined(separator: "\n"))
        return Set(computed.keys)
    }

    func testGoldenHashesOnRepeatedRuns44100() throws {
        XCTAssertEqual(try checkGoldens(rate: 44_100), goldenKeys(rate: 44_100))
    }

    func testGoldenHashesOnRepeatedRuns48000() throws {
        XCTAssertEqual(try checkGoldens(rate: 48_000), goldenKeys(rate: 48_000))
    }

    /// The stored table has exactly the 38 variants the two rate tests check, and nothing else.
    func testGoldenTableCoversEveryVariant() {
        XCTAssertEqual(ReferenceToneGoldens.sha256.count, 38, "stored goldens")
        XCTAssertEqual(goldenKeys(rate: 44_100).union(goldenKeys(rate: 48_000)), Set(ReferenceToneGoldens.sha256.keys))
        XCTAssertEqual(ReferenceToneCatalog.variantRates, [44_100, 48_000])
    }

    private func goldenKeys(rate: Int) -> Set<String> {
        Set(ReferenceToneCatalog.fixtures.flatMap { fixture in
            fixture.layouts.map { ReferenceToneGoldens.key(fixture.id, rate: rate, channels: $0) }
        })
    }
}

/// The first generation of every catalog variant, made once per test process and shared by the
/// peak, seamless-loop and golden tests (about 107 MB; each variant otherwise cost a further
/// generation in a Debug build).
enum ReferenceToneLoops {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var loops: [String: [Float]] = [:]

    static func firstRun(_ fixture: ReferenceToneFixture, rate: Int, channels: Int) throws -> [Float] {
        let key = ReferenceToneGoldens.key(fixture.id, rate: rate, channels: channels)
        lock.lock()
        defer { lock.unlock() }
        if let loop = loops[key] { return loop }
        let loop = try fixture.loop(sampleRate: rate, channels: channels)
        loops[key] = loop
        return loop
    }
}
