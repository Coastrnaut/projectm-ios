// SceneSwitcherTests.swift — UIX-002-T05, T14 (UIX-002-R2 to R9, S4, S6; data-model). The filter is
// pure; the model and the probe take a fake clock, so no test waits or reads the wall clock. The one
// timing check (S6) uses the monotonic `ContinuousClock` with a generous ceiling.
import ShowControl
import XCTest
@testable import projectM_iOS

final class SceneSwitcherTests: XCTestCase {
    /// A clock the test advances by hand.
    @MainActor private final class FakeClock {
        var now: Double
        init(now: Double) { self.now = now }
    }

    private static func sceneID(_ n: Int) -> String { String(format: "5CE7E000-0000-4000-8000-%012d", n) }
    private static func cueID(_ n: Int) -> UUID { UUID(uuidString: String(format: "C0E00000-0000-4000-8000-%012d", n))! }

    /// A show of `labels` (scene names default to the labels), standing on cue `active`.
    private static func list(_ labels: [String], active: Int? = 1) -> ShowCueList {
        var list = ShowCueList(id: UUID(), name: "Test")
        for (index, label) in labels.enumerated() {
            _ = try? list.append(sceneID: sceneID(index + 1), label: label, cueID: cueID(index + 1))
        }
        if let active { list.go(to: cueID(active)) }
        return list
    }

    private static func entries(_ labels: [String], names: [Int: String] = [:], missing: Set<Int> = [],
                                active: Int? = 1) -> [SceneSwitcherEntry] {
        var sceneNames: [String: String] = [:]
        for (index, label) in labels.enumerated() { sceneNames[sceneID(index + 1)] = names[index + 1] ?? label }
        let unreadable: Set<String> = Set(missing.map(sceneID))
        return SceneSwitcherEntry.entries(list: list(labels, active: active), sceneNames: sceneNames, unreadable: unreadable)
    }

    private static let show = ["Opening", "Build", "Drop", "Break", "Finale"]

    private func labels(_ results: [SceneSwitcherEntry]) -> [String] { results.map(\.label) }

    // MARK: - Entries (UIX-002-R2)

    func testEntriesFollowShowOrderAndCarryNameActiveAndMissing() {
        let rows = Self.entries(["Intro", "Intro copy", "Gone"], names: [2: "Sunrise"], missing: [3], active: 2)
        XCTAssertEqual(rows.map(\.number), [1, 2, 3])
        XCTAssertNil(rows[0].sceneName, "a name equal to the label is not repeated")
        XCTAssertEqual(rows[1].sceneName, "Sunrise")
        XCTAssertEqual(rows.map(\.isActive), [false, true, false])
        XCTAssertTrue(rows[2].isMissing)
        XCTAssertNil(rows[2].sceneName, "an unreadable scene has no name")
        XCTAssertEqual(rows[1].accessibilityValue, "Cue 2, scene Sunrise, current")
        XCTAssertEqual(rows[2].accessibilityValue, "Cue 3, scene missing")
    }

    // MARK: - Folder path (SCN-004-R11)

    func testEntriesCarryTheFolderPathAndSearchMatchesItAfterNameMatches() throws {
        var show = Self.list(["Opening", "Build", "Set piece"])
        let set = try show.createFolder(named: "Set A", in: nil)
        let encore = try show.createFolder(named: "Encore", in: set.id)
        try show.moveScene(Self.sceneID(2), to: encore.id)
        var names: [String: String] = [:]
        for n in 1...3 { names[Self.sceneID(n)] = ["Opening", "Build", "Set piece"][n - 1] }
        let rows = SceneSwitcherEntry.entries(list: show, sceneNames: names, unreadable: [])
        XCTAssertEqual(rows.map(\.folderPath), [nil, "Set A / Encore", nil], "flat, in show order")
        XCTAssertEqual(rows[1].accessibilityValue, "Cue 2, folder Set A / Encore")
        XCTAssertEqual(labels(SceneSwitcherFilter.results(rows, query: "set")), ["Set piece", "Build"],
                       "a label prefix match first, then the folder match")
        XCTAssertEqual(labels(SceneSwitcherFilter.results(rows, query: "encore")), ["Build"])
    }

    // MARK: - Filter (UIX-002-R3, S4)

    func testCaseInsensitiveContains() {
        let rows = Self.entries(Self.show)
        XCTAssertEqual(labels(SceneSwitcherFilter.results(rows, query: "DRO")), ["Drop"])
        XCTAssertEqual(labels(SceneSwitcherFilter.results(rows, query: "dro")), ["Drop"])
        XCTAssertEqual(labels(SceneSwitcherFilter.results(rows, query: "ea")), ["Break"])
        XCTAssertEqual(labels(SceneSwitcherFilter.results(rows, query: "zzz")), [])
    }

