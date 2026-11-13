// MOD-013-T03: the stable-ID migration table (MOD-013-R2 to R4; contract M1, M2; MOD-013-S4).
import ParameterGraph
import XCTest

final class ModulationIDMigrationTests: XCTestCase {
    private typealias Rule = ModulationIDMigrations.Rule

    /// Two versions of history: `test.a` became `test.b` (version 2), which became `test.c` (3);
    /// `test.gone` was retired (2); `audio.kick` became `audio.onset` (2); `audio.flux` retired (3).
    private let history: [Rule] = [
        .renamed("test.a", to: "test.b", since: 2),
        .retired("test.gone", since: 2),
        .renamed("audio.kick", to: "audio.onset", since: 2),
        .renamed("test.b", to: "test.c", since: 3),
        .retired("audio.flux", since: 3),
    ]

    private func registry(_ rules: [Rule], retired: Set<ParameterID> = ["test.a", "test.b", "test.gone"],
                          ids: [ParameterID] = ["test.c", "test.d"]) throws -> ParameterRegistry {
        try ParameterRegistry(descriptors: ids.map { (id: ParameterID) -> ParameterDescriptor in continuous(id, "N " + id.rawValue) },
                              retiredIDs: retired, migrations: try ModulationIDMigrations(rules))
    }

    private func problems(_ rules: [Rule]) -> [ModulationIDMigrationIssue.Problem] {
        do {
            _ = try ModulationIDMigrations(rules)
            return []
        } catch {
            return error.issues.map(\.problem)
        }
    }

    func testRenamesChainAndResolutionIsIdempotent() throws {
        let table = try ModulationIDMigrations(history)
        XCTAssertEqual(ModulationIDMigrations.formatVersion, 1)
        XCTAssertEqual(table.version, 3)
        XCTAssertEqual(ModulationIDMigrations.none.version, 0)
        XCTAssertEqual(table.resolve("test.a"), .renamed(to: "test.c", chain: ["test.a", "test.b", "test.c"]))
        XCTAssertEqual(table.resolve("test.b"), .renamed(to: "test.c", chain: ["test.b", "test.c"]))
        XCTAssertEqual(table.resolve("test.c"), .unchanged)
        XCTAssertEqual(table.resolve("test.gone"), .retired(chain: ["test.gone"]))
        XCTAssertEqual(table.resolve("audio.kick"), .renamed(to: "audio.onset", chain: ["audio.kick", "audio.onset"]))
        XCTAssertEqual(table.resolve("audio.flux"), .retired(chain: ["audio.flux"]))
        // Idempotent: resolving a resolved ID changes nothing, for every rule's start.
        for rule in history {
            if case let .renamed(end, _) = table.resolve(rule.from) { XCTAssertEqual(table.resolve(end), .unchanged) }
        }
        // Composing over versions: the version-2 table plus the version-3 rules resolves like the whole.
        let v2 = try ModulationIDMigrations(history.filter { (r: Rule) -> Bool in r.since <= 2 })
        XCTAssertEqual(v2.resolve("test.a"), .renamed(to: "test.b", chain: ["test.a", "test.b"]))
        XCTAssertEqual(try ModulationIDMigrations(v2.rules + history.filter { (r: Rule) -> Bool in r.since == 3 }), table)
    }

    func testRenamedThenRetiredResolvesRetired() throws {
        let table = try ModulationIDMigrations([.renamed("test.x", to: "test.y", since: 1), .retired("test.y", since: 2)])
        XCTAssertEqual(table.resolve("test.x"), .retired(chain: ["test.x", "test.y"]))
    }

