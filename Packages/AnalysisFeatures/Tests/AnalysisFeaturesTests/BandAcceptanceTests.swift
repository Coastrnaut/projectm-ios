// BandAcceptanceTests.swift — the roadmap acceptance of ANL-002 (ANL-002-T08, T10, T12, T14;
// ANL-002-R9, R11, R12, R14, S1 to S5; AUD-016-R22 hand-off):
//   "Known multi-tone fixture populates expected bands and zero input stays zero."
// The multi-tone fixture is built from the AUD-016 tone generator (research ANL-002-D7); expected bands
// come from `BandOracle`, never from `BandLayout`. Runs for every backend in the build.
import XCTest
import Foundation
import AudioCore
@testable import AnalysisFeatures

final class BandAcceptanceTests: XCTestCase {
    private let amplitude = BandOracle.toneAmplitude

    // MARK: US1 — the multi-tone fixture populates the expected bands

    func testMultiToneFixturePopulatesExpectedBands() throws {
        var matrix: [String] = []
        var strictCount = 0
        var worstFar = 0.0
        var worstStrict = 0.0
        var lowestExpected = Double.infinity
        for backend in TestSupport.backends {
            var combinations = 0
            let analyzer = SpectrumAnalyzer(backend: backend)
            for rate in ReferenceToneCatalog.variantRates {
                let signal = try BandOracle.multiTone(sampleRate: rate, frames: FFTSize.maximum.rawValue)
                let reducer = try BandReducer(sampleRate: Double(rate), backend: backend)
                for size in FFTSize.allCases {
                    let magnitudes = analyzer.magnitudes(of: signal, size: size)
                    let delta = Double(rate) / Double(size.rawValue)
                    for count in BandCount.allCases {
                        let b = count.rawValue
                        let bands = reducer.reduce(magnitudes, size: size, bandCount: count)
                        let edges = BandOracle.edges(count: b, sampleRate: Double(rate))
                        let label = "\(backend) R=\(rate) N=\(size.rawValue) B=\(b)"
                        XCTAssertTrue(bands.allSatisfy { $0.isFinite && $0 >= 0 }, label)
                        func touches(_ band: Int, _ lo: Double, _ hi: Double) -> Bool { edges[band + 1] > lo && edges[band] < hi }

                        // (c) Bands far from every tone stay low.
                        for band in 0..<b where !BandOracle.toneFrequencies.contains(where: { touches(band, $0 - 4 * delta, $0 + 4 * delta) }) {
                            let ratio = Double(bands[band]) / amplitude
                            worstFar = max(worstFar, ratio)
                            XCTAssertLessThanOrEqual(ratio, 0.02, "\(label) far band \(band)")
                        }

                        for f in BandOracle.toneFrequencies {
                            combinations += 1
                            let bin = ReferenceToneCatalog.nearestBin(frequency: f, fftSize: size.rawValue, sampleRate: rate)
                            let expected = try XCTUnwrap(BandOracle.ownerBand(ofBin: bin, edges: edges, size: size.rawValue, sampleRate: Double(rate)))
                            let value = Double(bands[expected]) / amplitude
                            lowestExpected = min(lowestExpected, value)
                            // (a) The expected band is populated.
                            XCTAssertGreaterThanOrEqual(value, 0.35, "\(label) tone \(f) band \(expected)")
                            // The measured band: the largest band near the tone (ties → lowest).
                            let near = (0..<b).filter { touches($0, f - 4 * delta, f + 4 * delta) }
                            let measured = near.reduce(near[0]) { bands[$1] > bands[$0] ? $1 : $0 }
                            // (b) Strict: the main lobe lies inside the expected band, no other lobe reaches it.
                            let lobe = (f - 2.5 * delta, f + 2.5 * delta)
                            let others = BandOracle.toneFrequencies.filter { $0 != f }
                            let strict = edges[expected] <= lobe.0 && lobe.1 <= edges[expected + 1]
                                && !others.contains { touches(expected, $0 - 2.5 * delta, $0 + 2.5 * delta) }
                            if strict {
                                XCTAssertEqual(measured, expected, "\(label) tone \(f)")
                                XCTAssertEqual(value, 1, accuracy: 0.02, "\(label) tone \(f)")
                                worstStrict = max(worstStrict, abs(value - 1))
                            }
                            if backend == TestSupport.backends.first {
                                if strict { strictCount += 1 }
                                matrix.append("ANL-002 matrix: \(Int(f)) Hz | B=\(b) | N=\(size.rawValue) | \(rate) | expected \(expected) | measured \(measured) | value/A \(String(format: "%.3f", value)) | \(strict ? "strict" : "-")")
                            }
                        }
                    }
                }
            }
            XCTAssertEqual(combinations, 240, "\(backend)")
        }
        print(matrix.joined(separator: "\n"))
        print("ANL-002 summary: \(matrix.count) combinations, \(strictCount) strict, lowest expected-band value/A \(String(format: "%.3f", lowestExpected)), largest strict error \(String(format: "%.4f", worstStrict)), largest far-band value/A \(String(format: "%.5f", worstFar))")
        fflush(stdout)   // keep the matrix in one piece in the log
    }

