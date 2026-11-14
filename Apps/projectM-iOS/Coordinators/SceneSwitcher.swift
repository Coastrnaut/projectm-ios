// SceneSwitcher.swift — UIX-002 quick scene switcher: the entries, the search filter, the latency
// probe and the overlay's state (spec UIX-002-R2 to R8; data-model; research UIX-002-D2, D3, D5).
//
// * The show's cues are the only named local scenes (spec baseline), so an entry is a cue: its
//   number, label, the scene's name when it differs, and whether it is active or its scene missing.
//   SCN-004: the list stays flat in show order; each entry carries its scene's folder path, shown,
//   read by VoiceOver and matched by search (after prefix and word-start matches).
//   SCN-005: each entry also carries its scene's tags (shown, read, matched like the folder path);
//   selected tag chips (in memory, AND, folded) narrow the entries before the query ranks them.
// * `SceneSwitcherFilter`: the trimmed query folded with case, diacritic and width insensitivity
//   (fixed `nil` locale, the same on every device language); an entry matches when its label or
//   scene name contains it. Prefix and word-start matches come first; show order within each group.
// * `SceneSwitchLatencyProbe`: the time from a choice to the applied state (or the repair report's
//   request) on an injected monotonic clock (`ProcessInfo.systemUptime` in the app). Budget 250 ms
//   on the simulator; never device evidence.
// * `SceneSwitcherModel`: open/closed, the query, the highlight and the abandoned query. In memory
//   only (UIX-002-R12): nothing is stored.
import Foundation
import Observation
import ShowControl

/// One row of the switcher: a cue of the show (UIX-002-R2).
struct SceneSwitcherEntry: Equatable, Sendable, Identifiable {
    let cueID: UUID
    /// 1-based position in the show.
    let number: Int
    let label: String
    /// The stored scene's name; nil when unreadable or equal to the label.
    let sceneName: String?
    let isActive: Bool
    let isMissing: Bool
    /// SCN-004: the scene's folder path ("Set A / Encore"); nil at the top level.
    var folderPath: String? = nil
    /// SCN-005: the scene's tags (sorted).
    var tags: [String] = []
    /// SCN-006: the cue's scene (its preview picture).
    var sceneID: String = ""

    var id: UUID { cueID }

    /// The rows for a show, in show order.
    static func entries(list: ShowCueList, sceneNames: [String: String], unreadable: Set<String>) -> [SceneSwitcherEntry] {
        let activeID: UUID? = list.activeCue?.id
        var rows: [SceneSwitcherEntry] = []
        rows.reserveCapacity(list.cues.count)
        for (index, cue) in list.cues.enumerated() {
            let missing: Bool = unreadable.contains(cue.sceneID)
            var name: String? = missing ? nil : sceneNames[cue.sceneID]
            if name == cue.label { name = nil }
            let path: String? = list.folders.pathText(of: list.folderID(ofScene: cue.sceneID))
            rows.append(SceneSwitcherEntry(cueID: cue.id, number: index + 1, label: cue.label, sceneName: name,
                                           isActive: cue.id == activeID, isMissing: missing, folderPath: path,
                                           tags: list.tags(ofScene: cue.sceneID), sceneID: cue.sceneID))
        }
        return rows
    }

    /// VoiceOver value: "Cue 3", then ", scene <name>", ", current", ", scene missing" as they apply.
    var accessibilityValue: String {
        var parts: [String] = ["Cue \(number)"]
        if let sceneName { parts.append("scene \(sceneName)") }
        if isActive { parts.append("current") }
        if isMissing { parts.append("scene missing") }
        if let folderPath { parts.append("folder \(folderPath)") }
        if !tags.isEmpty { parts.append("tags " + tags.joined(separator: ", ")) }   // SCN-005
        return parts.joined(separator: ", ")
    }
}

