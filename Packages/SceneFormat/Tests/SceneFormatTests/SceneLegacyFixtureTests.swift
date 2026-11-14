// SceneLegacyFixtureTests.swift — every golden legacy fixture loads into the current schema without
// data loss (SCN-013-T06; the roadmap row's acceptance; SCN-013-R12, R13, S1; contract M7).
//
// Fixtures: Fixtures/legacy/manifest.json lists each input (v<N>/…), its version, its source (the real
// writer that produced the shape) and the expected current-schema document (expected/…). Version 1 is
// the only version ever written, so every row is version 1 today; QA-004 runs the same manifest.
// "No data loss": every leaf of the input is present in the output with an equal value, or the
// migration audit log lists it (renamed → present at the new path; removed or transformed → listed).
import Foundation
import ParameterGraph
@testable import SceneFormat
import XCTest

struct LegacyFixtureManifest: Decodable {
    struct Row: Decodable {
        let file: String
        let version: Int
        let source: String
        let expected: String
        let covers: [String]
    }

    let format: String
    let fixtures: [Row]

    static var directory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/legacy", isDirectory: true)
    }

    static func load() throws -> LegacyFixtureManifest {
        try JSONDecoder().decode(LegacyFixtureManifest.self, from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
    }

    static func bytes(_ relative: String) throws -> [UInt8] {
        [UInt8](try Data(contentsOf: directory.appendingPathComponent(relative)))
    }
}

/// Flattens a JSON value into leaf paths; empty containers are leaves ("{}" / "[]").
enum SceneLeaves {
    enum Leaf: Equatable {
        case null, bool(Bool), number(Double?, String), string(String), emptyObject, emptyArray

        /// Numbers compare by value (`1` equals `1.0`); a number too large for a double by its text.
        func matches(_ other: Leaf) -> Bool {
            switch (self, other) {
            case let (.number(a, ta), .number(b, tb)): a != nil && b != nil ? a == b : ta == tb
            default: self == other
            }
        }
    }

    static func flatten(_ value: SceneJSON, _ path: String = "$", into out: inout [String: Leaf]) {
        switch value {
        case .null: out[path] = .null
        case let .bool(b): out[path] = .bool(b)
        case let .number(n): out[path] = .number(n.doubleValue, n.text)
        case let .string(s): out[path] = .string(s)
        case let .array(items):
            if items.isEmpty { out[path] = .emptyArray }
            for (i, item) in items.enumerated() { flatten(item, ScenePath.index(path, i), into: &out) }
        case let .object(o):
            if o.isEmpty { out[path] = .emptyObject }
            for (key, item) in o { flatten(item, ScenePath.key(path, key), into: &out) }
        }
    }

    static func leaves(_ value: SceneJSON) -> [String: Leaf] {
        var out: [String: Leaf] = [:]
        flatten(value, into: &out)
        return out
    }

    /// Input leaves missing from the output and not accounted for by the log (empty = no data loss).
    static func lost(input: SceneJSON, output: SceneJSON, log: [SceneMigrationLogEntry]) -> [String] {
        let outputLeaves = leaves(output)
        var lost: [String] = []
        for (path, leaf) in leaves(input).sorted(by: { (a: (key: String, value: Leaf), b: (key: String, value: Leaf)) -> Bool in a.key < b.key }) {
            var target = path
            var listed = false
            for entry in log {
                let c = entry.change
                guard ScenePathItem.isWithin(target, c.path) else { continue }
                switch c.kind {
                case .renamed:
                    if let newPath = c.newPath { target = newPath + target.dropFirst(c.path.count) }
                case .removed, .transformed, .version:
                    listed = true
                case .added:
                    break
                }
            }
            if listed { continue }
            guard let out = outputLeaves[target], leaf.matches(out) else {
                // An empty input container may gain items in the output (decoder defaults): not a loss.
                if leaf == .emptyObject || leaf == .emptyArray, outputLeaves.keys.contains(where: { (k: String) -> Bool in k.hasPrefix(target) }) {
                    continue
                }
                lost.append(path)
                continue
            }
        }
        return lost
    }
}

final class SceneLegacyFixtureTests: XCTestCase {
    func testManifestListsEveryInputFileAndRealSources() throws {
        let manifest = try LegacyFixtureManifest.load()
        XCTAssertEqual(manifest.format, "projectm-ios.scene-legacy-fixtures")
        XCTAssertGreaterThanOrEqual(manifest.fixtures.count, 11)
        var onDisk: Set<String> = []
        let base = LegacyFixtureManifest.directory
        for folder in try FileManager.default.contentsOfDirectory(atPath: base.path) where folder.hasPrefix("v") {
            for name in try FileManager.default.contentsOfDirectory(atPath: base.appendingPathComponent(folder).path) {
                onDisk.insert(folder + "/" + name)
            }
        }
        XCTAssertEqual(Set(manifest.fixtures.map(\.file)), onDisk, "every input has a manifest row")
        for row in manifest.fixtures {
            XCTAssertTrue(row.file.hasPrefix("v\(row.version)/"), "\(row.file) lives in its version's folder")
            XCTAssertLessThanOrEqual(row.version, SceneDocument.currentVersion)
            XCTAssertGreaterThanOrEqual(row.version, SceneMigrator.standard.oldestVersion)
            XCTAssertFalse(row.source.isEmpty)
        }
        // Version 1 is the only version ever written (research SCN-013-D1): no invented history.
        XCTAssertEqual(Set(manifest.fixtures.map(\.version)), [1])
    }

