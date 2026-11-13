// SceneArchiveFuzzTests.swift — QA-005-T10: scene archives (FILE-001/002 reader incl. the stored
// ZIP, FILE-007 manifest check, SCN-001 decode, asset content checks) under mutated bytes. Byte,
// length-field and splice mutations hit the ZIP layer; the suite-local re-zip mutation changes one
// entry (scene, manifest or asset) and writes a checksum-valid archive again, fixing the manifest's
// record for that file, so mutations also reach the manifest and scene layers (QA-005-R6).
import Foundation
import FuzzKit
import LocalPortability
import SceneArchive
import XCTest

final class SceneArchiveFuzzTests: XCTestCase {
    static let budget = FuzzBudget(inputs: 300, maxInputBytes: 65_536)

    /// Generous read limits for the mutation itself (the reader under test applies its own).
    static let zipLimits = StoredZipLimits(maxEntries: 16, maxEntryBytes: 1 << 20, maxArchiveBytes: 1 << 22)

    static let rezip: @Sendable ([UInt8], inout FuzzRandom, Int) -> [UInt8] = { (bytes: [UInt8], rng: inout FuzzRandom, cap: Int) -> [UInt8] in
        guard let entries = try? StoredZipReader.read(Data(bytes), limits: SceneArchiveFuzzTests.zipLimits), !entries.isEmpty else { return bytes }
        var files: [(path: String, data: Data)] = entries.map { (e: StoredZipEntry) -> (path: String, data: Data) in (e.path, e.data) }
        let manifestIndex = files.firstIndex { (f: (path: String, data: Data)) -> Bool in f.path == "manifest.json" }
        let roll = rng.below(10)
        let target: Int
        if roll < 5, let scene = files.firstIndex(where: { (f: (path: String, data: Data)) -> Bool in f.path == "scene.json" }) {
            target = scene
        } else if roll < 8, let manifest = manifestIndex {
            target = manifest
        } else {
            target = rng.below(files.count)
        }
        var data = [UInt8](files[target].data)
        if files[target].path.hasSuffix(".json") {
            data = rng.chance(oneIn: 2) ? FuzzJSON.mutateValue(data, rng: &rng)
                : rng.element(of: FuzzMutation.json).apply(to: data, other: [], rng: &rng, cap: cap)
        } else {
            data = rng.element(of: FuzzMutation.generic).apply(to: data, other: [], rng: &rng, cap: cap)
        }
        files[target].data = Data(data)
        // Keep the manifest's record of a changed file honest, so the checksum layer passes.
        if let m = manifestIndex, m != target,
           var manifest = (try? JSONSerialization.jsonObject(with: files[m].data)) as? [String: Any],
           var records = manifest["files"] as? [[String: Any]] {
            for i in records.indices where records[i]["path"] as? String == files[target].path {
                records[i]["sha256"] = PortableSHA256.hex(files[target].data)
                records[i]["byteCount"] = files[target].data.count
            }
            manifest["files"] = records
            if let rewritten = try? JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]) { files[m].data = rewritten }
        }
        var out = Data()
        let writer = StoredZipWriter(modified: Date(timeIntervalSince1970: 1_794_571_200)) { (chunk: Data) in out.append(chunk) }
        do {
            for file in files { try writer.add(path: file.path, data: file.data) }
            try writer.finish()
        } catch {
            return bytes
        }
        return [UInt8](out)
    }

    func testMutatedArchivesAreReadOrRefusedWithTypedErrors() throws {
        let registry = try FuzzCorpora.registry()
        let corpus = FuzzCorpora.load("archive")
        let campaign = FuzzCampaign(name: "scene-archive", seed: 0x05CE_A001, budget: Self.budget,
                                    strategies: FuzzMutation.generic, corpus: corpus.items, customMutations: [Self.rezip])
        var reasons: Set<String> = []
        let report = campaign.run { (input: FuzzInput) -> FuzzOutcome in
            do throws(SceneArchiveError) {
                let contents = try SceneArchiveReader.read(Data(input.bytes), registry: registry)
                _ = contents.document.encoded()
                return .accepted()
            } catch {
                reasons.insert(String(String(describing: error).prefix(28)))
                return .refused()
            }
        }
        assertClean(report, minimumInputs: campaign.budget.inputs)
        XCTAssertGreaterThanOrEqual(report.accepted, corpus.items.count)
        XCTAssertGreaterThanOrEqual(reasons.count, 4, "mutations reach several layers: \(reasons.sorted())")
        print("QA-005 scene-archive: \(reasons.count) distinct refusal kinds")
    }
}
