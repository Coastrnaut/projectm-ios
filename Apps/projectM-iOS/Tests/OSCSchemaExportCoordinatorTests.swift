// OSC-010-T05: Export routes… in the app (specs/282-osc-010-osc-schema-export, contract C2; S3, S4).
// The leak test seeds this device's network values the way OSC-001, OSC-005 and OSC-008 store them (receiver port,
// send destination, approved peers) plus a device name, builds the export through the coordinator, and scans the
// file for every seeded string and for IPv4, IPv6 and host:port patterns. Injected clock and version; no network.
import Foundation
import ParameterGraph
import PerformanceControl
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class OSCSchemaExportCoordinatorTests: XCTestCase {
    /// 2026-11-14T09:30:05Z.
    private static let instant = Date(timeIntervalSince1970: 1_794_648_605)
    private static let peers: [String] = ["192.168.1.20", "fe80:0:0:0:0:0:0:1", "10.0.0.77"]
    private static let sendHost = "10.20.30.40"
    private static let sendHostName = "mixer-desk.local"
    private static let sendPort = 47_811
    private static let receivePort = 53_999
    private static let deviceName = "Stage-iPad-Seven"

    private struct Harness {
        let defaults: UserDefaults
        let suite: String
        let routes: OSCRoutesCoordinator
        let export: OSCSchemaExportCoordinator
        let folder: URL
    }

    private func makeHarness(sharing folder: URL? = nil) throws -> Harness {
        let suite = "OSCSchemaExportCoordinatorTests-\(UUID().uuidString)"
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(Self.peers, forKey: OSCPeersCoordinator.approvedKey)
        defaults.set(true, forKey: OSCPeersCoordinator.enabledKey)
        defaults.set(Self.receivePort, forKey: AppSettings.oscPortKey)
        defaults.set(Self.sendHost, forKey: "settings.osc.send.host")   // OSC-005-style keys (merging in parallel)
        defaults.set(Self.sendHostName, forKey: "settings.osc.send.hostName")
        defaults.set(Self.sendPort, forKey: "settings.osc.send.port")
        defaults.set(Self.deviceName, forKey: "settings.osc.deviceName")
        defaults.set(["/fader/1=" + VisualParameterIDs.bloomRadius.rawValue], forKey: OSCRoutesCoordinator.aliasesKey)
        defaults.set(["/projectm/param/glow.knee"], forKey: OSCRoutesCoordinator.disabledRoutesKey)
        let peers = OSCPeersCoordinator(allowlist: OSCPeerAllowlist(), defaults: defaults)
        XCTAssertEqual(peers.approved.count, 3, "the seeded peers are real, loadable approved devices")
        let routes = OSCRoutesCoordinator(routable: OSCRoutesCoordinator.routable(), defaults: defaults)
        let sharing = folder ?? FileManager.default.temporaryDirectory.appendingPathComponent("OSCSchemaTest-\(UUID().uuidString)")
        let export = OSCSchemaExportCoordinator(routes: routes, store: ShareFileStore(directory: sharing), simulation: true,
                                                appVersion: "1.1 (2)", now: { () -> Date in Self.instant })
        return Harness(defaults: defaults, suite: suite, routes: routes, export: export, folder: sharing)
    }

    private func cleanUp(_ h: Harness) {
        h.defaults.removePersistentDomain(forName: h.suite)
        try? FileManager.default.removeItem(at: h.folder)
    }

    private func matches(_ pattern: String, in text: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { (m: NSTextCheckingResult) -> String? in
            Range(m.range, in: text).map { String(text[$0]) }
        }
    }

    func testExportWritesOneShareFileThatMatchesTheRoutesAndFinishDeletesIt() throws {
        let h = try makeHarness()
        defer { cleanUp(h) }
        XCTAssertTrue(h.export.export())
        let request = try XCTUnwrap(h.export.request)
        XCTAssertEqual(request.kind, .oscSchema)
        XCTAssertEqual(request.url.lastPathComponent, "projectM-osc-routes-20261114-093005Z.md")
        let text = try String(contentsOf: request.url, encoding: .utf8)
        XCTAssertEqual(text, h.export.lastText)
        XCTAssertEqual(h.export.store.fileCount(), 1)
        for route in h.routes.table {
            let row = "| " + route.address + " | " + route.parameter.rawValue + " |"
            XCTAssertEqual(text.components(separatedBy: row).count - 1, 1, route.address)
        }
        XCTAssertTrue(text.contains("| /fader/1 | effect.bloom.radius | Glow radius |"), text)
        XCTAssertTrue(text.contains("| /projectm/param/glow.knee |") && text.contains("| built-in alias | off |"), text)
        XCTAssertTrue(text.contains("- Routes: \(h.routes.table.count)\n"))

        XCTAssertFalse(h.export.export(), "one sheet at a time")
        h.export.finish(.completed)
        XCTAssertNil(h.export.request)
        XCTAssertEqual(h.export.notice, "Shared.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: request.url.path))
        XCTAssertEqual(h.export.store.fileCount(), 0)
    }

    func testExportHoldsNoPeerSendPortDeviceOrIPValues() throws {
        let h = try makeHarness()
        defer { cleanUp(h) }
        XCTAssertTrue(h.export.export())
        let text = try XCTUnwrap(h.export.lastText)
        let seeded: [String] = Self.peers + ["fe80::1", Self.sendHost, Self.sendHostName, String(Self.sendPort),
                                            String(Self.receivePort), Self.deviceName, "localhost", "127.0.0.1"]
        for value in seeded { XCTAssertFalse(text.contains(value), "leaked: " + value) }
        // The export time is the only clock-like text; drop its line before the address and port patterns.
        let body = text.split(separator: "\n").filter { (line: Substring) -> Bool in !line.hasPrefix("- Exported: ") }
            .joined(separator: "\n")
        XCTAssertEqual(try matches(#"\b\d{1,3}(\.\d{1,3}){3}\b"#, in: body), [], "IPv4")
        XCTAssertEqual(try matches(#"([0-9a-f]{1,4}:){2,7}[0-9a-f]{1,4}|[0-9a-f]{0,4}::[0-9a-f]{0,4}"#, in: body), [], "IPv6")
        XCTAssertEqual(try matches(#"[a-z0-9\].-]:\d{2,5}\b"#, in: body), [], "host:port")
        XCTAssertEqual(try matches(#"\b\d{4,5}\b"#, in: body), [], "no port-sized numbers")
        XCTAssertEqual(try matches(#"\bports?\b"#, in: text), [], "no port field")
    }

    func testAFailedWriteShowsTheNoticeAndNoSheet() throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("OSCSchemaBlocker-\(UUID().uuidString)")
        try Data("x".utf8).write(to: blocker)   // a file where the sharing folder should be
        defer { try? FileManager.default.removeItem(at: blocker) }
        let h = try makeHarness(sharing: blocker)
        defer { h.defaults.removePersistentDomain(forName: h.suite) }
        XCTAssertFalse(h.export.export())
        XCTAssertNil(h.export.request)
        XCTAssertEqual(h.export.notice, ShareFileStore.failureNotice)
    }
}
