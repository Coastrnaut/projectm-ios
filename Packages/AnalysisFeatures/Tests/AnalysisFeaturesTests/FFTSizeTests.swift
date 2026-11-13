// FFTSizeTests.swift — sizes, bin helpers, configuration validation and the decibel helper
// (ANL-001-T03; ANL-001-R2, R4, R6, R15).
import XCTest
import AudioCore
@testable import AnalysisFeatures

final class FFTSizeTests: XCTestCase {
    func testSupportedSizesAreExactlyTheFivePowersOfTwo() {
        XCTAssertEqual(FFTSize.allCases.map(\.rawValue), [512, 1_024, 2_048, 4_096, 8_192])
        XCTAssertEqual(FFTSize.allCases.map(\.log2), [9, 10, 11, 12, 13])
        XCTAssertEqual(FFTSize.maximum, .n8192)
        for size in FFTSize.allCases {
            XCTAssertEqual(FFTSize(samples: size.rawValue), size)
            XCTAssertEqual(size.binCount, size.rawValue / 2 + 1)
        }
        for unsupported in [0, 1, 256, 1_000, 16_384, -512] {
            XCTAssertNil(FFTSize(samples: unsupported), "\(unsupported)")
        }
    }

    func testBinHelpers() {
        XCTAssertEqual(FFTSize.n512.binWidth(sampleRate: 44_100), 86.1328125)
        XCTAssertEqual(FFTSize.n2048.binWidth(sampleRate: 48_000), 23.4375)
        XCTAssertEqual(FFTSize.n1024.frequency(ofBin: 10, sampleRate: 48_000), 468.75)
        XCTAssertEqual(FFTSize.n512.frequency(ofBin: 256, sampleRate: 44_100), 22_050)
        XCTAssertEqual(FFTSize.n512.nearestBin(toFrequency: -5, sampleRate: 44_100), 0)
        XCTAssertEqual(FFTSize.n512.nearestBin(toFrequency: 30_000, sampleRate: 44_100), 256)
        // The catalog's documented bins (ReferenceToneCatalog.nearestBin) for every sine, size and rate.
        for fixture in ReferenceToneCatalog.fixtures {
            for frequency in fixture.sineFrequencies {
                for rate in ReferenceToneCatalog.variantRates {
                    for size in FFTSize.allCases {
                        XCTAssertEqual(size.nearestBin(toFrequency: frequency, sampleRate: Double(rate)),
                                       ReferenceToneCatalog.nearestBin(frequency: frequency, fftSize: size.rawValue, sampleRate: rate),
                                       "\(fixture.id) \(frequency) Hz \(rate) N=\(size.rawValue)")
                    }
                }
            }
        }
    }

    func testConfigurationDefaultsAndValidation() throws {
        let defaults = try SpectrumConfiguration()
        XCTAssertEqual(defaults.size, .n2048)
        XCTAssertEqual(defaults.hop, 1_024)
        XCTAssertEqual(defaults.sampleRate, 44_100)
        XCTAssertEqual(defaults.channelMode, .mid)
        for size in FFTSize.allCases {
            XCTAssertEqual(try SpectrumConfiguration(size: size).hop, size.rawValue / 2)
            XCTAssertEqual(try SpectrumConfiguration(size: size, hop: 1).hop, 1)
            XCTAssertEqual(try SpectrumConfiguration(size: size, hop: size.rawValue).hop, size.rawValue)
            for bad in [0, -1, size.rawValue + 1] {
                XCTAssertThrowsError(try SpectrumConfiguration(size: size, hop: bad)) { error in
                    XCTAssertEqual(error as? SpectrumConfigurationError, .hopOutOfRange(hop: bad, size: size.rawValue))
                }
            }
        }
        for bad in [0, -1, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try SpectrumConfiguration(sampleRate: bad)) { error in
                guard case .invalidSampleRate = error as? SpectrumConfigurationError else {
                    return XCTFail("\(bad): \(error)")
                }
            }
        }
        let configured = try SpectrumConfiguration(size: .n512, hop: 128, sampleRate: 48_000, channelMode: .right)
        XCTAssertEqual(configured.binWidth, 93.75)
        XCTAssertEqual(configured.frequency(ofBin: 2), 187.5)
    }

    func testDecibels() {
        XCTAssertEqual(SpectrumMath.floorDecibels, -120)
        XCTAssertEqual(SpectrumMath.decibels(0), -120)
        XCTAssertEqual(SpectrumMath.decibels(1), 0)
        XCTAssertEqual(SpectrumMath.decibels(0.25), -12.0412, accuracy: 1e-3)
        XCTAssertEqual(SpectrumMath.decibels(1e-9), -120)
        XCTAssertEqual(SpectrumMath.decibels(.nan), -120)
        XCTAssertEqual(SpectrumMath.decibels(-1), -120)
        XCTAssertTrue(SpectrumMath.decibels(.infinity).isFinite)
    }
}