/// Search over the entries (UIX-002-R3; research UIX-002-D2).
enum SceneSwitcherFilter {
    /// The comparison form of a text: case, accents and width folded, fixed locale.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// The query as matched: trimmed, then folded; "" for an empty or blank query.
    static func normalizedQuery(_ query: String) -> String {
        fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The matching entries, best first; every entry in show order for an empty query.
    static func results(_ entries: [SceneSwitcherEntry], query: String, tags selected: Set<String> = []) -> [SceneSwitcherEntry] {
        let tagged: [SceneSwitcherEntry] = filter(entries, tags: selected)
        let needle: String = normalizedQuery(query)
        guard !needle.isEmpty else { return tagged }
        var first: [SceneSwitcherEntry] = []
        var rest: [SceneSwitcherEntry] = []
        for entry in tagged {
            let label: String = fold(entry.label)
            let name: String? = entry.sceneName.map(fold)
            let labelMatch: Bool = label.contains(needle)
            let nameMatch: Bool = name?.contains(needle) ?? false
            let folderMatch: Bool = entry.folderPath.map { (p: String) -> Bool in fold(p).contains(needle) } ?? false
            let tagMatch: Bool = entry.tags.contains { (t: String) -> Bool in fold(t).contains(needle) }   // SCN-005
            guard labelMatch || nameMatch || folderMatch || tagMatch else { continue }
            let early: Bool = startsWord(label, needle) || (name.map { (n: String) -> Bool in startsWord(n, needle) } ?? false)
            if early { first.append(entry) } else { rest.append(entry) }
        }
        return first + rest
    }

    /// SCN-005: the entries whose scene carries every selected tag (folded; AND). Show order kept.
    static func filter(_ entries: [SceneSwitcherEntry], tags selected: Set<String>) -> [SceneSwitcherEntry] {
        guard !selected.isEmpty else { return entries }
        let wanted: Set<String> = Set(selected.map(fold))
        return entries.filter { (entry: SceneSwitcherEntry) -> Bool in
            let own: Set<String> = Set(entry.tags.map(fold))
            return wanted.isSubset(of: own)
        }
    }

    private static let separators: Set<Character> = [" ", "-", "_", ".", "/"]

    /// True when `text` starts with `needle` or a word of it does.
    static func startsWord(_ text: String, _ needle: String) -> Bool {
        if text.hasPrefix(needle) { return true }
        var index = text.startIndex
        while index < text.endIndex {
            let character: Character = text[index]
            let next = text.index(after: index)
            if separators.contains(character), text[next...].hasPrefix(needle) { return true }
            index = next
        }
        return false
    }
}

/// One choice's measurement (UIX-002-R8).
struct SceneSwitchMeasurement: Equatable, Sendable {
    enum Outcome: String, Sendable {
        case applied, repairShown, failed
    }

    let outcome: Outcome
    let sceneID: String
    let cueID: UUID
    let seconds: Double
    let budget: Double

    /// Milliseconds rounded to 0.1.
    var milliseconds: Double { (seconds * 10_000).rounded() / 10 }
    var withinBudget: Bool { seconds <= budget }

    /// "<outcome>|<sceneID>|<ms>|<ok|over>" (DEBUG probe `sceneSwitcherProbe`).
    var probeText: String {
        let ms: String = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), milliseconds)
        let verdict: String = withinBudget ? "ok" : "over"
        return "\(outcome.rawValue)|\(sceneID)|\(ms)|\(verdict)"
    }
}

/// Times a choice to its end point on the caller's monotonic clock (research UIX-002-D3).
struct SceneSwitchLatencyProbe: Sendable {
    /// The simulator budget for choice → applied state (UIX-002-R8, S2).
    static let budget: Double = 0.250

    private struct Pending: Sendable {
        let sceneID: String
        let cueID: UUID
        let start: Double
    }

    private var pending: Pending?
    private(set) var last: SceneSwitchMeasurement?

    var isPending: Bool { pending != nil }

    /// Starts a measurement (replaces one still pending).
    mutating func begin(sceneID: String, cueID: UUID, now: Double) {
        pending = Pending(sceneID: sceneID, cueID: cueID, start: now)
    }

    /// Ends the pending measurement; nil when none is pending.
    @discardableResult
    mutating func finish(_ outcome: SceneSwitchMeasurement.Outcome, now: Double) -> SceneSwitchMeasurement? {
        guard let started = pending else { return nil }
        pending = nil
        let elapsed: Double = max(0, now - started.start)
        let measurement = SceneSwitchMeasurement(outcome: outcome, sceneID: started.sceneID, cueID: started.cueID,
                                                 seconds: elapsed, budget: Self.budget)
        last = measurement
        return measurement
    }
}

