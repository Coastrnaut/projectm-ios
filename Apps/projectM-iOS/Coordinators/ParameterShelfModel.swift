// ParameterShelfModel.swift — UIX-004: the favorite parameter shelf's stored pins (UIX-004-R2, R5 to R8, R10;
// specs/151-uix-004-parameter-shelf, research UIX-004-D1 to D3, D6, contracts/parameter-shelf.md P4).
//
// * `settings.parameterShelf.pins`: an ordered list of parameter ID strings ([String]; absent = empty shelf).
//   Included in library backups and erased with Settings (FILE-005 `LibrarySettingsPolicy.includedKeys`), in
//   `ALLOWED_KEYS`, removed by `-uitestResetNotice`. Not part of scenes or cues.
// * An entry is available when the MOD-001 registry has it and UIX-003 can write it (an inspectable ID). Other
//   entries (a later version's IDs, corrupt values, non-strings) are skipped, counted in one note, logged once
//   at load, and kept until the user removes them, so a downgrade and upgrade round-trips (UIX-004-R7).
// * At most `maxPins` (8) available pins; unavailable entries do not count (spec Clarifications).
// Every intermediate is a named, typed value (CI's type-check budget).
import Foundation
import Observation
import os
import ParameterGraph

// MARK: - Decoding the stored value (research UIX-004-D2)

enum ParameterShelfStorage {
    /// The stored entries in order: strings are kept, any other element (and a value that is not a list)
    /// becomes its text form, so it is counted and removable; later duplicates are dropped.
    static func decode(_ stored: Any?) -> [String] {
        guard let stored else { return [] }
        let raw: [String]
        if let strings = stored as? [String] {
            raw = strings
        } else if let items = stored as? [Any] {
            raw = items.map { (item: Any) -> String in (item as? String) ?? String(describing: item) }
        } else {
            raw = [(stored as? String) ?? String(describing: stored)]
        }
        var seen: Set<String> = []
        var result: [String] = []
        for entry in raw where !seen.contains(entry) {
            seen.insert(entry)
            result.append(entry)
        }
        return result
    }
}

// MARK: - The shelf

@MainActor
@Observable
final class ParameterShelf {
    static let pinsKey = "settings.parameterShelf.pins"
    static let maxPins = 8
    /// "Shelf Full (8)": the disabled Pin to Shelf item at the limit (contract P1).
    static let fullTitle = "Shelf Full (\(maxPins))"
    static let footer = "Pin up to \(maxPins) settings from their Inspect menu. Pinned controls appear with the visualizer's controls, in this order."

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let isAvailable: (ParameterID) -> Bool
    private static let log = Logger(subsystem: "org.projectmios.ProjectMiOS", category: "parameterShelf")

    /// The stored entries in shelf order, unavailable ones included; saved on every change.
    private(set) var entries: [String] {
        didSet { if entries != oldValue { defaults.set(entries, forKey: Self.pinsKey) } }
    }

    /// `isAvailable` defaults to "registered and editable" (research UIX-004-D1).
    init(defaults: UserDefaults, isAvailable: ((ParameterID) -> Bool)? = nil) {
        self.defaults = defaults
        self.isAvailable = isAvailable ?? ParameterShelf.isPinnable
        entries = ParameterShelfStorage.decode(defaults.object(forKey: Self.pinsKey))
        logMissing()
    }

    /// Registered in the visual catalog and written by a Settings control (UIX-003's inspectable IDs).
    nonisolated static func isPinnable(_ id: ParameterID) -> Bool {
        guard ParameterInspectorCatalog.registry?.contains(id) ?? false else { return false }
        return ParameterInspectorTargets.inspectableIDSet.contains(id)
    }

    // MARK: Reading

    /// The available pins in shelf order.
    var pinned: [ParameterID] {
        let ids: [ParameterID] = entries.map { (entry: String) -> ParameterID in ParameterID(entry) }
        return ids.filter { (id: ParameterID) -> Bool in isAvailable(id) }
    }

    /// The stored entries this version cannot show, in stored order.
    var missing: [String] {
        entries.filter { (entry: String) -> Bool in !isAvailable(ParameterID(entry)) }
    }

    var isEmpty: Bool { entries.isEmpty }

