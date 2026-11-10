// T211: name and author, case- and diacritic-insensitive, one character, grouping order, cap.
import Foundation
import XCTest
@testable import PresetLibrary

final class PresetSearchTests: XCTestCase {
    func testMatchesNameAndAuthorFoldingCaseAndDiacritics() throws {
        let library = try Fixtures.library()
        XCTAssertEqual(library.search("cafe", limit: 200).groups.flatMap(\.presets).map(\.name), ["Café"])
        XCTAssertEqual(library.search("GEISS", limit: 200).groups.flatMap(\.presets).map(\.name), ["Beta", "Spiral 1", "Original"])
        XCTAssertFalse(library.search("z", limit: 200).groups.isEmpty, "search starts at one character")
        XCTAssertTrue(library.search("   ", limit: 200).groups.isEmpty)
    }

    func testGroupsInPackOrderAlphabeticalWithin() throws {
        let library = try Fixtures.library()
        let result = library.search("i", limit: 200)
        XCTAssertEqual(result.groups.map(\.source), ["included", "cream-of-the-crop", "projectm-classic", "milkdrop-original", "en-d"]
            .filter { source in result.groups.contains { $0.source == source } })
        let cream = try XCTUnwrap(result.groups.first { $0.source == "cream-of-the-crop" })
        XCTAssertEqual(cream.presets.map(\.name), cream.presets.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    func testCapAndTruncation() throws {
        let library = try Fixtures.large()
        let result = library.search("preset", limit: 200)
        XCTAssertEqual(result.groups.flatMap(\.presets).count, 200)
        XCTAssertTrue(result.truncated)
        XCTAssertFalse(try Fixtures.library().search("cafe", limit: 200).truncated)
    }
}
