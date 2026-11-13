// SceneRepairTests.swift — SCN-012-T04 to T06: the malformed fixture table (each fixture → its exact
// entries, flags and actions, or the right refusal), repairs (validate cleanly, idempotent, order of
// the given actions irrelevant, unknown content and the scene ID kept) and a seeded fuzz over mutated
// scenes and bytes (a report for each, repaired documents encode and decode). CPU only, runs on Linux;
// no clock. Owner rule 7: the whole file runs in about a second.
import Compositor
import Foundation
import ParameterGraph
@testable import SceneFormat
import VisualParameters
import XCTest

final class SceneRepairTests: XCTestCase {
    private typealias IDs = VisualParameterIDs
    private typealias Group = SceneRepairReport.Group
    private typealias Severity = SceneRepairReport.Severity

    private static let photoKey = "photo"
    private static let missingPhotoID = "11111111-2222-4333-8444-555555555555"

    private func registry() throws -> ParameterRegistry { try SceneFixtures.registry() }

    private func scene(_ layers: [SceneLayer], name: String = "Fixture", parameters: [ParameterID: ParameterValue] = [:],
                       bindings: [SceneBinding] = [], modulation: SceneModulation = SceneModulation(),
                       assets: [String: SceneAsset] = [:]) -> SceneDocument {
        SceneDocument(id: SceneFixtures.sceneID, name: name, layers: layers, parameters: parameters, bindings: bindings,
                      modulation: modulation, assets: assets)
    }

    private func binding(_ source: String, _ target: ParameterID) -> SceneBinding {
        SceneBinding(sourceID: source, target: target, mapping: LinearMapping(outputStart: 0, outputEnd: 1))
    }

    private func connection(_ source: SceneNodeRef, _ target: SceneNodeRef, _ input: String = ModulationEdge.valueInput) -> SceneConnection {
        SceneConnection(source: source, target: target, input: input)
    }

    /// (group, severity, code, actions) of every entry, in report order.
    private func shape(_ report: SceneRepairReport) -> [String] {
        report.entries.map { (e: SceneRepairReport.Entry) -> String in
            "\(e.group.rawValue)|\(e.severity.title)|\(e.code)|" + e.actions.map(\.rawValue).joined(separator: ",")
        }
    }

    private func errors(_ document: SceneDocument, _ registry: ParameterRegistry,
                        _ assets: (any SceneAssetAvailability)? = FakeAvailability()) -> [SceneIssue] {
        document.validate(registry: registry, assets: assets).filter(\.isError)
    }

    // MARK: Refusals (S1)

    func testRefusalsProduceACannotOpenEntryWithoutActions() throws {
        let registry = try registry()
        let minimal = SceneFixtures.minimalText.bytes
        let newer = SceneFixtures.minimalText.replacingOccurrences(of: "\"version\":1", with: "\"version\":2").bytes
        let badVersion = SceneFixtures.minimalText.replacingOccurrences(of: "\"version\":1", with: "\"version\":\"one\"").bytes
        let duplicateKey = SceneFixtures.minimalText.replacingOccurrences(of: "\"name\":\"Empty\"", with: "\"name\":\"A\",\"name\":\"B\"").bytes
        let oversize = [UInt8](repeating: 0x20, count: SceneLimits.maximumBytes + 1)
        let cases: [(String, [UInt8], Group, String)] = [
            ("truncated", Array(minimal.dropLast(9)), .damagedFile, "refusal.notJSON"),
            ("oversize", oversize, .damagedFile, "refusal.tooLarge"),
            ("empty", [], .damagedFile, "refusal.empty"),
            ("duplicate key", duplicateKey, .damagedFile, "refusal.duplicateKey"),
            ("newer version", newer, .unsupportedVersion, "refusal.newerVersion"),
            ("invalid version", badVersion, .unsupportedVersion, "refusal.invalidVersion"),
        ]
        for (name, bytes, group, code) in cases {
            let opening = SceneRepairReport.open(bytes: bytes, registry: registry)
            XCTAssertNil(opening.document, name)
            XCTAssertEqual(shape(opening.report), ["\(group.rawValue)|Cannot open|\(code)|"], name)
            XCTAssertTrue(opening.report.cannotOpen, name)
            XCTAssertFalse(opening.report.canOpenAsIs, name)
            XCTAssertFalse(opening.report.canOpenWithRepairs, name)
            XCTAssertTrue(opening.report.needsReview, name)
            XCTAssertEqual(opening.report.statusText, "Cannot open", name)
            XCTAssertEqual(opening.report.entries.first?.item, "Scene file", name)
        }
        let report = SceneRepairReport.open(bytes: newer, registry: registry).report
        XCTAssertEqual(report.entries.first?.ifOpened, "Made by a newer version of the app: update the app to open it.")
        XCTAssertEqual(report.groups, [.unsupportedVersion])
    }

