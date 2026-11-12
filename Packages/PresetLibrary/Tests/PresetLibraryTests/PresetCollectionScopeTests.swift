// PRE-007-T08: a collection as a navigation scope (PRE-007-R11-R14; S3, S4): manual order,
// playable members only, locked presets never reachable, missing ids skipped.
import Foundation
import XCTest
@testable import PresetLibrary

final class PresetCollectionScopeTests: XCTestCase {
    private let spiral1 = "cream-of-the-crop/Fractal/Nested Spiral/Geiss - Spiral 1.milk"
    private let wave = "cream-of-the-crop/Reaction/Liquid/Zylot - Wave.milk"
    private let alpha = "frontend-uwp/a.milk"
    private let beta = "frontend-uwp/b.milk"
    private let missing = "removed-pack/Gone - Missing.milk"

    /// "mix": Wave (locked pack), Beta, a missing id, Alpha, Spiral 1 (locked pack): not alphabetical.
    private var collections: [String: [String]] { ["mix": [wave, beta, missing, alpha, spiral1], "empty": []] }

    private func members(_ id: String, unlocked: Bool, excluded: Set<String> = []) throws -> [String] {
        try Fixtures.library().members(of: .collection(id), unlocked: unlocked, favorites: [], excluded: excluded,
                                       collections: collections).map(\.name)
    }

    func testStorageRoundTrip() {
        let scope = PresetScope.collection("6F1C2B9E-0001-4000-8000-000000000001")
        XCTAssertEqual(scope.storageValue, "collection:6F1C2B9E-0001-4000-8000-000000000001")
        XCTAssertEqual(PresetScope(storageValue: scope.storageValue), scope)
        XCTAssertNil(PresetScope(storageValue: "collection:"))
    }

    func testMembersFollowTheStoredOrderAndSkipMissingIDs() throws {
        XCTAssertEqual(try members("mix", unlocked: true), ["Wave", "Beta", "Alpha", "Spiral 1"])
    }

    func testLockedPresetsAreNotMembersWhileLocked() throws {
        XCTAssertEqual(try members("mix", unlocked: false), ["Beta", "Alpha"])
    }

    func testSessionExcludedPresetsAreNotMembers() throws {
        XCTAssertEqual(try members("mix", unlocked: true, excluded: [beta]), ["Wave", "Alpha", "Spiral 1"])
    }

    func testUnknownAndEmptyCollectionsHaveNoMembers() throws {
        XCTAssertEqual(try members("empty", unlocked: true), [])
        XCTAssertEqual(try members("nope", unlocked: true), [])
        // Without the collections argument (existing callers) a collection scope is simply empty.
        XCTAssertEqual(try Fixtures.library().members(of: .collection("mix"), unlocked: true, favorites: [], excluded: []), [])
    }

    func testTheListingKeepsLockedPresetsAndOrder() throws {
        let library = try Fixtures.library()
        let listing = library.collectionListing(collections["mix"]!)
        XCTAssertEqual(listing.map(\.name), ["Wave", "Beta", "Alpha", "Spiral 1"])
        XCTAssertEqual(listing.map { library.isLocked($0, unlocked: false) }, [true, false, false, true])
        XCTAssertEqual(library.collectionListing([]), [])
    }

    func testTitlesAndResolution() throws {
        let library = try Fixtures.library()
        XCTAssertEqual(library.title(of: .collection("mix"), collectionNames: ["mix": "Friday set"]), "Friday set")
        XCTAssertEqual(library.title(of: .collection("mix")), "Collection")
        XCTAssertEqual(library.title(of: .favorites, collectionNames: ["mix": "Friday set"]), "Favorites")
        XCTAssertTrue(library.resolves(.collection("mix")), "only the collections store knows; the library does not veto")
    }

    func testAFullNextCycleVisitsEachMemberOnceInTheManualOrder() throws {
        let library = try Fixtures.library()
        let scopeMembers = library.members(of: .collection("mix"), unlocked: true, favorites: [], excluded: [], collections: collections)
        var current = scopeMembers.first
        var visited: [String] = []
        for _ in scopeMembers.indices {
            visited.append(current!.name)
            current = ScopeStepper.step(scopeMembers, from: current, by: 1)
        }
        XCTAssertEqual(visited, ["Wave", "Beta", "Alpha", "Spiral 1"])
        XCTAssertEqual(current, scopeMembers.first, "wraps")
        XCTAssertEqual(ScopeStepper.step(scopeMembers, from: scopeMembers.first, by: -1)?.name, "Spiral 1", "Previous wraps to the last")
        XCTAssertEqual(ScopeStepper.step(scopeMembers, from: scopeMembers[2], by: -1)?.name, "Beta")
    }

    func testRandomNeverReachesALockedPreset() throws {
        let library = try Fixtures.library()
        let scopeMembers = library.members(of: .collection("mix"), unlocked: false, favorites: [], excluded: [], collections: collections)
        var generator = SeededGenerator(seed: 7)
        var current = scopeMembers[0]
        for _ in 0..<1_000 {
            let pick = try XCTUnwrap(ScopeStepper.random(scopeMembers, excluding: current, using: &generator))
            XCTAssertFalse(library.isLocked(pick, unlocked: false))
            XCTAssertNotEqual(pick, current)
            XCTAssertTrue(collections["mix"]!.contains(pick.id))
            current = pick
        }
    }

    func testACollectionOfOnlyLockedOrMissingPresetsHasNoMembers() throws {
        let only = ["locked": [wave, spiral1, missing]]
        let library = try Fixtures.library()
        XCTAssertEqual(library.members(of: .collection("locked"), unlocked: false, favorites: [], excluded: [], collections: only), [])
        XCTAssertNil(ScopeStepper.step([], from: nil, by: 1))
    }

    func testTheGoldenFixtureResolvesAgainstTheLibrary() throws {
        let file = try PresetCollectionsFile.decode(Golden.data("collections-v1")).file
        let library = try Fixtures.library()
        let zebra = file.collections[0]
        XCTAssertEqual(library.collectionListing(zebra.presetIDs).map(\.name), ["Spiral 1", "Beta", "Alpha"])
        let byID = Dictionary(uniqueKeysWithValues: file.collections.map { ($0.id, $0.presetIDs) })
        XCTAssertEqual(library.members(of: .collection(zebra.id), unlocked: false, favorites: [], excluded: [], collections: byID).map(\.name),
                       ["Beta", "Alpha"])
    }

    func testExistingScopesAreUnchangedByTheNewParameter() throws {
        let library = try Fixtures.library()
        for scope in [PresetScope.included, .pack("cream-of-the-crop"), .folder("cream-of-the-crop", ["Fractal"]), .all, .search("geiss")] {
            XCTAssertEqual(library.members(of: scope, unlocked: true, favorites: [], excluded: []),
                           library.members(of: scope, unlocked: true, favorites: [], excluded: [], collections: collections), "\(scope)")
        }
        XCTAssertEqual(library.members(of: .favorites, unlocked: true, favorites: [alpha, wave], excluded: [], collections: collections).map(\.name),
                       ["Alpha", "Wave"], "Favorites stay alphabetical")
    }
}
