// MOD-001-T05: catalog validation (MOD-001-R5; acceptance "Duplicate IDs fail validation and
// defaults remain in range"; MOD-001-S1, S2). One representative fixture per problem kind.
import ParameterGraph
import XCTest

let testGroup = ParameterGroup(id: "test", displayName: "Test")

func continuous(_ id: ParameterID, _ name: String = "Level", min: Double = 0, max: Double = 1,
                default value: Double = 0.5, step: Double? = nil, curve: ParameterCurve = .linear,
                group: ParameterGroup = testGroup, policy: ModulationPolicy = .continuousDefault,
                fileID: String = #fileID, line: Int = #line) -> ParameterDescriptor {
    ParameterDescriptor(id: id, displayName: name, group: group, unit: .normalized,
                        kind: .continuous(minimum: min, maximum: max, defaultValue: value, step: step, curve: curve),
                        modulation: policy, fileID: fileID, line: line)
}

func descriptor(_ id: ParameterID, _ kind: ParameterKind, policy: ModulationPolicy = .discreteManual,
                name: String = "Thing", group: ParameterGroup = testGroup) -> ParameterDescriptor {
    ParameterDescriptor(id: id, displayName: name, group: group, unit: .none, kind: kind, modulation: policy)
}

let sampleCases = [ParameterEnumCase(id: "vertical", displayName: "Vertical"),
                   ParameterEnumCase(id: "horizontal", displayName: "Horizontal")]

final class RegistryValidationTests: XCTestCase {
    private func issues(_ descriptors: [ParameterDescriptor], retired: Set<ParameterID> = []) -> [ParameterValidationIssue] {
        ParameterRegistry.validate(descriptors, retiredIDs: retired)
    }

    /// Asserts exactly one issue of `problem`, naming the parameter, and that building throws.
    private func assertSingle(_ problem: ParameterValidationIssue.Problem, _ descriptors: [ParameterDescriptor],
                              retired: Set<ParameterID> = [], mentioning extra: String? = nil,
                              file: StaticString = #filePath, line: UInt = #line) {
        let found = issues(descriptors, retired: retired)
        XCTAssertEqual(found.map(\.problem), [problem], "\(found)", file: file, line: line)
        if let issue = found.first, let id = issue.parameter, !id.rawValue.isEmpty {
            XCTAssertTrue(issue.message.contains(id.rawValue), issue.message, file: file, line: line)
        }
        if let extra { XCTAssertTrue(found.first?.message.contains(extra) == true, "\(found)", file: file, line: line) }
        XCTAssertThrowsError(try ParameterRegistry(descriptors: descriptors, retiredIDs: retired), file: file, line: line)
    }

    func testDuplicateIDNamesBothRegistrations() throws {
        let first = continuous("visual.ring.gap", "Ring gap", line: 101)
        let second = continuous("visual.ring.gap", "Bar gap", line: 202)
        let descriptors = [first, continuous("visual.ring.size"), second]
        assertSingle(.duplicateID, descriptors)
        do {
            _ = try ParameterRegistry(descriptors: descriptors)
            XCTFail("expected a duplicate-ID error")
        } catch {
            let text = error.description
            XCTAssertTrue(text.contains("visual.ring.gap"), text)
            XCTAssertTrue(text.contains("Ring gap") && text.contains("Bar gap"), text)
            XCTAssertTrue(text.contains("\(first.registrationSite.fileID):101"), text)
            XCTAssertTrue(text.contains(":202"), text)
        }
    }

    func testIdentityAndNamingProblems() {
        assertSingle(.malformedID, [continuous("Visual.gap")])
        assertSingle(.malformedID, [continuous("")])
        assertSingle(.retiredID, [continuous("visual.ring.old")], retired: ["visual.ring.old"])
        assertSingle(.emptyDisplayName, [continuous("visual.ring.gap", " ")])
        assertSingle(.malformedGroup, [continuous("visual.ring.gap", group: ParameterGroup(id: "Ring", displayName: "Ring"))])
        assertSingle(.malformedGroup, [continuous("visual.ring.gap", group: ParameterGroup(id: "ring", displayName: ""))])
        assertSingle(.conflictingGroupName,
                     [continuous("visual.ring.gap", group: ParameterGroup(id: "ring", displayName: "Ring")),
                      continuous("visual.ring.size", group: ParameterGroup(id: "ring", displayName: "Circle"))])
    }