    // MARK: The fixture table (S1)

    private struct Fixture {
        let name: String
        let document: SceneDocument
        let shape: [String]
        let canOpenAsIs: Bool
        let canOpenWithRepairs: Bool
        let needsReview: Bool
    }

    private func fixtures() throws -> [Fixture] {
        let photoAsset: [String: SceneAsset] = [Self.photoKey: .photo(storeID: Self.missingPhotoID)]
        let cycle = SceneModulation(generators: [ModulationGenerator(id: "lfo.one", displayName: "LFO", inputs: ["rate"])],
                                    connections: [connection(.generator("lfo.one"), .parameter(IDs.bloomKnee)),
                                                  connection(.parameter(IDs.bloomKnee), .generator("lfo.one"), "rate")])
        let duplicateGenerators = SceneModulation(generators: [ModulationGenerator(id: "lfo.one", displayName: "A"),
                                                               ModulationGenerator(id: "lfo.one", displayName: "B")],
                                                  connections: [connection(.generator("lfo.one"), .parameter(IDs.bloomKnee))])
        return [
            Fixture(name: "duplicate instance IDs",
                    document: scene([SceneLayer(instance: 1, content: .circularSpectrum), SceneLayer(instance: 1, content: .linearSpectrum)]),
                    shape: ["damagedFile|Needs repair|duplicateInstance|renumberLayers"],
                    canOpenAsIs: false, canOpenWithRepairs: true, needsReview: true),
            Fixture(name: "missing photo",
                    document: scene([SceneLayer(instance: 1, content: .photo(asset: Self.photoKey)),
                                     SceneLayer(instance: 2, content: .circularSpectrum)], assets: photoAsset),
                    shape: ["missingMedia|Opens with a problem|missingAsset|dropMissingMedia"],
                    canOpenAsIs: true, canOpenWithRepairs: true, needsReview: true),
            Fixture(name: "dangling asset",
                    document: scene([SceneLayer(instance: 1, content: .photo(asset: "nope"))]),
                    shape: ["missingMedia|Needs repair|danglingAsset|removeBrokenLayers"],
                    canOpenAsIs: false, canOpenWithRepairs: true, needsReview: true),
            Fixture(name: "dangling binding target",
                    document: scene([SceneLayer(instance: 1, content: .circularSpectrum)],
                                    bindings: [binding("audio.onset", "visual.future.thing")]),
                    shape: ["invalidMappings|Opens with a problem|orphanedBinding|dropInvalidMappings"],
                    canOpenAsIs: true, canOpenWithRepairs: true, needsReview: true),
            Fixture(name: "modulation cycle", document: scene([SceneLayer(instance: 1, content: .circularSpectrum)], modulation: cycle),
                    shape: ["invalidMappings|Opens with a problem|rejectedConnection|dropInvalidMappings"],
                    canOpenAsIs: true, canOpenWithRepairs: true, needsReview: true),
            Fixture(name: "invalid generator declarations",
                    document: scene([SceneLayer(instance: 1, content: .circularSpectrum)], modulation: duplicateGenerators),
                    shape: ["invalidMappings|Needs repair|invalidModulation|dropInvalidModulation",
                            "invalidMappings|Opens with a problem|rejectedConnection|dropInvalidMappings"],
                    canOpenAsIs: false, canOpenWithRepairs: true, needsReview: true),
            Fixture(name: "unknown layer kind",
                    document: scene([SceneLayer(instance: 1, content: .circularSpectrum), SceneLayer(instance: 2, content: .unknown(kind: "particles.v9"))]),
                    shape: ["unknownContent|Opens with a problem|unknownLayerKind|keepUnknownContent"],
                    canOpenAsIs: true, canOpenWithRepairs: false, needsReview: true),
            Fixture(name: "unknown material",
                    document: scene([SceneLayer(instance: 1, content: .material(id: "material.nope"))]),
                    shape: ["damagedFile|Needs repair|unknownMaterial|removeBrokenLayers"],
                    canOpenAsIs: false, canOpenWithRepairs: true, needsReview: true),
            Fixture(name: "invalid name", document: scene([SceneLayer(instance: 1, content: .circularSpectrum)], name: "  "),
                    shape: ["damagedFile|Needs repair|invalidName|renameScene"],
                    canOpenAsIs: false, canOpenWithRepairs: true, needsReview: true),
            Fixture(name: "clamped value (a note only)",
                    document: scene([SceneLayer(instance: 1, content: .circularSpectrum)], parameters: [IDs.bloomIntensity: .continuous(99)]),
                    shape: ["valuesAdjusted|Note|parameterClamped|"],
                    canOpenAsIs: true, canOpenWithRepairs: false, needsReview: false),
            Fixture(name: "clean", document: scene([SceneLayer(instance: 1, content: .circularSpectrum)]),
                    shape: [], canOpenAsIs: true, canOpenWithRepairs: false, needsReview: false),
        ]
    }

