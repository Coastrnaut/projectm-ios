// PresetCoordinator.swift — preset browsing and switching over the full library (feature 001
// T090, T091; feature 002 T217, T228, T230, T231, T245, T246).
//
// * The library (PresetLibrary) arrives off the main thread after launch (`attach`); until then
//   nothing is listed.
// * Next, Previous and Random walk the current scope's members: alphabetical, playable only
//   (unlocked, not excluded, not failed this session), wrapping; Random never repeats the current
//   preset when another exists (FR-116-FR-118, feature 001 FR-088).
// * Choosing a preset from a list sets the scope to that list (FR-116). The scope persists as
//   `settings.presetScope` (a search scope is stored as All; FR-119, FR-123).
// * Before purchase the default scope is Included (exactly release 1.0's behavior, SC-107); after a
//   purchase or restore it becomes Cream of the Crop; after a refund it falls back to Included
//   and the playing preset keeps playing (FR-109).
// * Selecting a locked preset asks for the purchase sheet instead of playing it (FR-106).
// * Collections (roadmap PRE-007, specs/005-pre-007-preset-collections): named lists in the user's
//   own order, kept by PresetCollectionStore (one versioned file, saved atomically). A collection
//   is a scope too: Next and Previous follow the user's order. Locked presets may be listed in a
//   collection but never play through it (PRE-007-R13). Every change is saved before it is shown;
//   a refusal or a failed save sets `collectionsMessage` and changes nothing (PRE-007-R8).
// * A preset that fails to load leaves the running one on screen, shows "Preset could not be
//   loaded", and is excluded from every scope for the rest of the session (FR-045, FR-118).
// * Imported presets (roadmap PRE-012, specs/008-pre-012-preset-import-validation): the playable
//   ones join the library as the source `user` and form the scope My Presets. Before one is
//   loaded, after it loaded, when it is replaced and when its load fails, `userGuard` is told
//   (PRE-012-R18, R19): a failing one is quarantined, and the running preset stays.
// * Copies of built-in presets (roadmap PRE-015, specs/010-pre-015-user-preset-duplication): the
//   user guard hears about entitlement changes before the scope changes, so copies of locked
//   packs leave or rejoin the library first (PRE-015-R8); favorites of user presets that are
//   only waiting (for a check or for the unlock) are kept; an edited preset on screen is
//   reloaded with its new text (R17).
// * Reduced flash preset policy (roadmap ACC-002, specs/030-acc-002-reduced-flash-preset-policy,
//   ADR-0014): while Reduce flashing is on, presets the flash risk screen flagged are skipped by
//   Next, Previous, Random, the warm-up and the launch preset (they walk `walkable`), and choosing
//   one by name sets `flashWarning` instead of loading it, until Load Anyway or Cancel. With the
//   setting off nothing changes. FX-019's envelope still limits every frame either way.
import Foundation
import Observation
import PresetLibrary

/// Loads a library preset into the renderer (the app resolves files and archive data; a fake in tests).
@MainActor
protocol PresetLoading: AnyObject {
    func load(_ preset: IndexedPreset) async throws
    /// Presets likely to be chosen next, for the renderer to warm up (SC-104). Optional.
    func prewarm(_ presets: [IndexedPreset])
}

extension PresetLoading {
    func prewarm(_ presets: [IndexedPreset]) {}
}

@MainActor
@Observable
final class PresetCoordinator {
    static let failureText = "Preset could not be loaded"
    static let emptyFavoritesText = "No favorites yet — tap the star on a preset to add one."
    static let unlockScope = PresetScope.pack("cream-of-the-crop")
    /// ACC-002-R9: Next, Previous or Random found only flagged presets in the scope.
    static let allFlaggedText = "Every preset here may flash."
    static let flashWarningTitle = "May flash"
    /// ACC-002-R6: the warning's message for a flagged preset chosen by name.
    nonisolated static func flashWarningMessage(_ name: String) -> String {
        "“\(name)” may contain fast flashing. Reduce flashing still limits flashes while it plays."
    }
    /// ACC-002-R7: what a flagged row adds to its VoiceOver label.
    nonisolated static let mayFlashLabel = "may flash"

    /// ACC-002: a flagged preset the user chose by name, waiting for Load Anyway or Cancel.
    struct FlashWarning: Equatable, Identifiable {
        let preset: IndexedPreset
        let scope: PresetScope
        var id: String { preset.id }
    }