/// The overlay's state (UIX-002-R4 to R6; data-model "SceneSwitcherModel").
@MainActor
@Observable
final class SceneSwitcherModel {
    private(set) var isOpen = false
    /// The field's text, never trimmed in place.
    var query = ""
    /// The highlighted cue; nil only when nothing matches.
    private(set) var highlightedCueID: UUID?
    /// The query at the last close without a choice ("" after a choice).
    private(set) var abandonedQuery = ""
    /// Bumped on a close without a choice: the Scenes button takes VoiceOver focus (UIX-002-R11).
    private(set) var focusReturnRevision = 0
    /// The last choice's latency (UIX-002-R8).
    var probe = SceneSwitchLatencyProbe()
    /// SCN-005: the selected tag chips (folded), kept while the app runs; never stored.
    private(set) var selectedTags: Set<String> = []

    @ObservationIgnored let now: @MainActor () -> Double

    init(now: @escaping @MainActor () -> Double = { () -> Double in ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    func results(_ entries: [SceneSwitcherEntry]) -> [SceneSwitcherEntry] {
        SceneSwitcherFilter.results(entries, query: query, tags: selectedTags)
    }

    /// SCN-005: whether a chip is selected.
    func isSelected(tag: String) -> Bool { selectedTags.contains(SceneSwitcherFilter.fold(tag)) }

    /// SCN-005: selects or clears a chip; selections whose tag left `vocabulary` are dropped.
    func toggleTag(_ tag: String, vocabulary: [String]) {
        let key: String = SceneSwitcherFilter.fold(tag)
        if selectedTags.contains(key) { selectedTags.remove(key) } else { selectedTags.insert(key) }
        pruneTags(vocabulary: vocabulary)
    }

    /// SCN-005: drops selections no scene carries any more (SCN-005 Edge Cases).
    func pruneTags(vocabulary: [String]) {
        let live: Set<String> = Set(vocabulary.map(SceneSwitcherFilter.fold))
        selectedTags = selectedTags.intersection(live)
    }

    /// Opens with the abandoned query (and its highlight when it still matches), else the active
    /// entry, else the first result.
    func open(entries: [SceneSwitcherEntry]) {
        guard !isOpen else { return }
        let restoring: Bool = !abandonedQuery.isEmpty
        query = abandonedQuery
        let shown: [SceneSwitcherEntry] = results(entries)
        if restoring, let kept = highlightedCueID, shown.contains(where: { (e: SceneSwitcherEntry) -> Bool in e.cueID == kept }) {
            highlightedCueID = kept
        } else if let active = shown.first(where: { (e: SceneSwitcherEntry) -> Bool in e.isActive }) {
            highlightedCueID = active.cueID
        } else {
            highlightedCueID = shown.first?.cueID
        }
        isOpen = true
    }

    /// After the query changed: the same entry while it matches, else the first result, else none.
    func queryChanged(entries: [SceneSwitcherEntry]) {
        let shown: [SceneSwitcherEntry] = results(entries)
        if let kept = highlightedCueID, shown.contains(where: { (e: SceneSwitcherEntry) -> Bool in e.cueID == kept }) { return }
        highlightedCueID = shown.first?.cueID
    }

    /// Moves the highlight by `offset` within the results, clamped at both ends (no wrap).
    func moveHighlight(by offset: Int, entries: [SceneSwitcherEntry]) {
        let shown: [SceneSwitcherEntry] = results(entries)
        guard !shown.isEmpty else { highlightedCueID = nil; return }
        guard let current = highlightedCueID,
              let index = shown.firstIndex(where: { (e: SceneSwitcherEntry) -> Bool in e.cueID == current }) else {
            highlightedCueID = shown[0].cueID
            return
        }
        let target: Int = min(max(index + offset, 0), shown.count - 1)
        highlightedCueID = shown[target].cueID
    }

    /// The highlighted entry among the current results.
    func highlighted(in entries: [SceneSwitcherEntry]) -> SceneSwitcherEntry? {
        guard let id = highlightedCueID else { return nil }
        return results(entries).first(where: { (e: SceneSwitcherEntry) -> Bool in e.cueID == id })
    }

    func close(chose: Bool) {
        guard isOpen else { return }
        isOpen = false
        if chose {
            abandonedQuery = ""
            query = ""
        } else {
            abandonedQuery = query
            focusReturnRevision += 1
        }
    }

    #if DEBUG
    /// The last measurement for the `sceneSwitcherProbe` element, or "none".
    var probeText: String { probe.last?.probeText ?? "none" }
    #endif
}