    func testEachFixtureHasItsExactReport() throws {
        let registry = try registry()
        for fixture in try fixtures() {
            let report = SceneRepairReport(document: fixture.document, registry: registry, assets: FakeAvailability())
            XCTAssertEqual(shape(report), fixture.shape, fixture.name)
            XCTAssertEqual(report.canOpenAsIs, fixture.canOpenAsIs, fixture.name)
            XCTAssertEqual(report.canOpenWithRepairs, fixture.canOpenWithRepairs, fixture.name)
            XCTAssertEqual(report.needsReview, fixture.needsReview, fixture.name)
            XCTAssertFalse(report.cannotOpen, fixture.name)
            // The same report from the encoded bytes (decode → report).
            let opening = SceneRepairReport.open(bytes: fixture.document.encoded(), registry: registry, assets: FakeAvailability())
            XCTAssertEqual(opening.document, fixture.document, fixture.name)
            XCTAssertEqual(shape(opening.report), fixture.shape, fixture.name)
        }
    }

    func testEntriesNameTheItemAndWhatHappensIfOpened() throws {
        let registry = try registry()
        let document = scene([SceneLayer(instance: 1, content: .photo(asset: Self.photoKey)), SceneLayer(instance: 2, content: .circularSpectrum)],
                             bindings: [binding("audio.onset", "visual.future.thing")],
                             assets: [Self.photoKey: .photo(storeID: Self.missingPhotoID)])
        let report = SceneRepairReport(document: document, registry: registry, assets: FakeAvailability())
        XCTAssertEqual(report.groups, [.missingMedia, .invalidMappings])
        XCTAssertEqual(report.entries.map(\.item), ["Photo \"photo\"", "Mapping 1 (audio.onset → visual.future.thing)"])
        XCTAssertEqual(report.entries.map(\.ifOpened), ["Its layer draws nothing until the media is stored again.",
                                                        "It is kept in the scene but has no effect."])
        XCTAssertEqual(report.repairActions, [.dropMissingMedia, .dropInvalidMappings])
        XCTAssertEqual(report.statusText, "Opens with problems")
    }

    func testAnInvalidSceneIDCannotOpenAndHasNoRepair() throws {
        let registry = try registry()
        var document = scene([SceneLayer(instance: 1, content: .circularSpectrum), SceneLayer(instance: 1, content: .linearSpectrum)])
        document.id = "not-a-uuid"
        let report = SceneRepairReport(document: document, registry: registry)
        XCTAssertEqual(shape(report), ["damagedFile|Cannot open|invalidSceneID|", "damagedFile|Needs repair|duplicateInstance|renumberLayers"])
        XCTAssertTrue(report.cannotOpen)
        XCTAssertFalse(report.canOpenWithRepairs, "a scene that cannot open offers no repair")
        XCTAssertEqual(report.entries.first?.item, "Scene ID")
    }

    // MARK: Repairs (S2)

    func testRepairedFixturesValidateCleanlyAndRepairsAreIdempotent() throws {
        let registry = try registry()
        for fixture in try fixtures() {
            let report = SceneRepairReport(document: fixture.document, registry: registry, assets: FakeAvailability())
            let repaired = fixture.document.repairing(with: report, registry: registry, assets: FakeAvailability())
            XCTAssertEqual(errors(repaired, registry), [], fixture.name)
            XCTAssertEqual(repaired.id, fixture.document.id, "\(fixture.name): the scene ID is kept")
            let again = repaired.repairing(SceneRepairAction.allCases, registry: registry, assets: FakeAvailability())
            XCTAssertEqual(again, repaired, "\(fixture.name): repairing twice equals once")
            let reversed = fixture.document.repairing(report.repairActions.reversed(), registry: registry, assets: FakeAvailability())
            XCTAssertEqual(reversed, repaired, "\(fixture.name): the given order does not matter")
            let afterReport = SceneRepairReport(document: repaired, registry: registry, assets: FakeAvailability())
            XCTAssertFalse(afterReport.entries.contains { (e: SceneRepairReport.Entry) -> Bool in
                e.actions.contains { (a: SceneRepairAction) -> Bool in a.changesDocument }
            }, "\(fixture.name): nothing left to repair: \(afterReport.entries)")
        }
    }

