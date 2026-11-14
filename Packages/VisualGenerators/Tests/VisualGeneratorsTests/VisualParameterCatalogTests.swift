// MOD-001-T08: the app's parameter catalog (MOD-001-R10, R11; S3, S4; contract C6). It validates,
// lists exactly the documented parameters, keeps every default in range, and cannot drift from the
// configuration types it describes.
import ParameterGraph
import VisualEffects
import VisualGenerators
import VisualParameters
import XCTest

final class VisualParameterCatalogTests: XCTestCase {
    private typealias IDs = VisualParameterIDs

    private func range(_ d: ParameterDescriptor?, file: StaticString = #filePath, line: UInt = #line)
        -> (min: Double, max: Double, value: Double)? {
        guard case let .continuous(min, max, value, _, _)? = d?.kind else {
            XCTFail("\(String(describing: d?.id)) is not continuous", file: file, line: line)
            return nil
        }
        return (min, max, value)
    }

    private func cases(_ d: ParameterDescriptor?) -> (ids: [String], value: String)? {
        guard case let .enumeration(cases, value)? = d?.kind else { return nil }
        return (cases.map(\.id), value)
    }

    func testCatalogValidatesWithTheDocumentedIDsInOrder() throws {
        let registry = try VisualParameterCatalog.makeRegistry()
        XCTAssertEqual(registry.ids.map(\.rawValue), [
            "visual.circularSpectrum.barCount", "visual.circularSpectrum.innerRadius", "visual.circularSpectrum.gap",
            "visual.linearSpectrum.barCount", "visual.linearSpectrum.orientation", "visual.linearSpectrum.spacing",
            "visual.linearSpectrum.capThickness", "visual.linearSpectrum.peakHold", "visual.linearSpectrum.peakFall",
            "effect.bloom.enabled", "effect.bloom.intensity", "effect.bloom.radius", "effect.bloom.threshold",
            "effect.bloom.knee", "visual.particleOrbit.radius",
        ])
        XCTAssertEqual(try VisualParameterCatalog.makeRegistry().ids, registry.ids)
        XCTAssertEqual(registry.groups.map(\.id), ["visual.circularSpectrum", "visual.linearSpectrum", "effect.bloom", "visual.particleOrbit"])
        XCTAssertTrue(VisualParameterCatalog.retiredIDs.isEmpty)
        // Reduce flashing is a safety setting and is never registered (MOD-001-R11).
        XCTAssertFalse(registry.ids.contains { $0.rawValue.lowercased().contains("flash") })
    }

    func testEveryDefaultIsFiniteAndInRange() throws {
        for d in try VisualParameterCatalog.makeRegistry().descriptors {
            switch d.kind {
            case let .continuous(min, max, value, step, _):
                XCTAssertTrue(value.isFinite && min.isFinite && max.isFinite, "\(d.id)")
                XCTAssertTrue(min < max && (min...max).contains(value), "\(d.id)")
                if let step { XCTAssertGreaterThan(step, 0, "\(d.id)") }
            case let .integer(min, max, value, _):
                XCTAssertTrue((min...max).contains(value), "\(d.id)")
            case let .enumeration(cases, value):
                XCTAssertTrue(cases.contains { $0.id == value }, "\(d.id)")
            case .boolean, .color:
                break
            }
        }
    }

    func testRangesAndDefaultsMatchTheConfigurationTypes() throws {
        let r = try VisualParameterCatalog.makeRegistry()
        let barIDs = SpectrumBarCount.allCases.map { String($0.rawValue) }

        // Circular spectrum.
        let circular = CircularSpectrumConfiguration()
        XCTAssertEqual(cases(r.descriptor(for: IDs.circularSpectrumBarCount))?.ids, barIDs)
        XCTAssertEqual(cases(r.descriptor(for: IDs.circularSpectrumBarCount))?.value, String(circular.barCount.rawValue))
        let inner = try XCTUnwrap(range(r.descriptor(for: IDs.circularSpectrumInnerRadius)))
        XCTAssertEqual([inner.min, inner.max, inner.value],
                       [CircularSpectrumConfiguration.innerRadiusRange.lowerBound,
                        CircularSpectrumConfiguration.innerRadiusRange.upperBound, circular.innerRadius])
        let gap = try XCTUnwrap(range(r.descriptor(for: IDs.circularSpectrumGap)))
        XCTAssertEqual([gap.min, gap.max, gap.value],
                       [CircularSpectrumConfiguration.gapRange.lowerBound, CircularSpectrumConfiguration.gapRange.upperBound, circular.gap])

        // Linear spectrum.
        typealias L = LinearSpectrumConfiguration
        let linear = L()
        XCTAssertEqual(cases(r.descriptor(for: IDs.linearSpectrumBarCount))?.ids, barIDs)
        XCTAssertEqual(cases(r.descriptor(for: IDs.linearSpectrumBarCount))?.value, String(linear.barCount.rawValue))
        XCTAssertEqual(cases(r.descriptor(for: IDs.linearSpectrumOrientation))?.ids, LinearSpectrumOrientation.allCases.map(\.rawValue))
        XCTAssertEqual(cases(r.descriptor(for: IDs.linearSpectrumOrientation))?.value, linear.orientation.rawValue)
        let linearChecks: [(ParameterID, ClosedRange<Double>, Double)] = [
            (IDs.linearSpectrumSpacing, L.spacingRange, L.defaultSpacing),
            (IDs.linearSpectrumCapThickness, L.capThicknessRange, L.defaultCapThickness),
            (IDs.linearSpectrumPeakHold, L.peakHoldRange, L.defaultPeakHoldSeconds),
            (IDs.linearSpectrumPeakFall, L.peakFallRange, L.defaultPeakFallPerSecond),
        ]
        for (id, expectedRange, expectedDefault) in linearChecks {
            let got = try XCTUnwrap(range(r.descriptor(for: id)))
            XCTAssertEqual([got.min, got.max, got.value], [expectedRange.lowerBound, expectedRange.upperBound, expectedDefault], "\(id)")
        }
        XCTAssertEqual(linear.spacing, L.defaultSpacing)

        // Bloom (Float constants, compared as Double(Float)).
        typealias B = BloomParameters
        XCTAssertEqual(r.descriptor(for: IDs.bloomEnabled)?.kind, .boolean(defaultValue: B().enabled))
        let bloomChecks: [(ParameterID, ClosedRange<Float>, Float)] = [
            (IDs.bloomIntensity, B.intensityRange, B.defaultIntensity),
            (IDs.bloomRadius, B.radiusRange, B.defaultRadius),
            (IDs.bloomThreshold, B.thresholdRange, B.defaultThreshold),
            (IDs.bloomKnee, B.kneeRange, B.defaultKnee),
        ]
        for (id, expectedRange, expectedDefault) in bloomChecks {
            let got = try XCTUnwrap(range(r.descriptor(for: id)))
            XCTAssertEqual([got.min, got.max, got.value],
                           [Double(expectedRange.lowerBound), Double(expectedRange.upperBound), Double(expectedDefault)], "\(id)")
        }

        // Particle orbit (VIS-009-R4).
        typealias O = ParticleOrbitConfiguration
        let orbit = try XCTUnwrap(range(r.descriptor(for: IDs.particleOrbitRadius)))
        XCTAssertEqual([orbit.min, orbit.max, orbit.value], [O.radiusRange.lowerBound, O.radiusRange.upperBound, O().radius])
        XCTAssertEqual(r.descriptor(for: IDs.particleOrbitRadius)?.unit, .fractionOfOutput)
    }

    func testUnitsAndModulationPolicies() throws {
        for d in try VisualParameterCatalog.makeRegistry().descriptors {
            XCTAssertTrue(d.modulation.allowsExternalControl, "\(d.id)")
            switch d.kind {
            case .continuous:
                XCTAssertEqual(d.modulation, .continuousDefault, "\(d.id)")
            default:
                XCTAssertEqual(d.modulation, .discreteManual, "\(d.id)")
            }
        }
        let r = try VisualParameterCatalog.makeRegistry()
        XCTAssertEqual(r.descriptor(for: IDs.linearSpectrumPeakHold)?.unit, .seconds)
        XCTAssertEqual(r.descriptor(for: IDs.linearSpectrumPeakFall)?.unit, .perSecond)
        XCTAssertEqual(r.descriptor(for: IDs.circularSpectrumBarCount)?.unit, .count)
        XCTAssertEqual(r.descriptor(for: IDs.bloomRadius)?.unit, .fractionOfOutput)
    }
}