    func testDiacriticAndWidthInsensitive() {
        let rows = Self.entries(["Café Noir", "Ünder", "ＤＲＯＰ"])
        XCTAssertEqual(labels(SceneSwitcherFilter.results(rows, query: "cafe")), ["Café Noir"])
        XCTAssertEqual(labels(SceneSwitcherFilter.results(rows, query: "under")), ["Ünder"])
        XCTAssertEqual(labels(SceneSwitcherFilter.results(rows, query: "CAFÉ")), ["Café Noir"])
        XCTAssertEqual(labels(SceneSwitcherFilter.results(rows, query: "drop")), ["ＤＲＯＰ"], "full-width letters match")
    }

    func testEmptyAndBlankQueriesListEverythingInShowOrder() {
        let rows = Self.entries(Self.show)
        XCTAssertEqual(SceneSwitcherFilter.results(rows, query: ""), rows)
        XCTAssertEqual(SceneSwitcherFilter.results(rows, query: "   \n"), rows)
        XCTAssertEqual(labels(SceneSwitcherFilter.results(rows, query: "  drop ")), ["Drop"], "the query is trimmed")
    }

    func testTheSceneNameMatchesToo() {
        let rows = Self.entries(["Cue A", "Cue B"], names: [2: "Laser Storm"])
        XCTAssertEqual(labels(SceneSwitcherFilter.results(rows, query: "storm")), ["Cue B"])
    }

    func testPrefixAndWordStartMatchesComeFirstThenShowOrder() {
        let rows = Self.entries(["Airdrop", "Backdrop", "Drop", "Big drop", "Raindrops-drip"])
        // "dr": prefix or word start in Drop, Big drop and Raindrops-drip ("drip" after the hyphen);
        // contains only in Airdrop and Backdrop. Show order within each group.
        XCTAssertEqual(labels(SceneSwitcherFilter.results(rows, query: "dr")),
                       ["Drop", "Big drop", "Raindrops-drip", "Airdrop", "Backdrop"])
        XCTAssertTrue(SceneSwitcherFilter.startsWord("big drop", "dr"))
        XCTAssertFalse(SceneSwitcherFilter.startsWord("airdrop", "dr"))
    }

    func testFilteringTheLargestShowIsWellUnderAFrame() {
        let labels: [String] = (1...ShowCueList.maximumCues).map { (n: Int) -> String in "Scène numéro \(n) – Drop \(n % 7)" }
        let rows = Self.entries(labels)
        XCTAssertEqual(rows.count, 256)
        let clock = ContinuousClock()
        var worst: Duration = .zero
        for query in ["d", "dr", "dro", "drop 3", "scene", "numero 25", "x"] {
            let start = clock.now
            _ = SceneSwitcherFilter.results(rows, query: query)
            worst = max(worst, clock.now - start)
        }
        XCTAssertLessThan(worst, .milliseconds(5), "UIX-002-S6 (simulator, generous ceiling): worst \(worst)")
    }

    // MARK: - Model: highlight and reopen (UIX-002-R5, R6)

    @MainActor
    func testHighlightRules() {
        let rows = Self.entries(Self.show, active: 4)
        let model = SceneSwitcherModel(now: { () -> Double in 0 })
        model.open(entries: rows)
        XCTAssertTrue(model.isOpen)
        XCTAssertEqual(model.highlightedCueID, Self.cueID(4), "opens on the active cue")
        model.query = "b"            // Build, Break: Break (active) still matches
        model.queryChanged(entries: rows)
        XCTAssertEqual(model.highlightedCueID, Self.cueID(4), "kept while it matches")
        model.query = "bu"           // Build only
        model.queryChanged(entries: rows)
        XCTAssertEqual(model.highlightedCueID, Self.cueID(2), "the first result when it no longer matches")
        model.query = "zz"
        model.queryChanged(entries: rows)
        XCTAssertNil(model.highlightedCueID, "none when nothing matches")
        XCTAssertNil(model.highlighted(in: rows))
        model.query = ""
        model.queryChanged(entries: rows)
        XCTAssertEqual(model.highlightedCueID, Self.cueID(1))
        model.moveHighlight(by: -1, entries: rows)
        XCTAssertEqual(model.highlightedCueID, Self.cueID(1), "no wrap at the top")
        model.moveHighlight(by: 1, entries: rows)
        model.moveHighlight(by: 1, entries: rows)
        XCTAssertEqual(model.highlightedCueID, Self.cueID(3))
        for _ in 0..<10 { model.moveHighlight(by: 1, entries: rows) }
        XCTAssertEqual(model.highlightedCueID, Self.cueID(5), "no wrap at the bottom")
        XCTAssertEqual(model.highlighted(in: rows)?.label, "Finale")
    }

