// T207: decoding, home order and counts, folder trees per pack, lock state, members and order.
import Foundation
import XCTest
@testable import PresetLibrary

final class PresetLibraryTests: XCTestCase {
    func testHomeOrderAndCounts() throws {
        let library = try Fixtures.library()
        XCTAssertEqual(library.home.map(\.title), ["Included", "Cream of the Crop", "projectM Classic", "Milkdrop Original", "En D", "All presets A-Z"])
        XCTAssertEqual(library.home.map(\.presetCount), [2, 4, 1, 1, 1, 9])
        XCTAssertEqual(library.home.map(\.locked), [false, true, true, true, true, false])
    }

    func testFolderTreesFollowEachPack() throws {
        let library = try Fixtures.library()
        let cream = try XCTUnwrap(library.home.first { $0.id == "cream-of-the-crop" })
        XCTAssertEqual(cream.children.map(\.title), ["Fractal", "Reaction"])
        let fractal = cream.children[0]
        XCTAssertEqual(fractal.children.map(\.title), ["Nested Circle", "Nested Spiral"])
        XCTAssertEqual(fractal.presetCount, 3)
        XCTAssertEqual(fractal.children[1].scope, .folder("cream-of-the-crop", ["Fractal", "Nested Spiral"]))
        let classic = try XCTUnwrap(library.home.first { $0.id == "projectm-classic" })
        XCTAssertEqual(classic.children.map(\.title), ["tryptonaut"])
        let original = try XCTUnwrap(library.home.first { $0.id == "milkdrop-original" })
        XCTAssertTrue(original.children.isEmpty, "a flat pack has no folders")
    }

    func testMembersAreAlphabeticalAndPlayableOnly() throws {
        let library = try Fixtures.library()
        XCTAssertEqual(library.members(of: .included, unlocked: false, favorites: [], excluded: []).map(\.name), ["Alpha", "Beta"])
        XCTAssertTrue(library.members(of: .pack("cream-of-the-crop"), unlocked: false, favorites: [], excluded: []).isEmpty,
                      "locked presets never play")
        let spiral = library.members(of: .folder("cream-of-the-crop", ["Fractal", "Nested Spiral"]), unlocked: true, favorites: [], excluded: [])
        XCTAssertEqual(spiral.map(\.name), ["Spiral 1", "Spiral 2"])
        let excludedOne = library.members(of: .folder("cream-of-the-crop", ["Fractal", "Nested Spiral"]), unlocked: true,
                                          favorites: [], excluded: [spiral[0].id])
        XCTAssertEqual(excludedOne.map(\.name), ["Spiral 2"])
        XCTAssertEqual(library.members(of: .all, unlocked: false, favorites: [], excluded: []).count, 2)
        XCTAssertEqual(library.members(of: .all, unlocked: true, favorites: [], excluded: []).count, 9)
    }

    func testFavoritesAcrossPacksAlphabetical() throws {
        let library = try Fixtures.library()
        let favorites: Set = ["frontend-uwp/b.milk", "en-d/Episode 1/En D - Groove.milk", "missing/id.milk"]
        XCTAssertEqual(library.members(of: .favorites, unlocked: true, favorites: favorites, excluded: []).map(\.name), ["Beta", "Groove"])
        XCTAssertEqual(library.members(of: .favorites, unlocked: false, favorites: favorites, excluded: []).map(\.name), ["Beta"])
        XCTAssertEqual(library.favoritesListing(favorites).map(\.name), ["Beta", "Groove"], "the listing shows locked favorites too")
    }

    func testLockStateAndLookup() throws {
        let library = try Fixtures.library()
        let groove = try XCTUnwrap(library.preset(id: "en-d/Episode 1/En D - Groove.milk"))
        XCTAssertTrue(library.isLocked(groove, unlocked: false))
        XCTAssertFalse(library.isLocked(groove, unlocked: true))
        XCTAssertFalse(library.isLocked(try XCTUnwrap(library.preset(id: "frontend-uwp/a.milk")), unlocked: false))
        XCTAssertNil(library.preset(id: "nope"))
    }

    func testScopeTitles() throws {
        let library = try Fixtures.library()
        XCTAssertEqual(library.title(of: .folder("cream-of-the-crop", ["Fractal", "Nested Spiral"])), "Fractal › Nested Spiral")
        XCTAssertEqual(library.title(of: .pack("cream-of-the-crop")), "Cream of the Crop")
        XCTAssertEqual(library.title(of: .included), "Included")
        XCTAssertEqual(library.title(of: .search("geiss")), "Search: geiss")
    }

    /// T213: regression guard on the host (device numbers: T238, SC-101/SC-102).
    func testLargeLibraryBuildAndSearchPerformance() throws {
        let start = Date()
        let library = try Fixtures.large()
        let build = Date().timeIntervalSince(start)
        XCTAssertEqual(library.presets.count, 13_002)
        let searchStart = Date()
        let result = library.search("12 unicode", limit: 200)
        let search = Date().timeIntervalSince(searchStart)
        XCTAssertFalse(result.groups.isEmpty)
        print("PresetLibrary 13k host: build \(Int(build * 1000)) ms, search \(Int(search * 1000)) ms")
        XCTAssertLessThan(build, 2.0)
        XCTAssertLessThan(search, 0.2)
    }
}
