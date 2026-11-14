// SceneArchiveSourceSafetyTests.swift — FILE-001-T15: the package reads no files, opens no network
// connection, starts no process and loads no code (FILE-001-R13).
import Foundation
import XCTest

final class SceneArchiveSourceSafetyTests: XCTestCase {
    func testSourcesUseNoFileNetworkProcessOrLoadingAPI() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SceneArchive")
        let names = try FileManager.default.contentsOfDirectory(atPath: sources.path).filter { (n: String) -> Bool in n.hasSuffix(".swift") }.sorted()
        XCTAssertEqual(names, ["SceneArchiveContentCheck.swift", "SceneArchiveError.swift", "SceneArchiveFormat.swift",
                               "SceneArchiveManifest.swift", "SceneArchivePathAudit.swift", "SceneArchiveReader.swift",   // SCN-014
                               "SceneArchiveSlides.swift", "SceneArchiveWriter.swift", "SceneStoreRemapping.swift"])
        // Split words so this file does not match its own list.
        let forbidden = ["URL" + "Session", "N" + "WConnection", "Network", "File" + "Manager", "File" + "Handle", "contentsOf" + "File",
                         "Pro" + "cess(", "dl" + "open", "dl" + "sym", "Bundle(" + "path", "f" + "open", "socket("]
        for name in names {
            let text = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
            for word in forbidden {
                XCTAssertFalse(text.contains(word), "\(name) contains \(word)")
            }
        }
    }
}