    func testRangeAndDefaultProblems() {
        assertSingle(.nonFiniteNumber, [continuous("a.b", max: .infinity)])
        assertSingle(.nonFiniteNumber, [continuous("a.b", default: .nan)])
        assertSingle(.nonFiniteNumber, [continuous("a.b", step: .nan)])
        assertSingle(.emptyRange, [continuous("a.b", min: 1, max: 1, default: 1)])
        assertSingle(.emptyRange, [continuous("a.b", min: 2, max: 1, default: 1.5)])
        assertSingle(.emptyRange, [descriptor("a.b", .integer(minimum: 5, maximum: 1, defaultValue: 3))])
        assertSingle(.invalidStep, [continuous("a.b", step: 0)])
        assertSingle(.invalidStep, [descriptor("a.b", .integer(minimum: 0, maximum: 4, defaultValue: 0, step: 0))])
        assertSingle(.defaultOutOfRange, [continuous("a.b", default: 1.01)], mentioning: "1.01")
        assertSingle(.defaultOutOfRange, [descriptor("a.b", .integer(minimum: 0, maximum: 4, defaultValue: 5))])
        assertSingle(.defaultOutOfRange, [descriptor("a.b", .integer(minimum: 0, maximum: 8, defaultValue: 3, step: 2))])
        assertSingle(.invalidCurve, [continuous("a.b", curve: .logarithmic)])
    }

    func testEnumColorAndPolicyProblems() {
        assertSingle(.noEnumCases, [descriptor("a.b", .enumeration(cases: [], defaultValue: "x"))])
        assertSingle(.malformedEnumCase,
                     [descriptor("a.b", .enumeration(cases: [ParameterEnumCase(id: "Up", displayName: "Up")], defaultValue: "Up"))])
        assertSingle(.malformedEnumCase,
                     [descriptor("a.b", .enumeration(cases: [ParameterEnumCase(id: "up", displayName: "")], defaultValue: "up"))])
        assertSingle(.duplicateEnumCase,
                     [descriptor("a.b", .enumeration(cases: sampleCases + [sampleCases[0]], defaultValue: "vertical"))])
        assertSingle(.unknownEnumDefault, [descriptor("a.b", .enumeration(cases: sampleCases, defaultValue: "diagonal"))])
        assertSingle(.colorOutOfRange,
                     [descriptor("a.b", .color(defaultValue: ParameterColor(red: 1.5, green: 0, blue: 0)))])
        assertSingle(.colorOutOfRange,
                     [descriptor("a.b", .color(defaultValue: ParameterColor(red: .nan, green: 0, blue: 0)))])
        // Not modulatable but lists mix modes.
        assertSingle(.invalidModulationPolicy,
                     [continuous("a.b", policy: ModulationPolicy(isModulatable: false, mixModes: [.replace], allowsExternalControl: true))])
        // Modulatable with no mix mode.
        assertSingle(.invalidModulationPolicy,
                     [continuous("a.b", policy: ModulationPolicy(isModulatable: true, mixModes: [], allowsExternalControl: true))])
        // Add on a boolean.
        assertSingle(.invalidModulationPolicy,
                     [descriptor("a.b", .boolean(defaultValue: false),
                                 policy: ModulationPolicy(isModulatable: true, mixModes: [.replace, .add], allowsExternalControl: true))])
        // Duplicate mix mode.
        assertSingle(.invalidModulationPolicy,
                     [continuous("a.b", policy: ModulationPolicy(isModulatable: true, mixModes: [.add, .add], allowsExternalControl: true))])
    }

    func testEveryIssueIsReportedInRegistrationOrder() {
        let descriptors = [continuous("a.one", default: 2), continuous("Bad"), continuous("a.three", min: 1, max: 0, default: 0.5)]
        XCTAssertEqual(issues(descriptors).map(\.problem), [.defaultOutOfRange, .malformedID, .emptyRange])
        do {
            _ = try ParameterRegistry(descriptors: descriptors)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error.issues.count, 3)
            XCTAssertEqual(error.description.split(separator: "\n").count, 4) // heading + one line per issue
        }
    }

    func testValidCatalogBuildsWithDefaultsInRange() throws {
        let descriptors = [
            continuous("a.level", step: 0.01),
            continuous("a.frequency", min: 20, max: 20_000, default: 440, curve: .logarithmic),
            descriptor("a.count", .integer(minimum: 0, maximum: 8, defaultValue: 4, step: 2)),
            descriptor("a.on", .boolean(defaultValue: true)),
            descriptor("a.orientation", .enumeration(cases: sampleCases, defaultValue: "vertical")),
            descriptor("a.tint", .color(defaultValue: ParameterColor(red: 1, green: 0.5, blue: 0, alpha: 1)), policy: .none),
        ]
        let registry = try ParameterRegistry(descriptors: descriptors)
        XCTAssertEqual(registry.descriptors.count, 6)
        XCTAssertTrue(ParameterRegistry.validate(descriptors).isEmpty)
    }
}
