// OSC-010-T03: the OSC route schema document (specs/282-osc-010-osc-schema-export, contract C1; S1, S2).
// The roadmap acceptance, "Export matches registry IDs and includes no private network credentials": the document's
// (address, parameter ID) rows equal the route table exactly once each, ranges equal the descriptors, and the same
// injected instant and version give the same bytes. The app leak test is OSCSchemaExportCoordinatorTests. Linux-safe.
import ParameterGraph
@testable import PerformanceControl
import XCTest

final class OSCSchemaExportTests: XCTestCase {
    private static let intensity: ParameterID = "effect.bloom.intensity"
    private static let radius: ParameterID = "effect.bloom.radius"
    private static let glowAlias = "/projectm/param/glow.intensity"
    private static let userAlias = OSCRouteAlias(address: "/fader/1", parameter: radius)
    /// 2026-11-14T09:30:05Z.
    private static let instant: Int64 = 1_794_648_605

    private static let group = ParameterGroup(id: "effect.bloom", displayName: "Glow")
    private static let descriptors: [ParameterDescriptor] = [
        ParameterDescriptor(id: intensity, displayName: "Intensity", group: group, unit: .normalized,
                            kind: .continuous(minimum: 0, maximum: 2, defaultValue: 0.5), modulation: .continuousDefault),
        ParameterDescriptor(id: radius, displayName: "Radius", group: group, unit: .fractionOfOutput,
                            kind: .continuous(minimum: 0.005, maximum: 0.06, defaultValue: 0.02), modulation: .continuousDefault),
    ]

    private func table() throws -> [OSCParameterRoute] {
        let registry = try ParameterRegistry(descriptors: Self.descriptors)
        let routable = OSCParameterRoutes.routable(in: registry, applied: [Self.intensity, Self.radius])
        return OSCParameterRoutes.table(routable: routable, builtInAliases: [(Self.glowAlias, Self.intensity)],
                                        userAliases: [Self.userAlias])
    }

    private func document(disabled: Set<String> = [], version: String = "1.1 (2)") throws -> String {
        let rows = OSCSchemaExport.rows(table: try table(), disabled: disabled,
                                        descriptors: Self.descriptors + [OSCReceiverCatalog.testValueDescriptor],
                                        displayName: { (id: ParameterID) -> String in "Name of " + id.rawValue })
        return OSCSchemaExport.document(rows: rows, appVersion: version, exportedAt: Self.instant)
    }

