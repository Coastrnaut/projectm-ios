// UITestCollectionFixture.swift — DEBUG only: `-uitestSeedCollections "<name>:<i>,<j>|<name>:"` creates
// those collections, in that order, each holding the Included presets at those positions of the
// Included list (as the browser lists it), in that order; an empty list leaves a collection empty.
// It runs only on a fresh launch (`-uitestResetNotice`), so a relaunch shows what the test changed.
// PresetCollectionsUITests uses it where adding through the add sheet is not what a test checks
// (owner rule 7, 2026-11-13: a UI test under 30 s); other tests there still add through the sheet.
#if DEBUG
import Foundation
import PresetLibrary

@MainActor
enum UITestCollectionFixture {
    static func seedIfRequested(_ presets: PresetCoordinator, defaults: UserDefaults = .standard) {
        guard ProcessInfo.processInfo.arguments.contains("-uitestResetNotice"),
              let spec = defaults.string(forKey: "uitestSeedCollections"), let library = presets.library else { return }
        let included = library.members(of: .included, unlocked: true, favorites: [], excluded: [])
        for entry in spec.split(separator: "|") {
            let parts = entry.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard let name = parts.first, let collection = presets.createCollection(named: String(name)) else { continue }
            let positions = parts.count > 1 ? parts[1].split(separator: ",").compactMap { Int($0) } : []
            for position in positions where included.indices.contains(position) {
                presets.addToCollection(included[position], collection.id)
            }
        }
    }
}
#endif
