// PRE-007-T02: collection names, limits and the pure ordering rules (PRE-007-R6, R9, R10, R14).
import Foundation
import XCTest
@testable import PresetLibrary

final class PresetCollectionTests: XCTestCase {
    // MARK: - Names (R9)

    func testNamesAreTrimmedAndLineBreaksBecomeSpaces() throws {
        XCTAssertEqual(try PresetCollectionName.normalized("  Friday set \n"), "Friday set")
        XCTAssertEqual(try PresetCollectionName.normalized("Line one\nline two\r\nthree"), "Line one line two three")
        XCTAssertEqual(try PresetCollectionName.normalized("\tשבת 🎉"), "שבת 🎉")
    }

    func testEmptyNamesAreRefused() {
        for raw in ["", "   ", "\n\t ", "\u{00A0}"] {
            XCTAssertThrowsError(try PresetCollectionName.normalized(raw), raw) {
                XCTAssertEqual($0 as? PresetCollectionError, .emptyName)
            }
        }
    }

    func testTheLengthLimitCountsUserPerceivedCharacters() throws {
        XCTAssertEqual(PresetCollectionLimits.maxNameLength, 60)
        let sixty = String(repeating: "a", count: 60)
        XCTAssertEqual(try PresetCollectionName.normalized(sixty), sixty)
        XCTAssertThrowsError(try PresetCollectionName.normalized(sixty + "b")) {
            XCTAssertEqual($0 as? PresetCollectionError, .nameTooLong(limit: 60))
        }
        // A family emoji is one character but many scalars; 60 of them are accepted.
        let emoji = String(repeating: "👨‍👩‍👧‍👦", count: 60)
        XCTAssertEqual(try PresetCollectionName.normalized(emoji).count, 60)
        // Surrounding white space does not count.
        XCTAssertEqual(try PresetCollectionName.normalized("  " + sixty + "  "), sixty)
    }

    func testTheComparisonKeyIgnoresCaseAndDiacritics() {
        XCTAssertEqual(PresetCollectionName.key("Chill"), PresetCollectionName.key("chíLL"))
        XCTAssertEqual(PresetCollectionName.key(" Chill "), PresetCollectionName.key("chill"))
        XCTAssertNotEqual(PresetCollectionName.key("Chill"), PresetCollectionName.key("Chill 2"))
    }

    func testLimits() {
        XCTAssertEqual(PresetCollectionLimits.maxCollections, 100)
        XCTAssertEqual(PresetCollectionLimits.maxPresetsPerCollection, 1_000)
        XCTAssertEqual(PresetCollectionLimits.maxFileBytes, 16 * 1_024 * 1_024)
    }

    func testEveryErrorHasAMessage() {
        let errors: [PresetCollectionError] = [.emptyName, .nameTooLong(limit: 60), .duplicateName, .unknownCollection,
                                               .tooManyCollections(limit: 100), .collectionFull(limit: 1_000), .invalidOrder,
                                               .newerFormat(version: 2), .saveFailed]
        for error in errors { XCTAssertFalse(error.message.isEmpty, "\(error)") }
        XCTAssertTrue(PresetCollectionError.nameTooLong(limit: 60).message.contains("60"))
        XCTAssertTrue(PresetCollectionError.tooManyCollections(limit: 100).message.contains("100"))
        XCTAssertTrue(PresetCollectionError.collectionFull(limit: 1_000).message.contains("1,000"))
    }

    // MARK: - Moving (R6, R7)

