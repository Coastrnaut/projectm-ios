// VisualParameterBindingTests.swift — MOD-002-T08: which of the app's catalog parameters an audio
// feature may drive (MOD-002-R2, R3; MOD-002-S2). Every modulatable parameter accepts a band over
// its full range; manual-only ones and Reduce flashing (never registered) are refused.
import ParameterGraph
import VisualParameters
import XCTest

final class VisualParameterBindingTests: XCTestCase {
    private func fullRangeBinding(_ descriptor: ParameterDescriptor) -> AudioFeatureBinding {
        var range: (Double, Double) = (0, 0)
        if case let .continuous(minimum, maximum, _, _, _) = descriptor.kind { range = (minimum, maximum) }
        return AudioFeatureBinding(source: .band(0), target: descriptor.id, outputStart: range.0, outputEnd: range.1)
    }

    func testModulatableCatalogParametersAcceptABandAndManualOnesAreRefused() throws {
        let registry = try VisualParameterCatalog.makeRegistry()
        let modulator = AudioFeatureModulator(registry: registry)
        var accepted: [ParameterID] = []
        for descriptor in registry.descriptors {
            do {
                try modulator.bind(fullRangeBinding(descriptor))
                accepted.append(descriptor.id)
                XCTAssertTrue(descriptor.modulation.isModulatable, "\(descriptor.id)")
            } catch {
                XCTAssertFalse(descriptor.modulation.isModulatable, "\(descriptor.id): \(error)")
                XCTAssertEqual(error, .notNumeric(descriptor.id, kind: descriptor.kind.name), "\(descriptor.id)")
            }
        }
        XCTAssertTrue(accepted.contains(VisualParameterIDs.bloomIntensity))
        XCTAssertEqual(accepted.count, registry.descriptors.filter(\.modulation.isModulatable).count)
        for manualOnly in [VisualParameterIDs.circularSpectrumBarCount, VisualParameterIDs.linearSpectrumOrientation, VisualParameterIDs.bloomEnabled] {
            XCTAssertFalse(accepted.contains(manualOnly), "\(manualOnly)")
        }
    }

    func testReduceFlashingCannotBeBound() throws {
        let modulator = AudioFeatureModulator(registry: try VisualParameterCatalog.makeRegistry())
        for id: ParameterID in ["settings.reduceFlashing", "safety.reduceFlashing"] {
            XCTAssertThrowsError(try modulator.bind(AudioFeatureBinding(source: .band(0), target: id, outputStart: 0, outputEnd: 1))) {
                XCTAssertEqual($0 as? AudioFeatureBindingError, .unknownTarget(id))
            }
        }
    }
}