    private(set) var library: PresetLibrary?
    /// The bundled library, without the user's imported presets (PRE-012).
    @ObservationIgnored private var builtInLibrary: PresetLibrary?
    @ObservationIgnored private var userPresets: [IndexedPreset] = []
    /// Told about imported presets on the visible renderer (PRE-012-R18, R19).
    @ObservationIgnored weak var userGuard: (any UserPresetGuarding)?
    /// User presets that exist but are not in the library now (waiting for a check or for the
    /// unlock): their favorites are kept (PRE-015-R8).
    @ObservationIgnored var retainedUserPresetIDs: Set<String> = []
    /// PRE-001: the rows' thumbnails (set by the app; nil in tests that do not need them).
    @ObservationIgnored var thumbnails: PresetThumbnailModel?
    private(set) var current: IndexedPreset?
    private(set) var scope: PresetScope
    private(set) var unlocked = false
    var favoritesOnly = false
    private(set) var failureMessage: String?
    /// Set when a locked preset is chosen; the purchase sheet observes it (FR-106).
    var purchaseRequested = false
    /// The locked preset the user tapped, played after a purchase (FR-107).
    private(set) var pendingLockedPreset: IndexedPreset?
    /// Bumped on every favorite change so views refresh.
    private(set) var favoritesVersion = 0
    private(set) var excludedThisSession: Set<String> = []
    /// The next Random pick, chosen in advance so the renderer can warm it up (SC-104). Chosen
    /// uniformly from the scope, never the current preset (FR-117, SC-106).
    private(set) var plannedRandom: IndexedPreset?
    /// ACC-002-R6: set while a flagged preset chosen by name waits for the user's decision. Never
    /// stored (R12).
    private(set) var flashWarning: FlashWarning?

    /// Bumped on every collections change so views refresh (PRE-007).
    private(set) var collectionsVersion = 0
    /// Why the last collections action was refused or could not be saved; shown as an alert.
    var collectionsMessage: String?
    /// Set once when unreadable saved collections were set aside (PRE-007-R15).
    private(set) var collectionsNotice: String?

    @ObservationIgnored private let store: FavoritesStore
    @ObservationIgnored private let collectionStore: PresetCollectionStore
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let loader: any PresetLoading
    @ObservationIgnored private var scopeAnnouncer: ((String) -> Void)?

    init(store: FavoritesStore, settings: AppSettings, loader: any PresetLoading, collections: PresetCollectionStore) {
        self.store = store
        collectionStore = collections
        if collections.loadNotice == .unreadableSetAside { collectionsNotice = PresetCollectionStore.unreadableText }
        self.settings = settings
        self.loader = loader
        scope = settings.presetScope.flatMap(PresetScope.init(storageValue:)) ?? .included
    }

    /// The library is ready (FR-111). Drops favorites that no longer exist and resolves the stored scope.
    func attach(_ builtIn: PresetLibrary) {
        builtInLibrary = builtIn
        let library = builtIn.withUserPresets(userPresets)
        self.library = library
        let missing = store.favorites.filter { library.preset(id: $0) == nil && !retainedUserPresetIDs.contains($0) }
        for id in missing { store.toggle(id) }
        if !missing.isEmpty { favoritesVersion += 1 }
        resolveScope()
    }

    func onScopeChange(_ announce: @escaping (String) -> Void) { scopeAnnouncer = announce }

    /// The user's playable imported presets changed (PRE-012-R22). They are part of the library
    /// from now on; presets that left it stop being listed, and an empty My Presets is not kept
    /// as the scope. The playing preset keeps playing.
    func setUserPresets(_ presets: [IndexedPreset]) {
        guard presets != userPresets else { return }
        userPresets = presets
        guard let builtInLibrary else { return }
        library = builtInLibrary.withUserPresets(presets)
        plannedRandom = nil
        resolveScope()
    }

    // MARK: - Entitlement (FR-107, FR-109, FR-119)

    func setUnlocked(_ value: Bool) async {
        guard value != unlocked else { return }
        unlocked = value
        await userGuard?.libraryUnlockChanged(value)   // PRE-015-R8: copies of locked packs first
        if value {
            setScope(Self.unlockScope)
            if let pending = pendingLockedPreset {
                pendingLockedPreset = nil
                await choose(pending, from: Self.unlockScope)   // ACC-002: a flagged one is warned first
            }
        } else {
            setScope(.included)   // the playing preset keeps playing (FR-109)
        }
    }