    /// The row's acceptance: every fixture loads into the current schema, equals its expected document
    /// byte for byte, and loses no input value.
    func testEveryFixtureLoadsIntoTheCurrentSchemaWithoutDataLoss() throws {
        for row in try LegacyFixtureManifest.load().fixtures {
            let input = try LegacyFixtureManifest.bytes(row.file)
            let expected = try LegacyFixtureManifest.bytes(row.expected)
            let decoded = try SceneDocument.decode(input)
            XCTAssertEqual(decoded.migration.sourceVersion, row.version, row.file)
            XCTAssertEqual(decoded.migration.targetVersion, SceneDocument.currentVersion, row.file)
            XCTAssertEqual(decoded.document.encoded(), expected, "\(row.file) encodes to \(row.expected)")
            XCTAssertEqual(try SceneDocument.decode(expected).document.encoded(), expected, "\(row.expected) is canonical")
            let lost = SceneLeaves.lost(input: try SceneJSON.parse(input), output: decoded.document.json, log: decoded.migration.log)
            XCTAssertEqual(lost, [], "\(row.file) loses no value")
        }
    }

    /// The rows together cover every current layer kind, asset type, binding feature, modulation part,
    /// media reference and unknown content; each row's declared tags are true of its document.
    func testFixturesCoverTheWholeCurrentSchema() throws {
        var all: Set<String> = []
        for row in try LegacyFixtureManifest.load().fixtures {
            let document = try SceneDocument.decode(try LegacyFixtureManifest.bytes(row.file)).document
            let found = Self.coverage(document, raw: try SceneJSON.parse(try LegacyFixtureManifest.bytes(row.file)))
            XCTAssertTrue(Set(row.covers).isSubset(of: found), "\(row.file) declares \(Set(row.covers).subtracting(found))")
            all.formUnion(found)
        }
        var required: Set<String> = Set(SceneLayerContent.knownKinds.map { (k: String) -> String in "layer:" + k })
        required.formUnion(["layer:unknown", "asset:photo", "asset:video", "asset:text", "asset:generatorGraph", "parameters",
                            "binding:mix.replace", "binding:mix.add", "binding:mix.multiply", "binding:envelope", "binding:expression",
                            "modulation:generator", "modulation:connection", "media:photo", "media:video", "unknown:field",
                            "unknown:audioFeature", "empty", "hand-written"])
        XCTAssertEqual(required.subtracting(all), [], "uncovered")
    }

    static func coverage(_ d: SceneDocument, raw: SceneJSON) -> Set<String> {
        var c: Set<String> = []
        for layer in d.layers {
            c.insert(layer.content.isKnown ? "layer:" + layer.kind : "layer:unknown")
            if !layer.extra.isEmpty && layer.content.isKnown { c.insert("unknown:field") }
        }
        for asset in d.assets.values {
            switch asset.kind {
            case .photo: c.formUnion(["asset:photo", "media:photo"])
            case .video: c.formUnion(["asset:video", "media:video"])
            case .logo: c.formUnion(["asset:logo", "media:photo"])   // MED-010
            case .text: c.insert("asset:text")
            case .generatorGraph: c.insert("asset:generatorGraph")
            case .unknown: c.insert("asset:unknown")
            }
            if !asset.extra.isEmpty { c.insert("unknown:field") }
        }
        if !d.parameters.isEmpty { c.insert("parameters") }
        for b in d.bindings {
            c.insert("binding:mix." + b.mix.rawValue)
            if b.envelope != .none { c.insert("binding:envelope") }
            if b.expression != nil { c.insert("binding:expression") }
            if !b.extra.isEmpty { c.insert("unknown:field") }
            if AudioFeatureSource(id: b.sourceID) == nil { c.insert("unknown:audioFeature") }
        }
        if !d.modulation.generators.isEmpty { c.insert("modulation:generator") }
        if !d.modulation.connections.isEmpty { c.insert("modulation:connection") }
        if !d.extra.isEmpty { c.insert("unknown:field") }
        if d.layers.isEmpty && d.bindings.isEmpty && d.assets.isEmpty && d.parameters.isEmpty { c.insert("empty") }
        if SceneJSONWriter.write(raw) != SceneJSONWriter.write(d.json) || !(raw.objectValue?["layers"]?.arrayValue ?? []).allSatisfy({ (l: SceneJSON) -> Bool in l.objectValue?["composite"] != nil }) {
            c.insert("hand-written")
        }
        return c
    }

    // MARK: The no-data-loss check is not vacuous

    func testDataLossCheckHonoursTheLogAndCatchesUnloggedLoss() throws {
        let input = try SceneJSON.parse(try LegacyFixtureManifest.bytes("v1/all-kinds.scene.json"))
        // A logged rename (synthetic, test-only step): nothing is lost.
        let logged = try SceneMigrator(steps: [SceneMigrationTests.v1to2], targetVersion: 2).migrate(input)
        XCTAssertEqual(SceneLeaves.lost(input: input, output: logged.root, log: logged.record.log), [])
        // The same rename without its log entry loses every layer value.
        let silent = SceneMigrationStep(fromVersion: 1, identifier: "test-silent", summary: "drops values without logging") {
            (object: [String: SceneJSON], recorder: inout SceneMigrationRecorder) throws(SceneMigrationError) -> [String: SceneJSON] in
            var o = object
            o["layers"] = .array((o["layers"]?.arrayValue ?? []).map { (l: SceneJSON) -> SceneJSON in
                var lo = l.objectValue ?? [:]
                lo.removeValue(forKey: "values")
                return .object(lo)
            })
            return o
        }
        let unlogged = try SceneMigrator(steps: [silent], targetVersion: 2).migrate(input)
        let lost = SceneLeaves.lost(input: input, output: unlogged.root, log: unlogged.record.log)
        XCTAssertTrue(lost.contains("$.layers[1].values.glowBoost"), "\(lost)")
        XCTAssertTrue(lost.contains("$.layers[5].values.mix"), "\(lost)")
    }
}
