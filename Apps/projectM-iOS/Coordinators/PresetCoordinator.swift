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
// * A preset that fails to load leaves the running one on screen, shows "Preset could not be
//   loaded", and is excluded from every scope for the rest of the session (FR-045, FR-118).
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

    private(set) var library: PresetLibrary?
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

    @ObservationIgnored private let store: FavoritesStore
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let loader: any PresetLoading
    @ObservationIgnored private var scopeAnnouncer: ((String) -> Void)?

    init(store: FavoritesStore, settings: AppSettings, loader: any PresetLoading) {
        self.store = store
        self.settings = settings
        self.loader = loader
        scope = settings.presetScope.flatMap(PresetScope.init(storageValue:)) ?? .included
    }

    /// The library is ready (FR-111). Drops favorites that no longer exist and resolves the stored scope.
    func attach(_ library: PresetLibrary) {
        self.library = library
        let missing = store.favorites.filter { library.preset(id: $0) == nil }
        for id in missing { store.toggle(id) }
        if !missing.isEmpty { favoritesVersion += 1 }
        resolveScope()
    }

    func onScopeChange(_ announce: @escaping (String) -> Void) { scopeAnnouncer = announce }

    // MARK: - Entitlement (FR-107, FR-109, FR-119)

    func setUnlocked(_ value: Bool) async {
        guard value != unlocked else { return }
        unlocked = value
        if value {
            setScope(Self.unlockScope)
            if let pending = pendingLockedPreset {
                pendingLockedPreset = nil
                await select(pending, in: Self.unlockScope)
            }
        } else {
            setScope(.included)   // the playing preset keeps playing (FR-109)
        }
    }

    // MARK: - Lists

    /// The preset to start with: the last selected one if it is playable, else the scope's first.
    var initialPreset: IndexedPreset? {
        guard let library else { return nil }
        if let id = store.lastPresetID, let last = library.preset(id: id), isPlayable(last) { return last }
        return members.first
    }

    /// Members of the current scope (what Next/Previous/Random walk).
    var members: [IndexedPreset] {
        guard let library else { return [] }
        _ = favoritesVersion
        return library.members(of: scope, unlocked: unlocked, favorites: Set(store.favorites), excluded: excludedThisSession)
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

    /// "<scope> · <count>" under the preset name (FR-120).
    var scopeLine: String {
        guard let library else { return "" }
        return "\(library.title(of: scope)) · \(members.count)"
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
        await select(preset, in: listScope)
    }

    /// Loads `preset`; on failure keeps the current one, reports it and excludes it for the
    /// session (FR-045, FR-118).
    func select(_ preset: IndexedPreset, in newScope: PresetScope? = nil) async {
        if let newScope { setScope(newScope) }
        do {
            try await loader.load(preset)
            current = preset
            failureMessage = nil
            store.lastPresetID = preset.id
            planUpcoming()
        } catch {
            failureMessage = Self.failureText
            excludedThisSession.insert(preset.id)
        }
    }

    func next() async { await step(1) }
    func previous() async { await step(-1) }

    func random() async {
        let scopeMembers = members
        var pick = plannedRandom
        if pick == nil || pick == current || !scopeMembers.contains(pick!) {
            var generator = SystemRandomNumberGenerator()
            pick = ScopeStepper.random(scopeMembers, excluding: current, using: &generator)
        }
        guard let pick, pick != current else { return }
        await select(pick)
    }

    /// After each switch: choose the next Random pick and ask the renderer to warm it and the next
    /// and previous presets in the scope (SC-104). Random first, then Next, then Previous.
    private func planUpcoming() {
        let scopeMembers = members
        var generator = SystemRandomNumberGenerator()
        plannedRandom = ScopeStepper.random(scopeMembers, excluding: current, using: &generator)
        var upcoming: [IndexedPreset] = []
        for candidate in [plannedRandom, ScopeStepper.step(scopeMembers, from: current, by: 1),
                          ScopeStepper.step(scopeMembers, from: current, by: -1)] {
            if let candidate, candidate != current, !upcoming.contains(candidate) { upcoming.append(candidate) }
        }
        loader.prewarm(upcoming)
    }

    private func step(_ delta: Int) async {
        guard let pick = ScopeStepper.step(members, from: current, by: delta) else {
            if !unlocked, members.isEmpty, case .pack = scope { purchaseRequested = true }
            return
        }
        await select(pick)
    }

    // MARK: - Scope

    private func setScope(_ newScope: PresetScope) {
        guard newScope != scope else { return }
        scope = newScope
        plannedRandom = nil   // planned for the old scope
        settings.presetScope = newScope.storageValue
        if let library { scopeAnnouncer?("\(library.title(of: newScope)), \(members.count) presets") }
    }

    /// A stored scope that no longer resolves falls back (spec Edge Cases).
    private func resolveScope() {
        guard let library, !library.resolves(scope) else { return }
        setScope(unlocked ? .all : .included)
    }
}
