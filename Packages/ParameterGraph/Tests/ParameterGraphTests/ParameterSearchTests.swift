// ParameterSearchTests.swift — UIX-009-R2 to R4 (research D2-D4; contract S1-S3). A small fixture catalog shaped
// like MOD-001's; the app's ParameterSearchAppTests run the same rules over the real catalog.
import ParameterGraph
import XCTest

final class ParameterSearchTests: XCTestCase {
    private static let spectrum = ParameterGroup(id: "visual.spectrum", displayName: "Spectrum")
    private static let glow = ParameterGroup(id: "effect.bloom", displayName: "Glow")
    private static let orbit = ParameterGroup(id: "visual.orbit", displayName: "Particle Orbit")

    private static func continuous(_ id: String, _ name: String, _ group: ParameterGroup, _ unit: ParameterUnit) -> ParameterDescriptor {
        ParameterDescriptor(id: ParameterID(id), displayName: name, group: group, unit: unit,
                            kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0.5, step: 0.01), modulation: .continuousDefault)
    }

    private static let catalog: [ParameterDescriptor] = [
        continuous("visual.spectrum.innerRadius", "Inner radius (of half the shorter side)", spectrum, .fractionOfOutput),
        continuous("visual.spectrum.peakHold", "Peak hold", spectrum, .seconds),
        continuous("visual.spectrum.peakFall", "Peak fall rate (bar lengths)", spectrum, .perSecond),
        ParameterDescriptor(id: "visual.spectrum.orientation", displayName: "Orientation", group: spectrum, unit: .none,
                            kind: .enumeration(cases: [ParameterEnumCase(id: "vertical", displayName: "Vertical")], defaultValue: "vertical"),
                            modulation: .discreteManual),
        continuous("effect.bloom.radius", "Radius (of the shorter side)", glow, .fractionOfOutput),
        continuous("effect.bloom.intensity", "Intensity", glow, .normalized),
        continuous("visual.orbit.radius", "Radius (of half the shorter side)", orbit, .fractionOfOutput),
        continuous("visual.orbit.spin", "Spin", orbit, .degrees),
    ]

    private func ids(_ query: String) -> [String] {
        ParameterSearch.ids(query, in: Self.catalog).map(\.rawValue)
    }

    func testBlankQueryListsEveryParameterInOrder() {
        XCTAssertEqual(ids(""), Self.catalog.map(\.id.rawValue))
        XCTAssertEqual(ids("   \t "), Self.catalog.map(\.id.rawValue))
    }

    func testRankingNamePrefixThenSubstringThenGroupThenUnit() {
        // "radius": two name-prefix hits (catalog order), then the substring hit.
        XCTAssertEqual(ids("radius"), ["effect.bloom.radius", "visual.orbit.radius", "visual.spectrum.innerRadius"])
        // "glow" matches only the group; "bloom" the group ID.
        XCTAssertEqual(ids("glow"), ["effect.bloom.radius", "effect.bloom.intensity"])
        XCTAssertEqual(ids("bloom"), ids("glow"))
        // "peak" prefixes two names; "orbit" is the group of two.
        XCTAssertEqual(ids("peak"), ["visual.spectrum.peakHold", "visual.spectrum.peakFall"])
        let hits: [ParameterSearchHit] = ParameterSearch.search("orbit", in: Self.catalog)
        XCTAssertEqual(hits.map(\.tier), [.group, .group])
    }

    func testEveryWordMustMatchAndWorstWordRanks() {
        XCTAssertEqual(ids("radius glow"), ["effect.bloom.radius"])
        XCTAssertEqual(ids("radius %"), ["effect.bloom.radius", "visual.orbit.radius", "visual.spectrum.innerRadius"])
        XCTAssertEqual(ParameterSearch.search("radius %", in: Self.catalog).first?.tier, .unit)
        XCTAssertEqual(ids("radius nothing"), [])
    }

    func testUnitQueries() {
        XCTAssertEqual(ids("%"), ["visual.spectrum.innerRadius", "effect.bloom.radius", "effect.bloom.intensity", "visual.orbit.radius"])
        XCTAssertEqual(ids("ms"), ["visual.spectrum.peakHold"])
        XCTAssertEqual(ids("Hz"), ["visual.spectrum.peakFall"])
        XCTAssertEqual(ids("°"), ["visual.orbit.spin"])
        XCTAssertEqual(ids("per second"), ["visual.spectrum.peakFall"])
        XCTAssertEqual(ParameterSearch.search("seconds", in: Self.catalog).map(\.tier), [.unit])
    }

    func testCaseAndDiacriticsAreIgnored() {
        XCTAssertEqual(ids("RÁDIUS"), ids("radius"))
        XCTAssertEqual(ids("Glöw"), ids("glow"))
        XCTAssertEqual(ids("ＩＮＴＥＮＳＩＴＹ"), ["effect.bloom.intensity"])   // full-width
        XCTAssertEqual(ParameterSearch.fold("Pérçent"), "percent")
    }

    func testChoicesAndValuesAreNotSearched() {
        XCTAssertEqual(ids("vertical"), [])
        XCTAssertEqual(ids("0.5"), [])
    }

    func testUnitTermsAreFoldedAndNoneHasNone() {
        XCTAssertTrue(ParameterUnit.none.searchTerms.isEmpty)
        for unit in ParameterUnit.allCases {
            for term in unit.searchTerms { XCTAssertEqual(term, ParameterSearch.fold(term), "\(unit): \(term)") }
        }
    }
}
