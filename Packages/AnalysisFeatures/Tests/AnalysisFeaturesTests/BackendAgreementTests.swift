// BackendAgreementTests.swift — vDSP vs portable, and both vs the Double reference DFT
// (ANL-001-T19; ANL-001-R11, S5; research ANL-001-D8).
import XCTest
import AudioCore
@testable import AnalysisFeatures

/// |a − b| ≤ 1e-5·peak + 1e-6 for every bin; returns the largest difference relative to the peak.
private func assertAgree(_ a: [Float], _ b: [Double], _ label: String, file: StaticString = #filePath, line: UInt = #line) -> Double {
    let peak = b.max() ?? 0
    var worst = 0.0
    for k in a.indices {
        let difference = abs(Double(a[k]) - b[k])
        worst = max(worst, peak > 0 ? difference / peak : difference)
        if difference > 1e-5 * peak + 1e-6 {
            XCTFail("\(label) bin \(k): \(a[k]) vs \(b[k])", file: file, line: line)
            return worst
        }
    }
    return worst
}

private func inputs(size: FFTSize) throws -> [(String, [Float])] {
    var list: [(String, [Float])] = [("noise", TestSupport.noise(count: 3 * size.rawValue, seed: UInt64(size.rawValue)))]
    for fixture in ReferenceToneCatalog.fixtures {
        switch fixture.signal {
        case .sine, .sweep:
            for rate in ReferenceToneCatalog.variantRates {
                let stereo = try fixture.generator(sampleRate: rate, channels: 2).interleaved(frames: 3 * size.rawValue, startFrame: 12_345)
                list.append(("\(fixture.id) L \(rate)", TestSupport.channel(stereo, 0, of: 2)))
                list.append(("\(fixture.id) R \(rate)", TestSupport.channel(stereo, 1, of: 2)))
            }
        default:
            continue
        }
    }
    return list
}

final class BackendAgreementTests: XCTestCase {
    func testAcceleratedAndPortableAgree() throws {
        guard SpectrumBackend.isAcceleratedAvailable else {
            throw XCTSkip("Accelerate is compiled out (ANALYSIS_NO_ACCELERATE or no Accelerate); nothing to compare")
        }
        let accelerated = SpectrumAnalyzer(backend: .accelerated)
        let portable = SpectrumAnalyzer(backend: .portable)
        var worst = 0.0
        for size in FFTSize.allCases {
            for (name, samples) in try inputs(size: size) {
                for offset in stride(from: 0, through: 2 * size.rawValue, by: size.rawValue / 2) {
                    let window = Array(samples[offset..<(offset + size.rawValue)])
                    let a = accelerated.magnitudes(of: window, size: size)
                    let p = portable.magnitudes(of: window, size: size)
                    let label = "\(name) N=\(size.rawValue) offset \(offset)"
                    worst = max(worst, assertAgree(p, a.map(Double.init), label))
                    if name != "noise" { XCTAssertEqual(TestSupport.peakBin(a), TestSupport.peakBin(p), label) }
                }
            }
        }
        print("ANL001-AGREEMENT largest |accelerated − portable| / peak = \(worst)")
    }

    func testEveryBackendMatchesTheReferenceDFT() throws {
        for backend in TestSupport.backends {
            let analyzer = SpectrumAnalyzer(backend: backend)
            var worst = 0.0
            for size in [FFTSize.n512, .n1024] {
                for (name, samples) in try inputs(size: size) {
                    let window = Array(samples[0..<size.rawValue])
                    let reference = TestSupport.referenceMagnitudes(window[...], size: size.rawValue)
                    worst = max(worst, assertAgree(analyzer.magnitudes(of: window, size: size), reference, "\(backend) \(name) N=\(size.rawValue)"))
                }
            }
            print("ANL001-DFT \(backend): largest |analyzer − reference DFT| / peak = \(worst)")
        }
    }
}
