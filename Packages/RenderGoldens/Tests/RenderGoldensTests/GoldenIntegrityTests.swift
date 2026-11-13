// QA-002-T16 (US4; QA-002-R6, R14, S4; contract G5): the committed golden set is complete, matches its
// hashes and fits the budget; doctored copies fail. Manifest canonical form. No GPU, no PNG decoding:
// runs on Linux and every CI host, so a missing or stale golden fails CI even where nothing renders.
import Foundation
import GoldenImages
import XCTest

final class GoldenIntegrityTests: XCTestCase {
    private var scratch: URL?

    override func tearDownWithError() throws {
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
    }

    /// A copy of the committed goldens in a temporary folder.
    private func copyOfGoldens() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("qa002-integrity-\(UUID().uuidString)", isDirectory: true)
        scratch = root
        try FileManager.default.copyItem(at: GoldenPaths.goldens, to: root)
        return root
    }

    func testCommittedSetIsCompleteAndSmall() throws {
        let issues = GoldenIntegrity.check(goldensRoot: GoldenPaths.goldens)
        XCTAssertEqual(issues.map(\.description), [])
        for platform in GoldenPlatformClass.allCases {
            XCTAssertTrue(FileManager.default.fileExists(atPath: GoldenPaths.goldens(platform).appendingPathComponent(GoldenManifest.fileName).path),
                          "goldens for \(platform.rawValue) are committed")
        }
        let bytes = GoldenIntegrity.totalBytes(goldensRoot: GoldenPaths.goldens)
        XCTAssertLessThan(bytes, GoldenIntegrity.budgetBytes)
        print("QA-002 golden set: \(bytes) bytes (budget \(GoldenIntegrity.budgetBytes))")
    }

    func testDoctoredCopiesFail() throws {
        let root = try copyOfGoldens()
        let folder = root.appendingPathComponent(GoldenPlatformClass.macOS.rawValue, isDirectory: true)
        let manifest = try GoldenManifest.decode(Data(contentsOf: folder.appendingPathComponent(GoldenManifest.fileName)))
        let first = try XCTUnwrap(manifest.entries.first)
        let second = try XCTUnwrap(manifest.entries.dropFirst().first)
        // Missing file.
        try FileManager.default.removeItem(at: folder.appendingPathComponent(first.file))
        // Wrong hash.
        var bytes = try Data(contentsOf: folder.appendingPathComponent(second.file))
        bytes.append(0)
        try bytes.write(to: folder.appendingPathComponent(second.file))
        // Unlisted file.
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent("stray.png"))
        let issues = GoldenIntegrity.check(goldensRoot: root)
        XCTAssertTrue(issues.contains(.missingFile(platform: "macos", file: first.file)), "\(issues)")
        XCTAssertTrue(issues.contains(.fileHashMismatch(platform: "macos", file: second.file)), "\(issues)")
        XCTAssertTrue(issues.contains(.unlistedFile(platform: "macos", file: "stray.png")), "\(issues)")
    }

    func testIncompleteManifestAndBudgetFail() throws {
        let root = try copyOfGoldens()
        let folder = root.appendingPathComponent(GoldenPlatformClass.iOSSimulator.rawValue, isDirectory: true)
        let url = folder.appendingPathComponent(GoldenManifest.fileName)
        var manifest = try GoldenManifest.decode(Data(contentsOf: url))
        let dropped = manifest.entries.removeLast()
        try manifest.encoded().write(to: url)
        let issues = GoldenIntegrity.check(goldensRoot: root)
        XCTAssertTrue(issues.contains(.missingEntry(platform: "ios-simulator", file: dropped.file)), "\(issues)")
        XCTAssertTrue(issues.contains(.unlistedFile(platform: "ios-simulator", file: dropped.file)), "\(issues)")
        // A big stray file breaks the budget.
        try Data(count: GoldenIntegrity.budgetBytes).write(to: folder.appendingPathComponent("huge.png"))
        XCTAssertTrue(GoldenIntegrity.check(goldensRoot: root).contains { (i: GoldenIntegrityIssue) -> Bool in
            if case .overBudget = i { true } else { false }
        })
    }

    func testManifestIsCanonical() throws {
        for platform in GoldenPlatformClass.allCases {
            let url = GoldenPaths.goldens(platform).appendingPathComponent(GoldenManifest.fileName)
            let data = try Data(contentsOf: url)
            let manifest = try GoldenManifest.decode(data)
            XCTAssertEqual(manifest.platform, platform.rawValue)
            XCTAssertEqual(manifest.formatVersion, GoldenManifest.currentFormatVersion)
            #if canImport(Darwin)
            XCTAssertEqual(try manifest.encoded(), data, "rewriting an unchanged manifest gives the same bytes")
            #endif
            var shuffled = manifest
            shuffled.entries.reverse()
            XCTAssertEqual(try GoldenManifest.decode(shuffled.encoded()).entries, manifest.entries, "canonical order")
            for entry in manifest.entries {
                XCTAssertEqual(entry.pixelSHA256.count, 64)
                XCTAssertEqual(entry.osSensitive, GoldenSceneCatalog.run(named: entry.scene)?.osSensitive)
            }
        }
    }

    func testUpsertReplacesInPlace() {
        var manifest = GoldenManifest(platform: "macos", recordedOS: "27.2", recordedGPU: "test")
        let a = GoldenManifestEntry(scene: "b", frame: 7, width: 128, height: 96, file: "b-128x96-f7.png", pixelSHA256: "1",
                                    fileSHA256: "1", osSensitive: false)
        let b = GoldenManifestEntry(scene: "a", frame: 7, width: 128, height: 96, file: "a-128x96-f7.png", pixelSHA256: "2",
                                    fileSHA256: "2", osSensitive: false)
        manifest.upsert(a)
        manifest.upsert(b)
        XCTAssertEqual(manifest.entries.map(\.scene), ["a", "b"])
        var a2 = a
        a2.pixelSHA256 = "3"
        manifest.upsert(a2)
        XCTAssertEqual(manifest.entries.count, 2)
        XCTAssertEqual(manifest.entry(scene: "b", width: 128, frame: 7)?.pixelSHA256, "3")
    }
}
