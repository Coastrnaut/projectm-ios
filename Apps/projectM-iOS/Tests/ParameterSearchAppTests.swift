// ParameterSearchAppTests.swift — UIX-009-T05 and T07, the roadmap acceptance "Query finds matching IDs regardless
// of current layer selection" over the real MOD-001 catalog (S1, S2; specs/219-uix-009-parameter-search).
//
// * Layer independence (S1): for representative queries the IDs are identical with no visual, the circular
//   spectrum and the linear spectrum on screen, and with real settings whose visual differs.
// * Units (S2): "%", "ms" and "Hz" return exactly the catalog parameters of that unit, in catalog order.
// * Rows: values from the inspector targets or "Read only", the "on screen" mark, the empty query's groups.
// Each test makes its own UserDefaults suite and removes it; nothing is mutated in setUp/tearDown.
import Foundation
import ParameterGraph
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class ParameterSearchAppTests: XCTestCase {
    private typealias IDs = VisualParameterIDs

    private func makeSettings() throws -> (AppSettings, String) {
        let name = "ParameterSearchAppTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        return (AppSettings(defaults: defaults, systemReduceMotion: false), name)
    }

    private var catalog: [ParameterDescriptor] { ParameterSearchRows.descriptors }

    private func rowIDs(_ query: String, _ settings: AppSettings?, _ visual: VisualChoice?) -> [ParameterID] {
        ParameterSearchRows.rows(query, settings: settings, visual: visual).map(\.id)
    }

    // MARK: Acceptance: the same IDs whatever layer is selected (S1)

    func testQueryFindsTheSameIDsRegardlessOfTheLayerSelection() throws {
        let (settings, name) = try makeSettings()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        XCTAssertEqual(catalog.count, VisualParameterCatalog.descriptors.count, "the search covers the whole catalog")
        let expected: [String: [ParameterID]] = [
            "radius": [IDs.bloomRadius, IDs.particleOrbitRadius, IDs.circularSpectrumInnerRadius],
            "orientation": [IDs.linearSpectrumOrientation],
            "bars": [IDs.circularSpectrumBarCount, IDs.linearSpectrumBarCount],
            "glow": [IDs.bloomEnabled, IDs.bloomIntensity, IDs.bloomRadius, IDs.bloomThreshold, IDs.bloomKnee],
            "peak linear": [IDs.linearSpectrumCapThickness, IDs.linearSpectrumPeakHold, IDs.linearSpectrumPeakFall],
        ]
        let selections: [VisualChoice?] = [nil, .circularSpectrum, .linearSpectrum, .particleOrbit, .projectM]
        for (query, ids) in expected {
            XCTAssertEqual(ParameterSearchRows.ids(query, in: catalog), ids, "pure search: \(query)")
            for visual in selections {
                XCTAssertEqual(rowIDs(query, nil, visual), ids, "\(query) with \(String(describing: visual))")
            }
            settings.visual = .linearSpectrum
            let linear: [ParameterID] = rowIDs(query, settings, settings.visual)
            settings.visual = .circularSpectrum
            let circular: [ParameterID] = rowIDs(query, settings, settings.visual)
            XCTAssertEqual(linear, ids, "\(query): real settings, linear on screen")
            XCTAssertEqual(circular, ids, "\(query): real settings, circular on screen")
        }
    }

    // MARK: Units (S2)

    func testUnitQueriesReturnExactlyThatUnitsParameters() {
        func ofUnit(_ units: Set<ParameterUnit>) -> [ParameterID] {
            catalog.filter { (d: ParameterDescriptor) -> Bool in units.contains(d.unit) }.map(\.id)
        }
        XCTAssertEqual(rowIDs("%", nil, .linearSpectrum), ofUnit([.normalized, .fractionOfOutput]))
        XCTAssertEqual(rowIDs("ms", nil, .circularSpectrum), ofUnit([.seconds]))
        XCTAssertEqual(rowIDs("ms", nil, .circularSpectrum), [IDs.linearSpectrumPeakHold])
        XCTAssertEqual(rowIDs("Hz", nil, nil), ofUnit([.perSecond]))
        XCTAssertEqual(rowIDs("Hz", nil, nil), [IDs.linearSpectrumPeakFall])
    }

    func testDiacriticsAndCaseDoNotMatter() {
        XCTAssertEqual(rowIDs("RÁDIUS", nil, nil), rowIDs("radius", nil, nil))
        XCTAssertEqual(rowIDs("Orientación", nil, nil), [])   // a different word, not a fold of "orientation"
        XCTAssertEqual(rowIDs("ÓRIENTATION", nil, nil), [IDs.linearSpectrumOrientation])
    }

    // MARK: Rows (R5, R7)

    func testRowsShowValuesReadOnlyAndTheOnScreenMark() throws {
        let (settings, name) = try makeSettings()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        settings.glowIntensity = 0.5
        let rows: [ParameterSearchRow] = ParameterSearchRows.rows("", settings: settings, visual: .linearSpectrum)
        XCTAssertEqual(rows.map(\.id), catalog.map(\.id), "the empty query lists everything, catalog order")
        let intensity = try XCTUnwrap(rows.first { $0.id == IDs.bloomIntensity })
        XCTAssertEqual(intensity.value, "50%")
        XCTAssertEqual(intensity.group, "Glow")
        XCTAssertFalse(intensity.onScreen, "Glow is an effect, never a layer")
        let peakHold = try XCTUnwrap(rows.first { $0.id == IDs.linearSpectrumPeakHold })
        XCTAssertEqual(peakHold.value, ParameterSearchRows.readOnly, "no Settings control")
        XCTAssertTrue(peakHold.onScreen)
        XCTAssertEqual(peakHold.accessibilityValue, "Linear Spectrum, Read only, on screen")
        let inner = try XCTUnwrap(rows.first { $0.id == IDs.circularSpectrumInnerRadius })
        XCTAssertFalse(inner.onScreen)
    }

    func testEmptyQuerySectionsFollowTheCatalogGroups() {
        let sections: [ParameterSearchSection] = ParameterSearchRows.sections(settings: nil, visual: nil)
        XCTAssertEqual(sections.map(\.title), ["Circular Spectrum", "Linear Spectrum", "Glow", "Particle Orbit"])
        XCTAssertEqual(sections.flatMap(\.rows).map(\.id), catalog.map(\.id))
        XCTAssertTrue(ParameterSearchRows.rows("zzz", settings: nil, visual: nil).isEmpty, "no match: the empty state")
    }

    func testOnScreenGroupsPerVisual() {
        XCTAssertEqual(ParameterSearchRows.onScreenGroupID(for: .photo), VisualParameterCatalog.circularSpectrumGroup.id)
        XCTAssertEqual(ParameterSearchRows.onScreenGroupID(for: .linearSpectrum), VisualParameterCatalog.linearSpectrumGroup.id)
        XCTAssertEqual(ParameterSearchRows.onScreenGroupID(for: .particleOrbit), VisualParameterCatalog.particleOrbitGroup.id)
        XCTAssertNil(ParameterSearchRows.onScreenGroupID(for: .projectM))
        XCTAssertNil(ParameterSearchRows.onScreenGroupID(for: nil))
    }
}
