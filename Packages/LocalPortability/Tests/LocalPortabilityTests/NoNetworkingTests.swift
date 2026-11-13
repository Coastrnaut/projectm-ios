// PRE-014-T09 (R15, S1 "without network"): the export and read path contains no networking API.
// The forbidden names are assembled at run time so this file itself does not trip
// scripts/check_compliance.py.
import XCTest

final class NoNetworkingTests: XCTestCase {
    private var packages: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func sources() throws -> [URL] {
        let portability = packages.appendingPathComponent("LocalPortability/Sources/LocalPortability")
        let userPresets = packages.appendingPathComponent("PresetLibrary/Sources/PresetLibrary/UserPresets")
        var files = try FileManager.default.contentsOfDirectory(at: portability, includingPropertiesForKeys: nil)
        for name in ["UserPresetArchive.swift", "UserPresetExport.swift", "UserPresetLibrary.swift", "ContentHash.swift"] {
            files.append(userPresets.appendingPathComponent(name))
        }
        return files.filter { $0.pathExtension == "swift" }
    }

    func testExportPathUsesNoNetworkingAPI() throws {
        let forbidden = ["URL" + "Session", "CF" + "Network", "import " + "Network", "NW" + "Connection", "NW" + "Listener",
                         "NW" + "PathMonitor", "CF" + "Socket", "socket" + "(", "Web" + "Kit", "URL" + "Request", "Stream" + ".getStreamsToHost"]
        let files = try sources()
        XCTAssertGreaterThanOrEqual(files.count, 8, "the scan must see the export sources")
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for name in forbidden {
                XCTAssertFalse(text.contains(name), "\(file.lastPathComponent) mentions \(name)")
            }
        }
    }
}
