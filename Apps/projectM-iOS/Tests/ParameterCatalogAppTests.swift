// MOD-001-T10: the app's settings stay inside the parameter catalog (MOD-001-R10, R13; spec
// Clarifications Q1). The settings keep their own storage in this row; this test fails if their
// defaults or offered choices drift outside the registered parameters.
import ParameterGraph
import VisualEffects
import VisualGenerators
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class ParameterCatalogAppTests: XCTestCase {
    private typealias IDs = VisualParameterIDs

    private func enumCases(_ registry: ParameterRegistry, _ id: ParameterID) throws -> (ids: [String], value: String) {
        guard case let .enumeration(cases, value)? = registry.descriptor(for: id)?.kind else {
            throw XCTSkip("\(id) is not an enum")
        }
        return (cases.map(\.id), value)
    }

    private func continuous(_ registry: ParameterRegistry, _ id: ParameterID) throws -> (range: ClosedRange<Double>, value: Double) {
        guard case let .continuous(min, max, value, _, _)? = registry.descriptor(for: id)?.kind else {
            throw XCTSkip("\(id) is not continuous")
        }
        return (min...max, value)
    }

    func testSettingsChoicesAndDefaultsLieInTheCatalog() throws {
        let registry = try VisualParameterCatalog.makeRegistry()
        let suite = "ParameterCatalogAppTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)

        // Bars (shared by both spectra): every choice and the default are cases of both bar counts.
        for id in [IDs.circularSpectrumBarCount, IDs.linearSpectrumBarCount] {
            let bars = try enumCases(registry, id)
            XCTAssertEqual(Set(AppSettings.circularSpectrumBarChoices.map(String.init)), Set(bars.ids), "\(id)")
            XCTAssertEqual(String(settings.circularSpectrumBars), bars.value, "\(id)")
        }

        // Linear spectrum orientation and spacing.
        let orientation = try enumCases(registry, IDs.linearSpectrumOrientation)
        XCTAssertEqual(settings.linearSpectrumOrientation.rawValue, orientation.value)
        let spacing = try continuous(registry, IDs.linearSpectrumSpacing)
        XCTAssertEqual(settings.linearSpectrumSpacing, spacing.value)
        for choice in AppSettings.linearSpectrumSpacingChoices {
            XCTAssertTrue(spacing.range.contains(choice.value), choice.title)
        }

        // Glow: the settings' defaults are the bloom descriptors' defaults.
        XCTAssertEqual(registry.descriptor(for: IDs.bloomEnabled)?.defaultValue, .boolean(settings.glowEnabled))
        XCTAssertEqual(try continuous(registry, IDs.bloomIntensity).value, settings.glowIntensity)
        XCTAssertEqual(try continuous(registry, IDs.bloomRadius).value, settings.glowRadius)
        XCTAssertEqual(try continuous(registry, IDs.bloomThreshold).value, settings.glowThreshold)
    }
}