    // MARK: - Lists

    /// The preset to start with: the last selected one if it is playable, else the scope's first.
    var initialPreset: IndexedPreset? {
        guard let library else { return nil }
        if let id = store.lastPresetID, let last = library.preset(id: id), isPlayable(last), !isFlagged(last) { return last }
        return walkable.first   // ACC-002-R10: never a flagged preset while Reduce flashing is on
    }

    /// Members of the current scope (what Next/Previous/Random walk).
    var members: [IndexedPreset] {
        guard let library else { return [] }
        _ = favoritesVersion
        var collections: [String: [String]] = [:]
        if case .collection = scope {
            _ = collectionsVersion
            collections = collectionStore.presetIDsByCollection
        }
        return library.members(of: scope, unlocked: unlocked, favorites: Set(store.favorites), excluded: excludedThisSession,
                               collections: collections)
    }

    /// ACC-002: whether the policy applies to this preset now (Reduce flashing on and flagged).
    func isFlagged(_ preset: IndexedPreset) -> Bool { settings.effectiveReduceFlashing && preset.mayFlash }

    /// ACC-002-R5: what Next, Previous, Random and the warm-up walk: the scope's members without
    /// flagged presets while Reduce flashing is on (exactly `members` with it off, R8).
    var walkable: [IndexedPreset] {
        let all = members
        guard settings.effectiveReduceFlashing else { return all }
        return all.filter { !$0.mayFlash }
    }

    /// ACC-002-R7: a row's VoiceOver label, with ", may flash" for a flagged preset.
    func rowLabel(_ preset: IndexedPreset, locked: Bool) -> String {
        "\(preset.name), by \(preset.author)\(locked ? ", locked" : "")\(preset == current ? ", current preset" : "")"
            + (isFlagged(preset) ? ", \(Self.mayFlashLabel)" : "")
    }

    /// FR-114: favorites across packs, alphabetical, locked ones listed (marked by the view).
    var favoritesListing: [IndexedPreset] {
        _ = favoritesVersion
        return library?.favoritesListing(Set(store.favorites)) ?? []
    }

    var emptyStateText: String? {
        favoritesOnly && favoritesListing.isEmpty ? Self.emptyFavoritesText : nil
    }

    /// Presets of a node's own folder level (not its subfolders), alphabetical.
    func presets(in node: PresetNode) -> [IndexedPreset] {
        guard let library else { return [] }
        let all = library.members(of: node.scope, unlocked: true, favorites: [], excluded: [])
        guard case .folder(_, let path) = node.scope else {
            if case .pack = node.scope { return all.filter(\.folder.isEmpty) }
            return all
        }
        return all.filter { $0.folder == path }
    }

    /// FR-111: a home or folder row's count. Locked rows show their total; rows the user can play
    /// show the playable count, so presets that failed to load this session are left out (FR-118).
    func displayCount(of node: PresetNode) -> Int {
        guard !(node.locked && !unlocked), !excludedThisSession.isEmpty, let library else { return node.presetCount }
        let failedHere = excludedThisSession.compactMap { library.preset(id: $0) }.filter { preset in
            switch node.scope {
            case .included: preset.isIncluded
            case .pack(let id): preset.source == id
            case .folder(let id, let path): preset.source == id && preset.folder.starts(with: path)
            case .all: unlocked || preset.isIncluded
            case .favorites, .search, .collection, .user: false
            }
        }.count
        return max(0, node.presetCount - failedHere)
    }

    func isLocked(_ preset: IndexedPreset) -> Bool { library?.isLocked(preset, unlocked: unlocked) ?? false }

    func isPlayable(_ preset: IndexedPreset) -> Bool { !isLocked(preset) && !excludedThisSession.contains(preset.id) }

    func isFavorite(_ preset: IndexedPreset) -> Bool {
        _ = favoritesVersion
        return store.isFavorite(preset.id)
    }

    func toggleFavorite(_ preset: IndexedPreset) {
        store.toggle(preset.id)
        favoritesVersion += 1
    }

    /// ACC-004: set by AppCoordinator; speaks a favorite change the user made.
    @ObservationIgnored var announceFavorite: (String) -> Void = { (_: String) in }

