// EffectChainDescriptionTests.swift — FX-001-T06: the versioned, serializable chain description
// FX-020 will store (FX-001-R2; research FX-001-D6). Runs on Linux.
import XCTest
@testable import VisualEffects

final class EffectChainDescriptionTests: XCTestCase {
    func testRoundTripAndStableIdentifiers() throws {
        let chain = EffectChainDescription(effects: [.bloom(BloomParameters(enabled: true, intensity: 0.7, radius: 0.03))])
        let data = try JSONEncoder().encode(chain)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""formatVersion":1"#), text)
        XCTAssertTrue(text.contains(#""id":"fx.bloom""#), text)
        XCTAssertEqual(try JSONDecoder().decode(EffectChainDescription.self, from: data), chain)
        XCTAssertEqual(EffectIdentifier.bloom.rawValue, "fx.bloom")
        XCTAssertEqual(EffectDescription.bloom(BloomParameters()).identifier, .bloom)
    }

    func testDecodingClampsAndKeepsUnknownEffects() throws {
        let json = #"""
        {"formatVersion":1,"effects":[{"id":"fx.future","parameters":{"x":1}},
         {"id":"fx.bloom","parameters":{"enabled":true,"intensity":3,"radius":-1,"threshold":0.5,"knee":0.5}}]}
        """#
        let chain = try JSONDecoder().decode(EffectChainDescription.self, from: Data(json.utf8))
        XCTAssertEqual(chain.effects.count, 2)
        XCTAssertEqual(chain.effects[0], .unknown(EffectIdentifier(rawValue: "fx.future")))
        XCTAssertEqual(chain.effects[1], .bloom(BloomParameters(enabled: true, intensity: 1, radius: 0.005, threshold: 0.5, knee: 0.5)))
        XCTAssertEqual(chain.activeEffects, [chain.effects[1]], "unknown effects are skipped")
    }

    func testRejectsNewerVersionsAndTooManyEffects() {
        let newer = #"{"formatVersion":2,"effects":[]}"#
        XCTAssertThrowsError(try JSONDecoder().decode(EffectChainDescription.self, from: Data(newer.utf8))) {
            XCTAssertEqual($0 as? EffectChainDescriptionError, .unsupportedVersion(2))
        }
        let entries = Array(repeating: #"{"id":"fx.bloom","parameters":{}}"#, count: 17).joined(separator: ",")
        let many = #"{"formatVersion":1,"effects":["# + entries + "]}"
        XCTAssertThrowsError(try JSONDecoder().decode(EffectChainDescription.self, from: Data(many.utf8))) {
            XCTAssertEqual($0 as? EffectChainDescriptionError, .tooManyEffects(17))
        }
    }

    func testPassThroughBloomIsNotActive() {
        let chain = EffectChainDescription(effects: [.bloom(BloomParameters(enabled: false, intensity: 1)),
                                                     .bloom(BloomParameters(enabled: true, intensity: 0))])
        XCTAssertTrue(chain.activeEffects.isEmpty)
    }
}