    /// The table rows of a document, split into unescaped cells (header and separator removed).
    private func parsedRows(_ text: String) -> [[String]] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let table = lines.filter { (line: String) -> Bool in line.hasPrefix("| ") }
        return table.dropFirst(2).map { (line: String) -> [String] in
            var cells: [String] = []
            var current = ""
            var escaped = false
            for character in line.dropFirst(2).dropLast(2) {
                if escaped { current.append(character); escaped = false; continue }
                if character == "\\" { escaped = true; continue }
                if character == "|" { cells.append(current.trimmed); current = ""; continue }
                current.append(character)
            }
            cells.append(current.trimmed)
            return cells
        }
    }

    func testExportMatchesTheRouteTableExactlyOnce() throws {
        let table = try table()
        let rows = parsedRows(try document())
        XCTAssertEqual(rows.count, table.count)
        XCTAssertTrue(rows.allSatisfy { (cells: [String]) -> Bool in cells.count == OSCSchemaExport.columns.count })
        let addresses = rows.map { (cells: [String]) -> String in cells[0] }
        for route in table {
            XCTAssertEqual(addresses.filter { (a: String) -> Bool in a == route.address }.count, 1, route.address)
        }
        let exported = Set(rows.map { (cells: [String]) -> String in cells[0] + "=" + cells[1] })
        let registry = Set(table.map { (route: OSCParameterRoute) -> String in route.address + "=" + route.parameter.rawValue })
        XCTAssertEqual(exported, registry, "including the test route, the built-in alias and the user alias")
        XCTAssertTrue(exported.contains("/fader/1=effect.bloom.radius"))
        XCTAssertEqual(addresses, table.map(\.address), "table order")
    }

    func testRangesAndUnitsMatchTheDescriptors() throws {
        let rows = parsedRows(try document(disabled: ["/fader/1"]))
        let byAddress = Dictionary(uniqueKeysWithValues: rows.map { (cells: [String]) -> (String, [String]) in (cells[0], cells) })
        let intensity = try XCTUnwrap(byAddress["/projectm/param/effect.bloom.intensity"])
        XCTAssertEqual(Array(intensity[3...8]), ["one number (f, i, h or d)", "0…1, mapped linearly", "0…2", "fraction 0-1", "standard", "on"])
        let alias = try XCTUnwrap(byAddress[Self.glowAlias])
        XCTAssertEqual(Array(alias[4...7]), ["0…1, mapped linearly", "0…2", "fraction 0-1", "built-in alias"])
        let user = try XCTUnwrap(byAddress["/fader/1"])
        XCTAssertEqual(Array(user[5...8]), ["0.005…0.06", "fraction of output", "your alias", "off"])
        let test = try XCTUnwrap(byAddress[OSCReceiverCatalog.testAddress])
        XCTAssertEqual(Array(test[1...7]), ["osc.receiver.testValue", "Name of osc.receiver.testValue", "one number (f, i, h or d)",
                                            "0…1, raw", "0…1", "none", "test"])
    }

    func testSameInstantAndVersionGiveTheSameBytes() throws {
        let first = try document()
        XCTAssertEqual(first, try document())
        XCTAssertNotEqual(first, try document(version: "1.2 (3)"))
        XCTAssertTrue(first.contains("- App version: 1.1 (2)\n- Exported: 2026-11-14T09:30:05Z\n- Routes: 5\n"), first)
        XCTAssertTrue(first.hasSuffix(" |\n"))
        XCTAssertFalse(first.contains("\r"))
    }

    func testUTCStampsAndFileName() {
        XCTAssertEqual(OSCSchemaExport.utcStamp(0), "1970-01-01T00:00:00Z")
        XCTAssertEqual(OSCSchemaExport.utcStamp(951_782_400), "2000-02-29T00:00:00Z")
        XCTAssertEqual(OSCSchemaExport.utcStamp(-1), "1969-12-31T23:59:59Z")
        XCTAssertEqual(OSCSchemaExport.utcStamp(Self.instant), "2026-11-14T09:30:05Z")
        XCTAssertEqual(OSCSchemaExport.fileName(exportedAt: Self.instant), "projectM-osc-routes-20261114-093005Z.md")
    }

    func testCellsEscapePipesAndLineBreaksAndNumbersAreLocaleFree() {
        XCTAssertEqual(OSCSchemaExport.cell("a|b\nc"), "a\\|b c")
        XCTAssertEqual(OSCSchemaExport.number(2), "2")
        XCTAssertEqual(OSCSchemaExport.number(0.25), "0.25")
        XCTAssertEqual(OSCSchemaExport.number(-3), "-3")
    }

    func testAMissingDescriptorKeepsTheRouteWithUnknownRanges() throws {
        let rows = OSCSchemaExport.rows(table: try table(), disabled: [], descriptors: [],
                                        displayName: { (id: ParameterID) -> String in id.rawValue })
        XCTAssertEqual(rows.count, try table().count)
        XCTAssertTrue(rows.allSatisfy { (row: OSCSchemaRow) -> Bool in row.valueRange == "unknown" && row.unit == "unknown" })
    }
}

extension String {
    fileprivate var trimmed: String {
        var s = Substring(self)
        while s.first == " " { s = s.dropFirst() }
        while s.last == " " { s = s.dropLast() }
        return String(s)
    }
}