    func testStructuralProblemsAreRefusedWithReadableReasons() {
        XCTAssertEqual(problems([.renamed("test.a", to: "test.b", since: 1), .renamed("test.b", to: "test.a", since: 2)]), [.cycle])
        do {
            _ = try ModulationIDMigrations([.renamed("test.a", to: "test.b", since: 1), .renamed("test.b", to: "test.c", since: 1),
                                            .renamed("test.c", to: "test.a", since: 1)])
            XCTFail("a loop must be refused")
        } catch {
            XCTAssertEqual(error.issues.map(\.message),
                           ["Migration rule 0 (test.a → test.b (since 1)): the renames form the loop test.a → test.b → test.c → test.a"])
            XCTAssertTrue(error.description.hasPrefix("Migration table is invalid (1 issue):"))
        }
        XCTAssertEqual(problems([.renamed("test.a", to: "test.a", since: 1)]), [.selfRename])
        XCTAssertEqual(problems([.retired("test.a", since: 1), .renamed("test.a", to: "test.b", since: 1)]), [.duplicateRule])
        XCTAssertEqual(problems([.renamed("test.a", to: "audio.onset", since: 1)]), [.crossKind])
        XCTAssertEqual(problems([.retired("Bad", since: 1)]), [.malformedID])
        XCTAssertEqual(problems([.retired("audio.", since: 1), .retired("audio.a-b", since: 1)]), [.malformedID, .malformedID])
        XCTAssertEqual(problems([.retired("audio.band.200", since: 1)]), [])     // digits start audio segments
        XCTAssertEqual(problems([.retired("test.a", since: 0)]), [.invalidVersion])
        XCTAssertEqual(problems([.retired("test.a", since: 2), .retired("test.b", since: 1)]), [.versionOrder])
    }

    func testRegistryAppliesTheTableAndTheRetiredSet() throws {
        let r = try registry(history)
        XCTAssertEqual(r.migrations.version, 3)
        XCTAssertEqual(r.resolveParameter("test.a"), .renamed(to: "test.c", chain: ["test.a", "test.b", "test.c"]))
        XCTAssertEqual(r.resolveParameter("test.c"), .unchanged)
        XCTAssertEqual(r.resolveParameter("test.gone"), .retired(chain: ["test.gone"]))
        XCTAssertEqual(r.resolveParameter("test.unknown"), .unchanged)
        XCTAssertEqual(r.resolveAudioFeature("audio.kick"), .renamed(to: "audio.onset", chain: ["audio.kick", "audio.onset"]))
        XCTAssertEqual(r.resolveAudioFeature("audio.band.3"), .unchanged)
        // A parameter retired without a rule resolves retired; so does a chain that ends retired.
        let quiet = try registry([.renamed("test.a", to: "test.b", since: 1)], retired: ["test.a", "test.b", "test.old"])
        XCTAssertEqual(quiet.resolveParameter("test.old"), .retired(chain: ["test.old"]))
        XCTAssertEqual(quiet.resolveParameter("test.a"), .retired(chain: ["test.a", "test.b"]))
        // The default registry has the empty table.
        XCTAssertEqual(try ParameterRegistry(descriptors: []).migrations, .none)
    }

    func testRegistryRefusesTablesThatContradictTheCatalog() throws {
        func registryProblems(_ rules: [Rule], retired: Set<ParameterID>) throws -> [ParameterValidationIssue.Problem] {
            do {
                _ = try registry(rules, retired: retired)
                return []
            } catch let error as ParameterRegistryError {
                return error.issues.map(\.problem)
            }
        }
        // Renaming a registered ID would reuse it (MOD-001); it must also be retired.
        XCTAssertEqual(try registryProblems([.renamed("test.d", to: "test.c", since: 1)], retired: []),
                       [.migrationFromRegistered, .migrationFromNotRetired])
        XCTAssertEqual(try registryProblems([.renamed("test.a", to: "test.c", since: 1)], retired: []), [.migrationFromNotRetired])
        XCTAssertEqual(try registryProblems([.renamed("test.a", to: "test.nowhere", since: 1)], retired: ["test.a"]),
                       [.migrationTargetUnknown])
        XCTAssertEqual(try registryProblems([.retired("audio.onset", since: 1)], retired: []), [.migrationFromRegistered])
        XCTAssertEqual(try registryProblems([.renamed("audio.kick", to: "audio.snare", since: 1)], retired: []),
                       [.migrationTargetUnknown])
        XCTAssertEqual(try registryProblems(history, retired: ["test.a", "test.b", "test.gone"]), [])
    }
}
