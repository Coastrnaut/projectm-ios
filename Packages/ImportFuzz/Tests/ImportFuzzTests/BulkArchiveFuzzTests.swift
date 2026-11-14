// BulkArchiveFuzzTests.swift — PRE-013-T15 (specs/174-pre-013-bulk-import; contract C1): ordinary
// archives for "Import Folder or Archive…" under mutated bytes. `LooseZipReader` must never trap: an
// archive is either refused as a whole or every entry gets a verdict, and every `.file` entry either
// reads back with exactly its declared size or throws. The corpus is built here (stored entries of
// preset text written for this repository).
import Foundation
import FuzzKit
import LocalPortability
import XCTest

final class BulkArchiveFuzzTests: XCTestCase {
    static let budget = FuzzBudget(inputs: 300, maxInputBytes: 32_768)

    private func corpus() throws -> [[UInt8]] {
        let text = "MILKDROP_PRESET_VERSION=201\nPSVERSION=2\n[preset00]\nfDecay=0.96\nzoom=1.01\nper_frame_1=rot = 0.02*sin(time);\n"
        var archives: [[UInt8]] = []
        for count in [1, 3, 6] {
            var output = Data()
            let writer = StoredZipWriter(modified: Date(timeIntervalSince1970: 1_800_000_000),
                                         sink: { (chunk: Data) in output.append(chunk) })
            for index in 0..<count {
                let path: String = index % 2 == 0 ? "Pack/Preset \(index).milk" : "notes \(index).txt"
                try writer.add(path: path, data: Data((text + "// \(index)\n").utf8))
            }
            try writer.finish()
            archives.append([UInt8](output))
        }
        return archives
    }

    func testMutatedArchivesNeverTrapAndEveryEntryGetsAVerdict() throws {
        let campaign = FuzzCampaign(name: "bulk-archive", seed: 0x0513_0001, budget: Self.budget,
                                    strategies: FuzzMutation.generic, corpus: try corpus())
        let report = campaign.run { (input: FuzzInput) -> FuzzOutcome in
            let data = Data(input.bytes)
            guard let entries = try? LooseZipReader.entries(data) else { return .refused() }
            var violation: String?
            for entry in entries where entry.verdict == .file {
                if let read = try? LooseZipReader.data(of: entry, in: data, limit: 1 << 20), read.count != entry.size {
                    violation = "\(entry.path): read \(read.count) bytes, declared \(entry.size)"
                }
            }
            return .accepted(work: entries.count, violation: violation)
        }
        assertClean(report, minimumInputs: campaign.budget.inputs)
        XCTAssertGreaterThan(report.accepted, 0)
        XCTAssertGreaterThan(report.refused, 0)
    }
}
