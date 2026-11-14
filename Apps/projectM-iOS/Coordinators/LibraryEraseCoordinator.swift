// LibraryEraseCoordinator.swift — FILE-011 (contract E7; FILE-011-R1-R3, R7, R9): Settings › Storage ›
// Erase Data….
//
// * The sheet lists the six categories with counts and sizes (`LibraryEraseInventory`, measured off the
//   main thread); the user checks some, then confirms in a destructive alert naming them.
// * Confirming records a request (`LibraryEraseRequestStore`); the erase runs at the next launch in
//   `finishPendingErase`, called from `LibraryBackupCoordinator.finishPendingRestore` before any store
//   reads the library (research FILE-011-D1), so nothing held in memory can write erased data back.
// * Cancel Erase removes the request. The launch-time result is shown once and announced on the shared
//   announcer's `library` lane. A pending restore (FILE-005) and a pending erase exclude each other.
// No networking.
import Foundation
import LibraryBackup
import Observation

@MainActor
@Observable
final class LibraryEraseCoordinator {
    static let pendingText = "Erase ready. Close projectM-iOS and open it again to finish."
    static let cancelledText = "The erase was cancelled. Nothing was erased."
    static let restorePendingNote = "Cancel the pending restore first."
    static let footer = "Erase removes data only on this device. Bundled presets, the full library purchase, caches and your Reduce flashing choice are kept. An erase cannot be undone except from a backup."

    private(set) var inventory: LibraryEraseInventory?
    var selection: Set<LibraryEraseCategory> = []
    var showSheet = false
    var showConfirmation = false
    /// The categories of the pending request (nil: none).
    private(set) var pending: Set<LibraryEraseCategory>?
    /// The last result or state change, shown in the section.
    private(set) var message: String?

    /// The shared announcer's `library` lane (forwarded by LibraryBackupCoordinator).
    @ObservationIgnored var announce: (@MainActor (String) -> Void)?
    /// FILE-005: true while a restore waits for the next launch.
    @ObservationIgnored var isRestorePending: @MainActor () -> Bool = { () -> Bool in false }
    @ObservationIgnored let root: URL
    @ObservationIgnored private let defaults: UserDefaults
    /// The running measurement (tests await it).
    @ObservationIgnored private(set) var work: Task<Void, Never>?

    init(root: URL, defaults: UserDefaults) {
        self.root = root
        self.defaults = defaults
    }

    /// Before any store reads the library (and before a pending restore).
    nonisolated static func finishPendingErase(defaults: UserDefaults, root: URL) {
        let settings = LibrarySettingsBridge.read(defaults, keys: LibraryErasePolicy.planningKeys)
        LibraryEraseLaunch.run(root: root, settings: settings) { (keys: [String]) in
            LibrarySettingsBridge.remove(keys, from: defaults)
        }
    }

    // MARK: - Section state

    /// The section appeared: the pending request, the launch result (once) and the counts.
    func refresh() {
        let store = LibraryEraseRequestStore(root: root)
        pending = store.pending
        if let note = store.takeResult() {
            message = note.message
            announce?(note.message)
        }
        measure()
    }

    /// Erase Data… is offered while no erase and no restore is pending.
    var canStart: Bool { pending == nil && !isRestorePending() }

    func measure() {
        let root = root
        let settings = LibrarySettingsBridge.read(defaults, keys: LibraryErasePolicy.erasableKeys)
        work = Task { @MainActor [weak self] in
            let result: LibraryEraseInventory = await Task.detached(priority: .utility) { () -> LibraryEraseInventory in
                LibraryEraseInventory.measure(root: root, settings: settings)
            }.value
            self?.inventory = result
        }
    }

    // MARK: - Sheet

    func openSheet() {
        guard canStart else { return }
        selection = []
        showConfirmation = false
        showSheet = true
        measure()
    }

    func toggle(_ category: LibraryEraseCategory) {
        if selection.contains(category) { selection.remove(category) } else { selection.insert(category) }
    }

    var allSelected: Bool { selection.count == LibraryEraseCategory.allCases.count }

    func toggleAll() {
        selection = allSelected ? [] : Set(LibraryEraseCategory.allCases)
    }

    /// Erase… : the confirmation (FILE-011-R2).
    func continueTapped() {
        guard !selection.isEmpty else { return }
        showConfirmation = true
    }

    func dismissSheet() {
        showConfirmation = false
        showSheet = false
        selection = []
    }

    /// Erase at Next Launch.
    func requestErase() {
        let chosen = selection
        showConfirmation = false
        guard !chosen.isEmpty, canStart else { return }
        do {
            try LibraryEraseRequestStore(root: root).save(chosen)
            pending = chosen
            message = nil
            announce?(Self.pendingText)
        } catch {
            message = LibraryEraseText.failed
            announce?(LibraryEraseText.failed)
        }
        showSheet = false
        selection = []
    }

    func cancelErase() {
        LibraryEraseRequestStore(root: root).cancel()
        pending = nil
        message = Self.cancelledText
        announce?(Self.cancelledText)
    }

    // MARK: - Words (typed steps, FILE-011-R2)

    /// "Erase 2 categories?"
    static func confirmationTitle(_ chosen: Set<LibraryEraseCategory>) -> String {
        let count: Int = chosen.count
        let noun: String = count == 1 ? "category" : "categories"
        return "Erase " + String(count) + " " + noun + "?"
    }

    /// "Scenes and show (4 items) and Photos and videos (2 items) will be erased the next time … "
    static func confirmationMessage(_ chosen: Set<LibraryEraseCategory>, inventory: LibraryEraseInventory?) -> String {
        let parts: [String] = chosen.sorted().map { (category: LibraryEraseCategory) -> String in
            guard let item = inventory?.item(category) else { return category.title }
            return category.title + " (" + itemPhrase(item.count) + ")"
        }
        let list: String
        if parts.count > 1, let last = parts.last {
            list = parts.dropLast().joined(separator: ", ") + " and " + last
        } else {
            list = parts.first ?? ""
        }
        let kept = "Bundled presets, the full library purchase and caches are kept."
        return list + " will be erased the next time projectM-iOS opens. " + kept + " This cannot be undone except from a backup."
    }

    static func itemPhrase(_ count: Int) -> String { String(count) + (count == 1 ? " item" : " items") }

    /// "4 items, 12 KB" (settings: "3 items").
    static func detail(_ item: LibraryEraseInventory.Item?) -> String {
        guard let item else { return "Calculating…" }
        let count: String = itemPhrase(item.count)
        guard let bytes = item.bytes else { return count }
        return count + ", " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// "Erase ready … Scenes and show and My Presets will be erased."
    static func pendingDetail(_ chosen: Set<LibraryEraseCategory>) -> String {
        LibraryErasePolicy.list(chosen) + " will be erased."
    }
}