    // MARK: US2 — zero input stays zero

    func testSilenceStaysExactlyZero() throws {
        let silence = try XCTUnwrap(ReferenceToneCatalog.fixture(id: "silence"))
        var frames = 0
        for rate in ReferenceToneCatalog.variantRates {
            let stereo = try silence.loop(sampleRate: rate, channels: 2)
            let reducers = try TestSupport.backends.map { try BandReducer(sampleRate: Double(rate), backend: $0) }
            var output = [Float](repeating: -1, count: 128)
            for size in FFTSize.allCases {
                let stream = SpectrumStream(configuration: try SpectrumConfiguration(size: size, sampleRate: Double(rate)),
                                            backend: TestSupport.backends.first!, clock: { 0 })
                var nonZero = 0
                stereo.withUnsafeBufferPointer { buffer in
                    let total = buffer.count / 2
                    var offset = 0
                    while offset < total {
                        offset += stream.append(interleaved: buffer.baseAddress! + 2 * offset, frames: total - offset, channels: 2)
                        while stream.nextFrame() != nil {
                            frames += 1
                            for reducer in reducers {
                                for count in BandCount.allCases {
                                    output.withUnsafeMutableBufferPointer { o in
                                        reducer.reduce(magnitudes: stream.magnitudes.baseAddress!, size: size, bandCount: count, into: o.baseAddress!)
                                        for i in 0..<count.rawValue where o[i].bitPattern != 0 { nonZero += 1 }
                                        for scale in [BandScale.linear(reference: 1), .decibels(floorDecibels: BandMath.defaultFloorDecibels)] {
                                            BandMath.normalize(o.baseAddress!, count: count.rawValue, scale: scale)
                                            for i in 0..<count.rawValue where o[i].bitPattern != 0 { nonZero += 1 }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                XCTAssertEqual(nonZero, 0, "R=\(rate) N=\(size.rawValue)")
            }
        }
        XCTAssertGreaterThan(frames, 6_000)
    }

    // MARK: US3 — switching size and count between frames

    func testSwitchingSizeAndCountBetweenFramesMatchesFreshReducers() throws {
        let rate = 44_100
        let signal = try BandOracle.multiTone(sampleRate: rate, frames: 2 * rate)
        let sizes: [FFTSize] = [.n2048, .n512, .n8192]
        let counts: [BandCount] = [.b16, .b128, .b32]
        for backend in TestSupport.backends {
            let stream = SpectrumStream(configuration: try SpectrumConfiguration(size: sizes[0], sampleRate: Double(rate)), backend: backend, clock: { 0 })
            let reducer = try BandReducer(sampleRate: Double(rate), backend: backend)
            var fresh: [String: BandReducer] = [:]
            var output = [Float](repeating: -1, count: 128)
            var frame = 0
            signal.withUnsafeBufferPointer { buffer in
                var offset = 0
                while offset < buffer.count {
                    offset += stream.append(mono: buffer.baseAddress! + offset, count: buffer.count - offset)
                    while let spectrum = stream.nextFrame() {
                        let count = counts[frame % counts.count]
                        let magnitudes = Array(stream.magnitudes)
                        XCTAssertEqual(magnitudes.count, spectrum.size.binCount)
                        output.withUnsafeMutableBufferPointer { o in
                            reducer.reduce(magnitudes: stream.magnitudes.baseAddress!, size: spectrum.size, bandCount: count, into: o.baseAddress!)
                        }
                        let key = "\(spectrum.size.rawValue)-\(count.rawValue)"
                        if fresh[key] == nil { fresh[key] = try? BandReducer(sampleRate: Double(rate), backend: backend) }
                        let expected = fresh[key]!.reduce(magnitudes, size: spectrum.size, bandCount: count)
                        XCTAssertEqual(Array(output[0..<count.rawValue]).map(\.bitPattern), expected.map(\.bitPattern), "\(backend) frame \(frame) \(key)")
                        frame += 1
                        stream.setConfiguration(try! SpectrumConfiguration(size: sizes[frame % sizes.count], sampleRate: Double(rate)))
                    }
                }
            }
            XCTAssertGreaterThan(frame, 20, "\(backend)")
        }
    }

    // MARK: US4 — identical runs; backends agree

    /// Bands of every frame (all four counts, concatenated) of `samples` through a fresh stream and reducer.
    private func bandFrames(_ samples: [Float], size: FFTSize, rate: Int, backend: SpectrumBackend)
        throws -> (bands: [Float], magnitudes: [[Float]]) {
        let configuration = try SpectrumConfiguration(size: size, sampleRate: Double(rate))
        let reducer = try BandReducer(sampleRate: Double(rate), backend: backend)
        var bands: [Float] = []
        var magnitudes: [[Float]] = []
        for frame in TestSupport.frames(of: samples, configuration: configuration, backend: backend) {
            magnitudes.append(frame.magnitudes)
            for count in BandCount.allCases {
                bands.append(contentsOf: reducer.reduce(frame.magnitudes, size: size, bandCount: count))
            }
        }
        return (bands, magnitudes)
    }

    func testRepeatedRunsAreBitIdenticalAndBackendsAgree() throws {
        var compared = 0
        var largestRelative: Float = 0
        for rate in ReferenceToneCatalog.variantRates {
            var signals: [(String, [Float])] = [("multi-tone", try BandOracle.multiTone(sampleRate: rate, frames: 10 * rate))]
            for id in ["sweep-log", "sweep-linear"] {
                signals.append((id, try XCTUnwrap(ReferenceToneCatalog.fixture(id: id)).loop(sampleRate: rate, channels: 1)))
            }
            for (name, samples) in signals {
                for size in [FFTSize.n512, .n8192] {
                    for backend in TestSupport.backends {
                        // The portable FFT is slow in Debug: where vDSP exists it repeats only the
                        // multi-tone fixture (vDSP covers the sweeps); without vDSP it runs everything.
                        if backend == .portable && SpectrumBackend.isAcceleratedAvailable && name != "multi-tone" { continue }
                        let first = try bandFrames(samples, size: size, rate: rate, backend: backend)
                        let second = try bandFrames(samples, size: size, rate: rate, backend: backend)
                        XCTAssertFalse(first.bands.isEmpty)
                        XCTAssertEqual(first.bands.map(\.bitPattern), second.bands.map(\.bitPattern), "\(name) \(backend) R=\(rate) N=\(size.rawValue)")
                        XCTAssertTrue(first.bands.allSatisfy { $0.isFinite && $0 >= 0 })
                        guard backend == .accelerated else { continue }
                        // The same magnitudes through both reduction paths.
                        let accelerated = try BandReducer(sampleRate: Double(rate), backend: .accelerated)
                        let portable = try BandReducer(sampleRate: Double(rate), backend: .portable)
                        for magnitudes in first.magnitudes.enumerated().filter({ $0.offset % 4 == 0 }).map(\.element) {
                            for count in BandCount.allCases {
                                let a = accelerated.reduce(magnitudes, size: size, bandCount: count)
                                let p = portable.reduce(magnitudes, size: size, bandCount: count)
                                let peak = a.max() ?? 0
                                for i in a.indices {
                                    let difference = abs(a[i] - p[i])
                                    if difference > 1e-5 * peak + 1e-7 { XCTFail("\(name) R=\(rate) N=\(size.rawValue) B=\(count.rawValue) band \(i): \(a[i]) vs \(p[i])") }
                                    if peak > 0 { largestRelative = max(largestRelative, difference / peak) }
                                }
                                compared += 1
                            }
                        }
                    }
                }
            }
        }
        if SpectrumBackend.isAcceleratedAvailable {
            XCTAssertGreaterThan(compared, 0)
            print("ANL-002 backend agreement: \(compared) frame×count comparisons (every 4th frame), largest |vDSP − portable| = \(largestRelative) of the frame's largest band")
        } else {
            print("ANL-002 backend agreement: skipped (vDSP compiled out; portable path only)")
        }
    }
}