    func testEachRepairTouchesOnlyItsItems() throws {
        let registry = try registry()
        let unknown = SceneLayer(instance: 7, content: .unknown(kind: "particles.v9"), values: ["rate": 30])
        let good = binding("audio.onset", IDs.bloomIntensity)
        let document = scene([SceneLayer(instance: 3, content: .photo(asset: Self.photoKey)),
                              SceneLayer(instance: 3, content: .circularSpectrum), unknown,
                              SceneLayer(instance: 0, content: .linearSpectrum)],
                             parameters: [IDs.bloomEnabled: .boolean(true)],
                             bindings: [good, binding("audio.onset", "visual.future.thing"), binding("audio.onset", IDs.bloomIntensity)],
                             assets: [Self.photoKey: .photo(storeID: Self.missingPhotoID)])
        let report = SceneRepairReport(document: document, registry: registry, assets: FakeAvailability())
        XCTAssertEqual(report.repairActions, [.renumberLayers, .dropMissingMedia, .dropInvalidMappings, .keepUnknownContent])
        let repaired = document.repairing(with: report, registry: registry, assets: FakeAvailability())
        XCTAssertEqual(repaired.layers.map(\.kind), ["spectrum.circular", "particles.v9", "spectrum.linear"],
                       "the photo layer goes; the unknown layer stays")
        XCTAssertEqual(repaired.layers.map(\.instance), [1, 7, 2],
                       "the first holder of ID 3 keeps it; the duplicate 3 and the 0 get the smallest free IDs (1, 2)")
        XCTAssertEqual(repaired.layers[1], unknown)
        XCTAssertEqual(repaired.assets, [:])
        XCTAssertEqual(repaired.bindings, [good], "the orphaned and the duplicate-target mappings go")
        XCTAssertEqual(repaired.parameters, document.parameters)
        XCTAssertEqual(errors(repaired, registry), [])
        // Each action alone changes only its own items.
        let mediaOnly = document.repairing([.dropMissingMedia], registry: registry, assets: FakeAvailability())
        XCTAssertEqual(mediaOnly.bindings, document.bindings)
        XCTAssertEqual(mediaOnly.layers.count, 3)
        XCTAssertEqual(document.repairing([.keepUnknownContent], registry: registry), document, "keep changes nothing")
    }

    func testOtherRepairsMakeErrorsOpenable() throws {
        let registry = try registry()
        let document = scene([SceneLayer(instance: 1, content: .circularSpectrum, values: ["": 1, "ok": 2]),
                              SceneLayer(instance: 2, content: .photo(asset: "pic")),
                              SceneLayer(instance: 3, content: .photo(asset: "pic")),
                              SceneLayer(instance: 4, content: .text(asset: "pic"))],
                             name: "",
                             parameters: ["..bad": .boolean(true), IDs.bloomEnabled: .boolean(true)],
                             assets: ["pic": .photo(storeID: SceneFixtures.photoID), "Bad": .photo(storeID: "../x")])
        let report = SceneRepairReport(document: document, registry: registry, assets: FakeAvailability())
        XCTAssertTrue(report.canOpenWithRepairs, "\(report.entries)")
        XCTAssertEqual(report.repairActions, [.renameScene, .removeBrokenLayers, .removeExtraLayers, .dropInvalidValues])
        let repaired = document.repairing(with: report, registry: registry, assets: FakeAvailability())
        XCTAssertEqual(errors(repaired, registry), [])
        XCTAssertEqual(repaired.name, SceneRepairAction.untitledName)
        XCTAssertEqual(repaired.layers.map(\.instance), [1, 2], "the text layer on a photo asset and the second photo go")
        XCTAssertEqual(repaired.layers[0].values, ["ok": 2])
        XCTAssertEqual(repaired.parameters, [IDs.bloomEnabled: .boolean(true)])
        XCTAssertEqual(Set(repaired.assets.keys), ["pic"])
    }

    // MARK: Fuzz (S3)