    @MainActor
    func testReopenRestoresAnAbandonedQueryAndClearsAfterAChoice() {
        let rows = Self.entries(Self.show)
        let model = SceneSwitcherModel(now: { () -> Double in 0 })
        model.open(entries: rows)
        model.query = "br"
        model.queryChanged(entries: rows)
        model.moveHighlight(by: 1, entries: rows)    // Build → Break
        XCTAssertEqual(model.highlightedCueID, Self.cueID(4))
        model.close(chose: false)
        XCTAssertFalse(model.isOpen)
        XCTAssertEqual(model.focusReturnRevision, 1, "focus returns to the Scenes button")
        model.open(entries: rows)
        XCTAssertEqual(model.query, "br", "the abandoned query is restored")
        XCTAssertEqual(model.highlightedCueID, Self.cueID(4), "with its highlight")
        model.close(chose: true)
        XCTAssertEqual(model.focusReturnRevision, 1, "a choice does not move focus to the button")
        model.open(entries: rows)
        XCTAssertEqual(model.query, "", "after a choice the switcher reopens empty")
        XCTAssertEqual(model.highlightedCueID, Self.cueID(1), "on the active cue")
    }

    // MARK: - Probe (UIX-002-R8)

    func testProbeMeasuresOnTheGivenClock() throws {
        var probe = SceneSwitchLatencyProbe()
        XCTAssertNil(probe.finish(.applied, now: 5), "nothing pending")
        probe.begin(sceneID: "S1", cueID: Self.cueID(1), now: 10)
        XCTAssertTrue(probe.isPending)
        let applied = try XCTUnwrap(probe.finish(.applied, now: 10.12))
        XCTAssertFalse(probe.isPending)
        XCTAssertEqual(applied.milliseconds, 120.0, accuracy: 0.001)
        XCTAssertTrue(applied.withinBudget)
        XCTAssertEqual(applied.probeText, "applied|S1|120.0|ok")
        XCTAssertNil(probe.finish(.failed, now: 11), "one measurement per choice")

        probe.begin(sceneID: "S2", cueID: Self.cueID(2), now: 20)
        probe.begin(sceneID: "S3", cueID: Self.cueID(3), now: 21)   // replaces the pending one
        let over = try XCTUnwrap(probe.finish(.repairShown, now: 21.2501))
        XCTAssertEqual(over.sceneID, "S3")
        XCTAssertFalse(over.withinBudget)
        XCTAssertEqual(over.probeText, "repairShown|S3|250.1|over")
        XCTAssertEqual(probe.last, over)

        probe.begin(sceneID: "S4", cueID: Self.cueID(4), now: 30)
        let edge = try XCTUnwrap(probe.finish(.failed, now: 30.25))
        XCTAssertTrue(edge.withinBudget, "the budget is inclusive")
        XCTAssertEqual(SceneSwitchLatencyProbe.budget, 0.250)
    }

    @MainActor
    func testModelProbeUsesItsClock() {
        let clock = FakeClock(now: 100)
        let model = SceneSwitcherModel(now: { () -> Double in clock.now })
        model.probe.begin(sceneID: "S1", cueID: Self.cueID(1), now: model.now())
        clock.now = 100.042
        model.probe.finish(.applied, now: model.now())
        XCTAssertEqual(model.probeText, "applied|S1|42.0|ok")
    }

    // MARK: - Texts (UIX-002-R9)

    func testAnnouncementTexts() {
        XCTAssertEqual(AccessibilityAnnouncer.sceneSwitcherCountText(0), "No matching scenes")
        XCTAssertEqual(AccessibilityAnnouncer.sceneSwitcherCountText(1), "1 scene")
        XCTAssertEqual(AccessibilityAnnouncer.sceneSwitcherCountText(5), "5 scenes")
        XCTAssertEqual(AccessibilityAnnouncer.sceneChosenText("Drop"), "Scene: Drop")
        XCTAssertTrue(AnnouncementKind.allCases.contains(.search))
    }

    @MainActor
    func testCountAnnouncementsShareTheRateLimitedSearchLane() {
        var posted: [String] = []
        let clock = FakeClock(now: 0)
        var scheduled: [@MainActor () -> Void] = []
        let announcer = AccessibilityAnnouncer(post: { (text: String) in posted.append(text) },
                                               now: { () -> Double in clock.now },
                                               schedule: { (_: Double, action: @escaping @MainActor () -> Void) in scheduled.append(action) })
        // Typing "b", "r", "e" within one second: the first count at once, the latest when the window closes.
        for (t, count) in [(0.0, 2), (0.2, 2), (0.4, 1)] {
            clock.now = t
            announcer.announce(AccessibilityAnnouncer.sceneSwitcherCountText(count), kind: .search)
        }
        announcer.announce(AccessibilityAnnouncer.sceneChosenText("Break"), kind: .cue)
        XCTAssertEqual(posted, ["2 scenes", "Scene: Break"], "a count burst never swallows the cue lane")
        clock.now = 1.0
        scheduled.first?()
        XCTAssertEqual(posted, ["2 scenes", "Scene: Break", "1 scene"])
    }
}