    func isPinned(_ id: ParameterID) -> Bool { pinned.contains(id) }

    /// A free slot remains (unavailable entries do not count).
    var canPin: Bool { pinned.count < Self.maxPins }

    /// "1 pinned control is no longer available" / "N pinned controls are no longer available"; nil when none.
    var missingNote: String? { Self.missingNote(count: missing.count) }

    nonisolated static func missingNote(count: Int) -> String? {
        guard count > 0 else { return nil }
        if count == 1 { return "1 pinned control is no longer available" }
        return "\(count) pinned controls are no longer available"
    }

    // MARK: Changing

    /// Appends `id` when it is available, not pinned yet and a slot is free; false otherwise (no change).
    @discardableResult
    func pin(_ id: ParameterID) -> Bool {
        guard isAvailable(id), !isPinned(id), canPin else { return false }
        entries.append(id.rawValue)
        return true
    }

    func unpin(_ id: ParameterID) {
        entries.removeAll { (entry: String) -> Bool in entry == id.rawValue }
    }

    func toggle(_ id: ParameterID) {
        if isPinned(id) { unpin(id) } else { pin(id) }
    }

    /// Reorders the available pins (List `onMove` offsets); unavailable entries follow them.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var order: [ParameterID] = pinned
        order.move(fromOffsets: source, toOffset: destination)
        apply(order)
    }

    /// Deletes available pins at List `onDelete` offsets.
    func remove(atOffsets offsets: IndexSet) {
        var order: [ParameterID] = pinned
        order.remove(atOffsets: offsets)
        apply(order)
    }

    /// VoiceOver "Move up": one place earlier; no change at the top.
    func moveUp(_ id: ParameterID) { shift(id, by: -1) }

    /// VoiceOver "Move down": one place later; no change at the bottom.
    func moveDown(_ id: ParameterID) { shift(id, by: 1) }

    /// The note's Remove: deletes exactly the unavailable entries; the pins keep their order (UIX-004-R8).
    func removeMissing() {
        let kept: [String] = pinned.map(\.rawValue)
        entries = kept
    }

    private func shift(_ id: ParameterID, by delta: Int) {
        var order: [ParameterID] = pinned
        guard let index = order.firstIndex(of: id) else { return }
        let target: Int = index + delta
        guard target >= 0, target < order.count else { return }
        order.swapAt(index, target)
        apply(order)
    }

    private func apply(_ order: [ParameterID]) {
        let pins: [String] = order.map(\.rawValue)
        entries = pins + missing
    }

    /// UIX-004-R7: once per load; the count is public, the entries private.
    private func logMissing() {
        let unavailable: [String] = missing
        guard !unavailable.isEmpty else { return }
        let count: Int = unavailable.count
        let joined: String = unavailable.joined(separator: ", ")
        Self.log.notice("Parameter shelf: \(count, privacy: .public) pinned entries are not available: \(joined, privacy: .private)")
    }
}

// MARK: - Control spec shared with the inspector

enum ParameterShelfControlSpec {
    /// The ACC-005 slider spec of a numeric descriptor: step = the hint (at least 1% of the span), tidied.
    static func slider(_ descriptor: ParameterDescriptor, bounds: ClosedRange<Double>, id: String) -> AccessibleParameterSpec {
        let span: Double = bounds.upperBound - bounds.lowerBound
        let hint: Double = descriptor.kind.stepHint ?? span / 100
        let step: Double = ParameterStepper.tidy(max(hint, span / 100))
        let unit: SpokenUnit = ParameterValueText.spokenUnit(descriptor.unit, step: descriptor.kind.stepHint)
        return AccessibleParameterSpec(id: id, label: descriptor.displayName, range: bounds, step: step, unit: unit)
    }

    /// The fixed choices of a target or an enum descriptor; nil for free values.
    @MainActor
    static func choices(_ descriptor: ParameterDescriptor, target: ParameterInspectorTarget) -> [ParameterValue]? {
        if let choices = target.choices { return choices }
        let cases: [ParameterEnumCase] = descriptor.kind.enumCases
        return cases.isEmpty ? nil : cases.map { (c: ParameterEnumCase) -> ParameterValue in .enumeration(c.id) }
    }
}