    func testMovedFollowsTheListControlRule() {
        let items = ["a", "b", "c", "d"]
        XCTAssertEqual(PresetCollectionOrder.moved(items, fromOffsets: [2], toOffset: 0), ["c", "a", "b", "d"])
        XCTAssertEqual(PresetCollectionOrder.moved(items, fromOffsets: [0], toOffset: 4), ["b", "c", "d", "a"])
        XCTAssertEqual(PresetCollectionOrder.moved(items, fromOffsets: [0], toOffset: 2), ["b", "a", "c", "d"])
        XCTAssertEqual(PresetCollectionOrder.moved(items, fromOffsets: [3], toOffset: 1), ["a", "d", "b", "c"])
        // Dropping an item on itself or just after itself changes nothing.
        XCTAssertEqual(PresetCollectionOrder.moved(items, fromOffsets: [1], toOffset: 1), items)
        XCTAssertEqual(PresetCollectionOrder.moved(items, fromOffsets: [1], toOffset: 2), items)
        // Several items keep their relative order.
        XCTAssertEqual(PresetCollectionOrder.moved(items, fromOffsets: [0, 2], toOffset: 4), ["b", "d", "a", "c"])
        XCTAssertEqual(PresetCollectionOrder.moved(items, fromOffsets: [1, 3], toOffset: 0), ["b", "d", "a", "c"])
    }

    func testMovedIgnoresOffsetsOutsideTheList() {
        let items = ["a", "b"]
        XCTAssertEqual(PresetCollectionOrder.moved(items, fromOffsets: [5], toOffset: 0), items)
        XCTAssertEqual(PresetCollectionOrder.moved(items, fromOffsets: [0], toOffset: 99), ["b", "a"])
        XCTAssertEqual(PresetCollectionOrder.moved(items, fromOffsets: [1], toOffset: -3), ["b", "a"])
        XCTAssertEqual(PresetCollectionOrder.moved([String](), fromOffsets: [0], toOffset: 0), [])
    }

    // MARK: - Reordering with hidden entries (R14)

    func testHiddenEntriesKeepTheirSlots() throws {
        let stored = ["a", "gone1", "b", "c", "gone2"]
        XCTAssertEqual(try PresetCollectionOrder.applying(visibleOrder: ["c", "a", "b"], to: stored),
                       ["c", "gone1", "a", "b", "gone2"])
        XCTAssertEqual(try PresetCollectionOrder.applying(visibleOrder: ["a", "b", "c"], to: stored), stored)
    }

    func testAFullPermutationIsTakenAsIs() throws {
        XCTAssertEqual(try PresetCollectionOrder.applying(visibleOrder: ["c", "b", "a"], to: ["a", "b", "c"]), ["c", "b", "a"])
        XCTAssertEqual(try PresetCollectionOrder.applying(visibleOrder: [], to: ["a"]), ["a"])
    }

    func testAnOrderThatIsNotAPermutationOfStoredEntriesIsRefused() {
        for order in [["a", "x"], ["a", "a"], ["a", "b", "c", "d"]] {
            XCTAssertThrowsError(try PresetCollectionOrder.applying(visibleOrder: order, to: ["a", "b", "c"]), "\(order)") {
                XCTAssertEqual($0 as? PresetCollectionError, .invalidOrder)
            }
        }
    }

    func testEveryPermutationOfTheVisibleEntriesIsReproduced() throws {
        // Exhaustive on a small list: the visible entries read back in exactly the order set (R6).
        let stored = ["h1", "a", "b", "h2", "c", "d"]
        let hidden: Set<String> = ["h1", "h2"]
        func permutations(_ list: [String]) -> [[String]] {
            guard list.count > 1 else { return [list] }
            return list.indices.flatMap { index -> [[String]] in
                var rest = list
                let head = rest.remove(at: index)
                return permutations(rest).map { [head] + $0 }
            }
        }
        for order in permutations(["a", "b", "c", "d"]) {
            let result = try PresetCollectionOrder.applying(visibleOrder: order, to: stored)
            XCTAssertEqual(result.filter { !hidden.contains($0) }, order)
            XCTAssertEqual(result.firstIndex(of: "h1"), 0)
            XCTAssertEqual(result.firstIndex(of: "h2"), 3)
            XCTAssertEqual(Set(result), Set(stored))
        }
    }
}