    /// The star and the rotor action (ACC-004-R3, R5): toggles and announces the new state.
    func toggleFavoriteAnnounced(_ preset: IndexedPreset) {
        toggleFavorite(preset)
        announceFavorite(AccessibilityAnnouncer.favoriteText(preset.name, added: isFavorite(preset)))
    }

    /// "<scope> · <count>" under the preset name (FR-120).
    var scopeLine: String {
        guard let library else { return "" }
        return "\(title(of: scope, in: library)) · \(members.count)"
    }

    private func title(of scope: PresetScope, in library: PresetLibrary) -> String {
        guard case .collection = scope else { return library.title(of: scope) }
        _ = collectionsVersion
        return library.title(of: scope, collectionNames: collectionStore.namesByCollection)
    }

    // MARK: - Switching

    /// Chooses a preset from a list, making that list the scope (FR-116). A locked preset asks for
    /// the purchase instead (FR-106).
    func choose(_ preset: IndexedPreset, from listScope: PresetScope) async {
        if isLocked(preset) {
            pendingLockedPreset = preset
            purchaseRequested = true
            return
        }
        if isFlagged(preset) {   // ACC-002-R6: warned before anything loads
            flashWarning = FlashWarning(preset: preset, scope: listScope)
            return
        }
        await select(preset, in: listScope)
    }

    /// ACC-002-R6: Load Anyway. The warned preset loads in the list it was chosen from. The alert
    /// passes the warning it showed, so the order in which SwiftUI dismisses it does not matter.
    func confirmFlashWarning(_ shown: FlashWarning? = nil) async {
        guard let warning = shown ?? flashWarning else { return }
        if flashWarning == warning { flashWarning = nil }
        await select(warning.preset, in: warning.scope)
    }

    /// ACC-002-R6: Cancel (or the browser closed). Nothing loads.
    func cancelFlashWarning() { flashWarning = nil }

    /// Opens the purchase sheet without a preset to play afterwards (PRE-015-R7, R8: duplicating
    /// a locked preset, or tapping a copy that waits for the unlock).
    func requestPurchase() {
        pendingLockedPreset = nil
        purchaseRequested = true
    }

    /// PRE-015-R17: a user preset was saved from the editor. On screen with a new text, it is
    /// loaded again through the guarded path; renamed only, the shown entry is refreshed.
    func reloadIfCurrent(_ id: String) async {
        guard let current, current.id == id, let fresh = library?.preset(id: id), fresh != current else { return }
        if fresh.hash == current.hash {
            self.current = fresh
        } else {
            await select(fresh)
        }
    }

    /// Loads `preset`; on failure keeps the current one, reports it and excludes it for the
    /// session (FR-045, FR-118).
    func select(_ preset: IndexedPreset, in newScope: PresetScope? = nil) async {
        if let newScope { setScope(newScope) }
        let isUserPreset = preset.source == PresetLibrary.userSource
        if let current, current != preset, current.source == PresetLibrary.userSource { await userGuard?.stoppedShowing(current) }
        if isUserPreset { await userGuard?.willShow(preset) }   // PRE-012-R18: noted on disk before the engine sees it
        do {
            try await loader.load(preset)
            current = preset
            failureMessage = nil
            store.lastPresetID = preset.id
            planUpcoming()
            if isUserPreset { userGuard?.didShow(preset) }
        } catch {
            failureMessage = isUserPreset ? UserPresetText.onScreenFailure : Self.failureText
            excludedThisSession.insert(preset.id)
            // PRE-012-R19: the running preset stays; the imported one is quarantined for good.
            if isUserPreset { await userGuard?.failedOnScreen(preset, message: (error as NSError).localizedDescription) }
        }
    }

    func next() async { await step(1) }
    func previous() async { await step(-1) }

    func random() async {
        let scopeMembers = walkable
        var pick = plannedRandom
        if pick == nil || pick == current || !scopeMembers.contains(pick!) {
            var generator = SystemRandomNumberGenerator()
            pick = ScopeStepper.random(scopeMembers, excluding: current, using: &generator)
        }
        guard let pick, pick != current else {
            if scopeMembers.isEmpty { reportEmptyWalk() }
            return
        }
        await select(pick)
    }