    private struct Seeded {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(max(bound, 1)))
        }
    }

    private func base() throws -> SceneDocument {
        scene([SceneLayer(instance: 1, content: .circularSpectrum, values: ["glowBoost": 0.5]),
               SceneLayer(instance: 2, content: .photo(asset: "photo1")),
               SceneLayer(instance: 3, content: .text(asset: "caption")),
               SceneLayer(instance: 4, content: .material(id: "material.plasma")),
               SceneLayer(instance: 9, content: .unknown(kind: "particles.v9"))],
              parameters: [IDs.bloomEnabled: .boolean(true), IDs.circularSpectrumGap: .continuous(0.1)],
              bindings: [binding("audio.onset", IDs.bloomIntensity), binding("audio.bandMean", IDs.circularSpectrumGap)],
              modulation: SceneModulation(generators: [ModulationGenerator(id: "lfo.one", displayName: "LFO", inputs: ["rate"])],
                                          connections: [connection(.generator("lfo.one"), .parameter(IDs.bloomRadius))]),
              assets: ["photo1": .photo(storeID: SceneFixtures.photoID), "caption": SceneAsset(.text(spec: try SceneFixtures.textSpec()))])
    }

    private func mutate(_ d: inout SceneDocument, _ r: inout Seeded) {
        let n = d.layers.count
        switch r.next(14) {
        case 0: if n > 1 { d.layers[r.next(n)].instance = d.layers[r.next(n)].instance }
        case 1: if n > 0 { d.layers[r.next(n)].instance = 0 }
        case 2: d.layers.append(SceneLayer(instance: UInt64(20 + r.next(5)), content: .unknown(kind: "future.\(r.next(3))")))
        case 3: d.layers.append(SceneLayer(instance: UInt64(30 + r.next(5)), content: .photo(asset: ["photo1", "nope", "caption"][r.next(3)])))
        case 4: d.assets[["photo1", "caption"][r.next(2)]] = nil
        case 5: d.bindings.append(binding(["audio.onset", "audio.nope", "bad id"][r.next(3)], ["visual.future.thing", IDs.bloomRadius, "..x"][r.next(3)]))
        case 6: d.modulation.connections.append(connection(.parameter(IDs.bloomRadius), .generator("lfo.one"), "rate"))
        case 7: d.layers.append(SceneLayer(instance: UInt64(40 + r.next(5)), content: .material(id: ["material.nope", "material.plasma"][r.next(2)])))
        case 8: d.name = ["", "\u{7}", String(repeating: "n", count: 130), "Fine"][r.next(4)]
        case 9: if n > 0 { d.layers[r.next(n)].values[["", "ok"][r.next(2)]] = 1 }
        case 10: d.parameters[ParameterID(["..bad", "visual.future.x", IDs.bloomIntensity.rawValue][r.next(3)])] = .continuous(Double(r.next(300)))
        case 11: d.modulation.generators.append(ModulationGenerator(id: ["lfo.one", "lfo.two"][r.next(2)], displayName: "G"))
        case 12: d.assets["photo1"] = .photo(storeID: ["../x", Self.missingPhotoID, SceneFixtures.photoID][r.next(3)])
        default: if n > 0 { d.layers.remove(at: r.next(n)) }
        }
    }

    func testSeededMutationsAlwaysReportAndRepairsDecodeAgain() throws {
        let registry = try registry()
        let base = try base()
        var random = Seeded(state: 0x5C3_012)
        var repairedCount = 0
        for case_ in 0..<500 {
            var document = base
            for _ in 0..<(1 + random.next(3)) { mutate(&document, &random) }
            let report = SceneRepairReport(document: document, registry: registry, assets: FakeAvailability())
            if case_ % 4 == 0 {   // every fourth through the bytes too: encode, flip or cut, open
                var bytes = document.encoded()
                if !bytes.isEmpty {
                    let at = random.next(bytes.count)
                    if random.next(2) == 0 { bytes[at] = UInt8(truncatingIfNeeded: random.next(256)) } else { bytes.removeSubrange(at...) }
                }
                let opening = SceneRepairReport.open(bytes: bytes, registry: registry, assets: FakeAvailability())
                XCTAssertFalse(opening.report.entries.isEmpty && opening.document == nil, "case \(case_): a refusal has an entry")
            }
            guard report.canOpenWithRepairs else { continue }
            let repaired = document.repairing(with: report, registry: registry, assets: FakeAvailability())
            XCTAssertEqual(errors(repaired, registry), [], "case \(case_): \(report.entries)")
            XCTAssertEqual(repaired.repairing(SceneRepairAction.allCases, registry: registry, assets: FakeAvailability()), repaired,
                           "case \(case_): idempotent")
            XCTAssertNoThrow(try SceneDocument.decode(repaired.encoded()), "case \(case_)")
            repairedCount += 1
        }
        XCTAssertGreaterThan(repairedCount, 100, "the fuzz exercises repairs")
    }
}
