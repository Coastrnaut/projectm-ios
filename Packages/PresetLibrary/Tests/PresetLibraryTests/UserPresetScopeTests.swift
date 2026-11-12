// PRE-012-T08: user presets as part of the library and as a scope (PRE-012-R22, R23, S6).
import XCTest
@testable import PresetLibrary

final class UserPresetScopeTests: XCTestCase {
    private func user(_ n: Int, _ name: String, author: String = "Me") -> IndexedPreset {
        IndexedPreset(id: "user/00000000-0000-0000-0000-\(String(format: "%012d", n))", name: name, author: author,
                      source: PresetLibrary.userSource, folder: [], path: "\(n).milk", hash: String(repeating: "b", count: 40))
    }

    func testTheScopeIsStoredAsUser() {
        XCTAssertEqual(PresetScope.user.storageValue, "user")
        XCTAssertEqual(PresetScope(storageValue: "user"), .user)
    }

    func testUserPresetsJoinLookupSearchAndTheirOwnScopeOnly() throws {
        let base = try Fixtures.library()
        let library = base.withUserPresets([user(2, "Zeta"), user(1, "alpha mine"), user(3, "Beta")])
        XCTAssertEqual(library.members(of: .user, unlocked: false, favorites: [], excluded: []).map(\.name), ["alpha mine", "Beta", "Zeta"])
        XCTAssertEqual(library.preset(id: user(1, "").id)?.name, "alpha mine")
        XCTAssertEqual(library.title(of: .user), "My Presets")
        XCTAssertTrue(library.resolves(.user))

        // Everything built in is what it was.
        for scope in [PresetScope.included, .all, .pack("cream-of-the-crop"), .folder("cream-of-the-crop", ["Fractal"])] {
            for unlocked in [false, true] {
                XCTAssertEqual(library.members(of: scope, unlocked: unlocked, favorites: [], excluded: []),
                               base.members(of: scope, unlocked: unlocked, favorites: [], excluded: []), "\(scope)")
            }
        }
        XCTAssertEqual(library.home, base.home)
        XCTAssertEqual(library.packs, base.packs)
        XCTAssertEqual(library.archiveOrder, base.archiveOrder)

        // Never locked, purchase or not (R23).
        XCTAssertFalse(library.isLocked(user(1, "alpha mine"), unlocked: false))
        XCTAssertTrue(library.isLocked(try XCTUnwrap(library.preset(id: "en-d/Episode 1/En D - Groove.milk")), unlocked: false))

        // Search finds them, in their own group after the packs.
        let found = library.search("alpha", limit: 10)
        XCTAssertEqual(found.groups.map(\.source), ["included", PresetLibrary.userSource])
        XCTAssertEqual(found.groups.last?.presets.map(\.name), ["alpha mine"])
        XCTAssertEqual(base.search("alpha mine", limit: 10).groups.count, 0)
    }

    func testFavoritesAndCollectionsResolveUserPresets() throws {
        let library = try Fixtures.library().withUserPresets([user(1, "Mine")])
        let id = user(1, "").id
        XCTAssertEqual(library.favoritesListing([id, "frontend-uwp/a.milk"]).map(\.name), ["Alpha", "Mine"])
        XCTAssertEqual(library.members(of: .favorites, unlocked: false, favorites: [id], excluded: []).map(\.name), ["Mine"])
        XCTAssertEqual(library.collectionListing(["frontend-uwp/b.milk", id]).map(\.name), ["Beta", "Mine"])
        XCTAssertEqual(library.members(of: .collection("c"), unlocked: false, favorites: [], excluded: [id],
                                       collections: ["c": [id, "frontend-uwp/b.milk"]]).map(\.name), ["Beta"])
    }

    func testReplacingTheUserListDropsTheOldOnes() throws {
        let first = try Fixtures.library().withUserPresets([user(1, "One"), user(2, "Two")])
        let second = first.withUserPresets([user(2, "Two")])
        XCTAssertNil(second.preset(id: user(1, "").id))
        XCTAssertEqual(second.members(of: .user, unlocked: true, favorites: [], excluded: []).map(\.name), ["Two"])
        XCTAssertEqual(second.presets.count, first.presets.count - 1)
        XCTAssertEqual(first.withUserPresets([]).presets, try Fixtures.library().presets)
    }

    func testEntriesThatAreNotUserPresetsAreIgnored() throws {
        let impostor = IndexedPreset(id: "frontend-uwp/a.milk", name: "Impostor", author: "X", source: "included", folder: [],
                                     path: "x", hash: "")
        let library = try Fixtures.library().withUserPresets([impostor])
        XCTAssertEqual(library.preset(id: "frontend-uwp/a.milk")?.name, "Alpha")
        XCTAssertEqual(library.members(of: .user, unlocked: true, favorites: [], excluded: []), [])
    }
}
