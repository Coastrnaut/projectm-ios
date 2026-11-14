// LibraryBackupFuzzTests.swift — FILE-005-T12 (FILE-005-S4): the library backup reader (FILE-005
// contract C2: stored ZIP, checksummed manifest, every record's own reader) under mutated bytes. The
// seeds are written by the real writer from records made here; the re-zip mutation changes one entry
// and fixes its manifest record, so mutations also reach the record readers.
import Foundation
import FuzzKit
import LibraryBackup
import LocalPortability
import PresetLibrary
import SceneFormat
import XCTest

final class LibraryBackupFuzzTests: XCTestCase {
    static let budget = FuzzBudget(inputs: 300, maxInputBytes: 65_536)
    static let zipLimits = StoredZipLimits(maxEntries: 32, maxEntryBytes: 1 << 20, maxArchiveBytes: 1 << 22)

    static func seed(withPreset: Bool) throws -> [UInt8] {
        let scene = SceneDocument(id: "5CE7E000-0000-4000-8000-000000000001", name: "Fuzz scene",
                                  layers: [SceneLayer(instance: 1, content: .linearSpectrum, values: [:])])
        var contents = LibraryContents()
        contents.scenes[scene.id] = Data(scene.encoded())
        contents.currentScene = Data(scene.encoded())
        contents.collections = [PresetCollection(id: "00000000-0000-4000-8000-000000000050", name: "Fuzz", presetIDs: ["included/a.milk"])]
        contents.settings = ["settings.osc.port": .int(9_000), "favorites": .strings(["included/a.milk"]), "settings.camera.zoom": .double(1.5)]
        contents.photos["0000A000-0000-4000-8000-000000000001.png"] = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
        if withPreset {
            let text = Data("MILKDROP_PRESET_VERSION=201\n[preset00]\nfRating=3.0\nzoom=1.01\nper_frame_1=wave_r = 0.5;\n".utf8)
            let bytes = [UInt8](text)
            let record = UserPreset(id: "user/00000000-0000-4000-8000-000000000001", name: "Fuzz", author: "", originalFileName: "Fuzz.milk",
                                    sha256: ContentHash.sha256Hex(bytes), blobHash: ContentHash.gitBlobSHA1Hex(bytes), byteCount: bytes.count,
                                    importedAt: Date(timeIntervalSince1970: 1_794_571_200), state: .pending,
                                    license: PresetLicenseMetadata(authorFromFileName: false, linesFound: []))
            contents.presets = [LibraryPreset(record: record, text: text)]
        }
        return [UInt8](try LibraryBackupWriter.write(contents, appVersion: "fuzz", createdAt: Date(timeIntervalSince1970: 1_794_571_200)))
    }

    static let rezip: @Sendable ([UInt8], inout FuzzRandom, Int) -> [UInt8] = { (bytes: [UInt8], rng: inout FuzzRandom, cap: Int) -> [UInt8] in
        guard let entries = try? StoredZipReader.read(Data(bytes), limits: LibraryBackupFuzzTests.zipLimits), !entries.isEmpty else { return bytes }
        var files: [(path: String, data: Data)] = entries.map { (e: StoredZipEntry) -> (path: String, data: Data) in (e.path, e.data) }
        let manifestIndex = files.firstIndex { (f: (path: String, data: Data)) -> Bool in f.path == "manifest.json" }
        let target = rng.below(files.count)
        var data = [UInt8](files[target].data)
        if files[target].path.hasSuffix(".json") || files[target].path.hasSuffix(".scene") {
            data = rng.chance(oneIn: 2) ? FuzzJSON.mutateValue(data, rng: &rng)
                : rng.element(of: FuzzMutation.json).apply(to: data, other: [], rng: &rng, cap: cap)
        } else {
            data = rng.element(of: FuzzMutation.generic).apply(to: data, other: [], rng: &rng, cap: cap)
        }
        files[target].data = Data(data)
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

    func testMutatedBackupsAreReadOrRefusedWithTypedErrors() throws {
        let corpus: [[UInt8]] = [try Self.seed(withPreset: false), try Self.seed(withPreset: true)]
        let campaign = FuzzCampaign(name: "library-backup", seed: 0x0F11_E005, budget: Self.budget,
                                    strategies: FuzzMutation.generic, corpus: corpus, customMutations: [Self.rezip])
        var reasons: Set<String> = []
        let report = campaign.run { (input: FuzzInput) -> FuzzOutcome in
            do throws(LibraryBackupError) {
                let backup = try LibraryBackupReader.read(Data(input.bytes))
                _ = LibraryRecords(backup.contents).digest
                return .accepted()
            } catch {
                reasons.insert(String(String(describing: error).prefix(28)))
                return .refused()
            }
        }
        assertClean(report, minimumInputs: campaign.budget.inputs)
        XCTAssertGreaterThanOrEqual(report.accepted, corpus.count)
        XCTAssertGreaterThanOrEqual(reasons.count, 3, "mutations reach several layers: \(reasons.sorted())")
        print("FILE-005 library-backup: \(reasons.count) distinct refusal kinds")
    }
}