    /// After each switch: choose the next Random pick and ask the renderer to warm it and the next
    /// preset in the scope (SC-104). Previous is left out: warming costs frame rate, and Previous is
    /// the least used.
    private func planUpcoming() {
        let scopeMembers = walkable   // ACC-002-R5: flagged presets are never warmed or planned
        var generator = SystemRandomNumberGenerator()
        plannedRandom = ScopeStepper.random(scopeMembers, excluding: current, using: &generator)
        var upcoming: [IndexedPreset] = []
        for candidate in [plannedRandom, ScopeStepper.step(scopeMembers, from: current, by: 1)] {
            if let candidate, candidate != current, !upcoming.contains(candidate) { upcoming.append(candidate) }
        }
        loader.prewarm(upcoming)
    }

    private func step(_ delta: Int) async {
        let scopeMembers = walkable
        let pick: IndexedPreset?
        if let current, !scopeMembers.contains(current), members.contains(current) {
            // ACC-002: a flagged current preset is not in the walk; go to the nearest walkable one
            // in the scope's order, so Next and Previous keep their direction.
            pick = neighbour(of: current, in: scopeMembers, by: delta)
        } else {
            pick = ScopeStepper.step(scopeMembers, from: current, by: delta)
        }
        guard let pick else {
            reportEmptyWalk()
            return
        }
        await select(pick)
    }

    /// The first walkable preset after (delta > 0) or before `preset` in the scope's full order,
    /// wrapping; nil when there is none or `preset` is not a member.
    private func neighbour(of preset: IndexedPreset, in walk: [IndexedPreset], by delta: Int) -> IndexedPreset? {
        let all = members
        guard let index = all.firstIndex(of: preset), !walk.isEmpty else { return nil }
        let allowed = Set(walk.map(\.id))
        for offset in 1..<max(all.count, 1) {
            let candidate = all[((index + offset * (delta > 0 ? 1 : -1)) % all.count + all.count) % all.count]
            if allowed.contains(candidate.id) { return candidate }
        }
        return nil
    }

    /// Nothing to walk: a locked scope offers the purchase; a scope whose playable presets are all
    /// flagged says so (ACC-002-R9).
    private func reportEmptyWalk() {
        if settings.effectiveReduceFlashing, !members.isEmpty {
            failureMessage = Self.allFlaggedText
            return
        }
        offerPurchaseIfTheScopeIsLocked()
    }

    /// Spec Edge Cases: a scope with no playable presets because it is locked (a pack or one of its
    /// folders before purchase): Next, Previous and Random offer the purchase sheet.
    private func offerPurchaseIfTheScopeIsLocked() {
        guard !unlocked, members.isEmpty, let library else { return }
        let source: String
        switch scope {
        case .pack(let id), .folder(let id, _): source = id
        default: return
        }
        if library.pack(id: source)?.locked == true { purchaseRequested = true }
    }

    // MARK: - Scope

    private func setScope(_ newScope: PresetScope) {
        guard newScope != scope else { return }
        scope = newScope
        plannedRandom = nil   // planned for the old scope
        settings.presetScope = newScope.storageValue
        if let library { scopeAnnouncer?("\(title(of: newScope, in: library)), \(members.count) presets") }
    }

    /// A stored scope that no longer resolves falls back (spec Edge Cases). A collection scope
    /// resolves while the collections store has that collection (PRE-007-R12).
    private func resolveScope() {
        guard let library else { return }
        let resolves: Bool
        if case .collection(let id) = scope {
            resolves = collectionStore.collection(id: id) != nil
        } else if case .user = scope {
            resolves = !library.userPresets.isEmpty   // PRE-012: an empty My Presets is not a scope to stay in
        } else {
            resolves = library.resolves(scope)
        }
        if !resolves { setScope(unlocked ? .all : .included) }
    }

    // MARK: - Collections (PRE-007)

    enum AddToCollectionResult: Equatable { case added, alreadyThere, failed }

    /// The user's collections, in the user's order.
    var collections: [PresetCollection] {
        _ = collectionsVersion
        return collectionStore.collections
    }

    /// Non-nil when the saved collections come from a newer app version and cannot be used (R15).
    var collectionsUnavailableText: String? {
        collectionStore.availability == .available ? nil : PresetCollectionStore.newerFormatText
    }

    func dismissCollectionsNotice() { collectionsNotice = nil }

    func collection(id: String) -> PresetCollection? {
        _ = collectionsVersion
        return collectionStore.collection(id: id)
    }

