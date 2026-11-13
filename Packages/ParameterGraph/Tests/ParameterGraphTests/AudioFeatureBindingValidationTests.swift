// AudioFeatureBindingValidationTests.swift — MOD-002-T06: every refusal reason of contract C2 has
// a fixture; each names the target and leaves the existing bindings unchanged (MOD-002-R2 to R4,
// R7; MOD-002-S2).
import ParameterGraph
import XCTest

final class AudioFeatureBindingValidationTests: XCTestCase {
    static let group = ParameterGroup(id: "test.v", displayName: "Validation")
    static let opacity: ParameterID = "test.v.opacity"
    static let flag: ParameterID = "test.v.flag"
    static let locked: ParameterID = "test.v.locked"
    static let replaceOnly: ParameterID = "test.v.replaceOnly"

    static func continuous(_ id: ParameterID, policy: ModulationPolicy = .continuousDefault) -> ParameterDescriptor {
        ParameterDescriptor(id: id, displayName: "\(id)", group: group, unit: .normalized,
                            kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0.5), modulation: policy)
    }

    static func modulator() throws -> AudioFeatureModulator {
        let registry = try ParameterRegistry(descriptors: [
            continuous(opacity),
            ParameterDescriptor(id: flag, displayName: "Flag", group: group, unit: .none,
                                kind: .boolean(defaultValue: false), modulation: .discreteManual),
            continuous(locked, policy: .none),
            continuous(replaceOnly, policy: ModulationPolicy(isModulatable: true, mixModes: [.replace], allowsExternalControl: true)),
        ])
        return AudioFeatureModulator(registry: registry)
    }

    static func binding(_ target: ParameterID = opacity, source: AudioFeatureSource = .band(0),
                        input: (Double, Double) = (0, 1), output: (Double, Double) = (0, 1),
                        mixMode: ModulationMixMode = .replace, envelope: AudioFeatureEnvelope = .none) -> AudioFeatureBinding {
        AudioFeatureBinding(source: source, target: target, inputMinimum: input.0, inputMaximum: input.1,
                            outputStart: output.0, outputEnd: output.1, mixMode: mixMode, envelope: envelope)
    }

    /// Binds `binding`, expects `expected`, and checks the message and that nothing changed.
    private func assertRefused(_ binding: AudioFeatureBinding, _ expected: AudioFeatureBindingError, mentions words: [String],
                               file: StaticString = #filePath, line: UInt = #line) throws {
        let modulator = try Self.modulator()
        let existing = Self.binding(Self.replaceOnly, output: (0.2, 0.4))
        try modulator.bind(existing)
        do {
            try modulator.bind(binding)
            XCTFail("accepted \(binding)", file: file, line: line)
        } catch {
            XCTAssertEqual(error, expected, file: file, line: line)
            let text = error.description
            XCTAssertTrue(text.contains("\"\(binding.target)\""), "names the target: \(text)", file: file, line: line)
            for word in words { XCTAssertTrue(text.contains(word), "\(text) mentions \(word)", file: file, line: line) }
        }
        XCTAssertEqual(modulator.bindings, [existing], "existing bindings unchanged", file: file, line: line)
    }

    func testTargetRules() throws {
        try assertRefused(Self.binding("settings.reduceFlashing"), .unknownTarget("settings.reduceFlashing"), mentions: ["not a registered"])
        try assertRefused(Self.binding(Self.flag), .notNumeric(Self.flag, kind: "boolean"), mentions: ["boolean"])
        try assertRefused(Self.binding(Self.locked), .notModulatable(Self.locked), mentions: ["manual only"])
        try assertRefused(Self.binding(Self.replaceOnly, output: (0, 0.1), mixMode: .add), .mixModeNotAllowed(Self.replaceOnly, .add),
                          mentions: ["add"])
    }

    func testSourceInputOutputAndEnvelopeRules() throws {
        for index in [128, -1] {
            try assertRefused(Self.binding(source: .band(index)), .bandIndexOutOfRange(Self.opacity, index), mentions: ["band \(index)"])
        }
        for input in [(1.0, 1.0), (1.0, 0.0), (Double.nan, 1.0), (0.0, Double.infinity)] {
            try assertRefused(Self.binding(input: input), .invalidInputRange(Self.opacity), mentions: ["input range"])
        }
        try assertRefused(Self.binding(output: (0, 1.2)), .outputOutOfRange(Self.opacity, .replace, minimum: 0, maximum: 1),
                          mentions: ["replace", "0.0…1.0"])
        try assertRefused(Self.binding(output: (0, 1.5), mixMode: .add), .outputOutOfRange(Self.opacity, .add, minimum: -1, maximum: 1),
                          mentions: ["add", "-1.0…1.0"])
        try assertRefused(Self.binding(output: (0.5, 1.5), mixMode: .multiply),
                          .outputOutOfRange(Self.opacity, .multiply, minimum: 0, maximum: 1), mentions: ["multiply"])
        try assertRefused(Self.binding(output: (-0.1, 1), mixMode: .multiply),
                          .outputOutOfRange(Self.opacity, .multiply, minimum: 0, maximum: 1), mentions: ["multiply"])
        try assertRefused(Self.binding(output: (.nan, 1)), .outputOutOfRange(Self.opacity, .replace, minimum: 0, maximum: 1),
                          mentions: ["replace"])
        for envelope in [AudioFeatureEnvelope(attackSeconds: -1, releaseSeconds: 0), AudioFeatureEnvelope(attackSeconds: 0, releaseSeconds: .infinity),
                         AudioFeatureEnvelope(attackSeconds: 61, releaseSeconds: 0)] {
            try assertRefused(Self.binding(envelope: envelope), .invalidEnvelope(Self.opacity), mentions: ["envelope"])
        }
    }

    func testValidBindingsAreAcceptedAndRebindReplaces() throws {
        let modulator = try Self.modulator()
        try modulator.bind(Self.binding(output: (1, 0)))                         // inverted replace
        try modulator.bind(Self.binding(output: (-1, 1), mixMode: .add))          // full ± span
        try modulator.bind(Self.binding(output: (0, 1), mixMode: .multiply, envelope: AudioFeatureEnvelope(attackSeconds: 60, releaseSeconds: 0)))
        XCTAssertEqual(modulator.bindings.count, 1, "each rebind replaced the earlier binding")
        XCTAssertEqual(modulator.bindings.first?.mixMode, .multiply)
    }

    func testAtMostThirtyTwoBindings() throws {
        let ids: [ParameterID] = (0...32).map { ParameterID("test.many.p\($0)") }
        let registry = try ParameterRegistry(descriptors: ids.map { Self.continuous($0) })
        let modulator = AudioFeatureModulator(registry: registry)
        for id in ids.prefix(32) { try modulator.bind(Self.binding(id)) }
        XCTAssertThrowsError(try modulator.bind(Self.binding(ids[32]))) { error in
            XCTAssertEqual(error as? AudioFeatureBindingError, .tooManyBindings(ids[32], limit: 32))
        }
        XCTAssertEqual(modulator.bindings.count, 32)
        try modulator.bind(Self.binding(ids[0], output: (0.5, 1)))   // rebinding a bound target is not a new binding
        XCTAssertEqual(modulator.bindings.count, 32)
    }
}
