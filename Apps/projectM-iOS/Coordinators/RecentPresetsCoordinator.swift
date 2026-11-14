// RecentPresetsCoordinator.swift — roadmap PRE-006 (specs/159-pre-006-recent-history; contract C1;
// R2-R6): what the browser's Recently Played list and Settings' Recently Played section use.
//
// * `shown(_:)` is called by PresetCoordinator after every successful load, whatever chose the preset.
//   The preset becomes the dwell candidate (RecentPresetDwell, 3 s on the injected monotonic clock) and a
//   check is scheduled; when it fires and the preset is still the candidate, it is recorded (R2).
// * `setEnabled(false)` stops recording, cancels the candidate and clears the list (R3); `clear()`
//   removes the list only (R4). Both announce on the shared announcer's library lane (R6).
// No networking; nothing but preset IDs is stored.
import Foundation
import Observation
import PresetLibrary

@MainActor
@Observable
final class RecentPresetsCoordinator {
    static let clearedText = "Recently played history cleared."
    static let turnedOffText = "Recently played history is off and was cleared."
    static let turnedOnText = "Recently played history is on."
    static let emptyText = "No recently played presets yet."
    static let offText = "Recently played history is off."
    nonisolated static let title = "Recently Played"
    static let clearTitle = "Clear History"
    static let confirmationTitle = "Clear recently played history?"
    static let confirmationMessage = "This removes the list of recently played presets on this device. Favorites, collections and tags are kept."

    /// The stored history, most recent first.
    private(set) var ids: [String]
    private(set) var isEnabled: Bool

    /// The shared announcer's library lane (set by AppCoordinator).
    @ObservationIgnored var announce: (String) -> Void = { (_: String) in }
    @ObservationIgnored private let store: RecentPresetsStore
    @ObservationIgnored private var dwell = RecentPresetDwell()
    @ObservationIgnored private let now: () -> Double
    @ObservationIgnored private let schedule: (Double, @escaping @MainActor () -> Void) -> Void

    /// `now`: monotonic seconds; `schedule(delay, work)`: runs `work` on the main actor after `delay`
    /// seconds. Tests pass a fake clock and keep the scheduled work to run it themselves.
    init(store: RecentPresetsStore,
         now: @escaping () -> Double = { () -> Double in ProcessInfo.processInfo.systemUptime },
         schedule: @escaping (Double, @escaping @MainActor () -> Void) -> Void = RecentPresetsCoordinator.sleepThenRun) {
        self.store = store
        self.now = now
        self.schedule = schedule
        ids = store.history.ids
        isEnabled = store.isEnabled
    }

    nonisolated static func sleepThenRun(_ delay: Double, _ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            work()
        }
    }

    /// A preset loaded successfully and is now on screen (R2).
    func shown(_ id: String) {
        guard isEnabled else { return }
        dwell.shown(id, at: now())
        schedule(RecentPresetDwell.threshold) { [weak self] () -> Void in self?.checkDwell() }
    }

    /// Records the candidate once its 3 s have passed (an earlier check for a replaced preset does nothing).
    func checkDwell() {
        guard isEnabled, let id = dwell.due(at: now()) else { return }
        ids = store.record(id).ids
    }

    /// "Remember Recently Played" (R3): off clears the list and stops recording.
    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        store.isEnabled = on
        isEnabled = on
        if !on {
            dwell.cancel()
            ids = []
        }
        announce(on ? Self.turnedOnText : Self.turnedOffText)
    }

    /// Clear History (R4): the list only.
    func clear() {
        dwell.cancel()
        store.clear()
        ids = []
        announce(Self.clearedText)
    }

    /// The recorded presets the library lists, most recent first (locked ones included; R5).
    func listing(in library: PresetLibrary?) -> [IndexedPreset] {
        library?.collectionListing(ids) ?? []
    }

    /// "Recently Played, 2 presets" (R6).
    nonisolated static func rowLabel(count: Int) -> String {
        title + ", " + String(count) + (count == 1 ? " preset" : " presets")
    }
}