    /// What a collection's screen lists: its presets that exist in the library, in the user's
    /// order, locked ones included (the row marks them; R13, R14).
    func collectionListing(_ id: String) -> [IndexedPreset] {
        guard let library, let collection = collection(id: id) else { return [] }
        return library.collectionListing(collection.presetIDs)
    }

    func collectionCount(_ id: String) -> Int { collectionListing(id).count }

    func isInCollection(_ preset: IndexedPreset, _ id: String) -> Bool {
        collection(id: id)?.presetIDs.contains(preset.id) ?? false
    }

    /// Why a name cannot be used (nil = it can); shown while the user types (R9).
    func collectionNameProblem(_ name: String, renaming id: String?) -> String? {
        _ = collectionsVersion
        return collectionStore.nameProblem(name, renaming: id)?.message
    }

    @discardableResult
    func createCollection(named name: String) -> PresetCollection? {
        var created: PresetCollection?
        changeCollections { created = try collectionStore.create(name: name) }
        return created
    }

    @discardableResult
    func renameCollection(_ id: String, to name: String) -> Bool {
        changeCollections { try collectionStore.rename(id, to: name) }
    }

    /// Removes the collection only: presets, favorites and other collections stay (R3). If it was
    /// the scope, the scope falls back and the playing preset keeps playing (R12).
    func deleteCollection(_ id: String) {
        if changeCollections({ try collectionStore.delete(id) }) { resolveScope() }
    }

    @discardableResult
    func addToCollection(_ preset: IndexedPreset, _ id: String) -> AddToCollectionResult {
        var added = false
        guard changeCollections({ added = try collectionStore.add(preset.id, to: id) }) else { return .failed }
        return added ? .added : .alreadyThere
    }

    func removeFromCollection(_ presets: [IndexedPreset], _ id: String) {
        changeCollections { try collectionStore.remove(Set(presets.map(\.id)), from: id) }
    }

    /// A list move of the shown presets (offsets as the list control gives them). Entries that are
    /// not shown keep their places (R14).
    func movePresets(in id: String, fromOffsets: IndexSet, toOffset: Int) {
        let shown = collectionListing(id).map(\.id)
        let order = PresetCollectionOrder.moved(shown, fromOffsets: fromOffsets, toOffset: toOffset)
        guard order != shown else { return }
        changeCollections { try collectionStore.reorderPresets(in: id, visibleOrder: order) }
    }

    /// Move Up (-1) or Move Down (+1): reordering without a drag (R18).
    func movePreset(_ preset: IndexedPreset, in id: String, by delta: Int) {
        guard let index = collectionListing(id).firstIndex(of: preset) else { return }
        movePresets(in: id, fromOffsets: [index], toOffset: delta < 0 ? index - 1 : index + 2)
    }

    func moveCollections(fromOffsets: IndexSet, toOffset: Int) {
        let ids = collections.map(\.id)
        let order = PresetCollectionOrder.moved(ids, fromOffsets: fromOffsets, toOffset: toOffset)
        guard order != ids else { return }
        changeCollections { try collectionStore.reorderCollections(order) }
    }

    func moveCollection(_ id: String, by delta: Int) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        moveCollections(fromOffsets: [index], toOffset: delta < 0 ? index - 1 : index + 2)
    }

    /// "Friday set, 3 presets": a collection row for VoiceOver (R18).
    nonisolated static func collectionRowLabel(name: String, count: Int) -> String {
        "\(name), \(count.formatted(.number.locale(Locale(identifier: "en_US")))) \(count == 1 ? "preset" : "presets")"
    }

    nonisolated static func collectionsRowLabel(count: Int) -> String {
        "Collections, \(count) \(count == 1 ? "collection" : "collections")"
    }

    /// Runs one store change. On a refusal or a failed save nothing changed: the reason goes to
    /// `collectionsMessage` (R8). Views refresh either way, so an optimistic list move snaps back.
    @discardableResult
    private func changeCollections(_ change: () throws -> Void) -> Bool {
        defer { collectionsVersion += 1 }
        do {
            try change()
            plannedRandom = nil   // may have been planned from the old contents
            return true
        } catch {
            collectionsMessage = (error as? PresetCollectionError)?.message ?? PresetCollectionError.saveFailed.message
            return false
        }
    }
}
